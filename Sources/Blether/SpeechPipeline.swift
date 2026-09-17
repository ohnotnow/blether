import AppKit

/// Joins the listener to the planner, a provider and the playback queue: text in, audio queued.
final class SpeechPipeline: Sendable {
    private let provider: any Provider
    private let queue: PlaybackQueue
    private let settings: AppSettings
    /// Built per reply so an edited endpoint takes effect on the next reply without a relaunch.
    private let makeLLM: @Sendable @MainActor (AppSettings) -> any LLM

    init(provider: any Provider, queue: PlaybackQueue, settings: AppSettings, makeLLM: @escaping @Sendable @MainActor (AppSettings) -> any LLM) {
        self.provider = provider
        self.queue = queue
        self.settings = settings
        self.makeLLM = makeLLM
    }

    /// Everything read from main-actor state, in one hop, at the moment the reply arrives.
    private struct Snapshot: Sendable {
        let generation: Int
        /// nil when the preamble is wanted; otherwise why it is not, for the log.
        let preambleSkipReason: String?
        let speaksMainReply: Bool
        let monologuePersona: Persona?
        let mainPersona: Persona?
        let voices: [Role: String]
        let llm: any LLM
    }

    /// `profile` is the name from the hook URL; nil, blank or unknown means the default profile.
    func speak(_ text: String, profile name: String? = nil) async {
        // Checked on its own before the snapshot: off must cost nothing, and the snapshot builds an LLM client.
        let isEnabled = await MainActor.run { settings.isEnabled }
        guard isEnabled else {
            Log.log("speaking is off, reply dropped")
            return
        }
        let snapshot = await MainActor.run {
            let profile = settings.profile(named: name)
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                Log.log("profile \"\(name)\" not found, using \"\(profile.name)\"")
            }
            return Snapshot(
                generation: queue.generation,
                // Playback rule 4: no preamble when the reply will queue behind audio already playing.
                preambleSkipReason: !settings.speaksPreamble ? "preamble is off" : queue.isPlaying ? "audio already playing" : nil,
                speaksMainReply: settings.speaksMainReply,
                monologuePersona: settings.persona(for: .monologue, in: profile),
                mainPersona: settings.persona(for: .main, in: profile),
                voices: Dictionary(uniqueKeysWithValues: Role.allCases.map { ($0, settings.voiceID(for: $0, in: profile)) }),
                llm: makeLLM(settings)
            )
        }
        let includePreamble = snapshot.preambleSkipReason == nil
        if let reason = snapshot.preambleSkipReason { Log.log("\(reason), skipping the preamble") }
        guard includePreamble || snapshot.speaksMainReply else {
            Log.log("reply is off and the preamble is skipped, nothing to speak")
            return
        }

        let clips = await ReplyPlanner(llm: snapshot.llm).plan(
            text, monologuePersona: snapshot.monologuePersona, mainPersona: snapshot.mainPersona,
            includePreamble: includePreamble, includeMain: snapshot.speaksMainReply, mainCap: provider.maxMainCharacters
        )

        // Synthesise concurrently, but hand clips to the queue in planned order as each becomes ready.
        await withTaskGroup(of: (Int, Result<AudioClip, Error>).self) { group in
            for (index, clip) in clips.enumerated() {
                let voice = snapshot.voices[clip.role] ?? KokoroProvider.defaultVoiceID
                group.addTask { [provider] in
                    do { return (index, .success(try await provider.synthesise(clip.text, voice: voice))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var ready: [Int: Result<AudioClip, Error>] = [:]
            var next = 0
            for await (index, result) in group {
                ready[index] = result
                while let result = ready.removeValue(forKey: next) {
                    await deliver(clips[next], result, generation: snapshot.generation)
                    next += 1
                }
            }
        }
    }

    private func deliver(_ clip: PlannedClip, _ result: Result<AudioClip, Error>, generation: Int) async {
        switch result {
        case .success(let audio):
            await queue.enqueue(audio, generation: generation)
        case .failure(let error):
            Log.log("synthesis failed (\(provider.name), \(clip.role.rawValue)): \(error)")
            // The preamble is a garnish; losing the reply itself must be heard.
            if clip.role == .main { await MainActor.run { NSSound.beep() } }
        }
    }
}
