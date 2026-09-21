import AppKit

/// Joins the listener to the planner, the providers and the playback queue: text in, audio queued.
/// The provider is chosen per reply from the profile the hook named.
final class SpeechPipeline: Sendable {
    private let registry: ProviderRegistry
    private let queue: PlaybackQueue
    private let settings: AppSettings
    /// Built per reply so an edited endpoint takes effect on the next reply without a relaunch.
    private let makeLLM: @Sendable @MainActor (AppSettings) -> any LLM
    /// Opens the microphone after a reply when listening is on. nil in tests that do not care.
    private let ears: (any EarsArming)?
    /// Where spoken clips are copied when "Keep recent clips" is on.
    private let recent: RecentClips

    init(registry: ProviderRegistry, queue: PlaybackQueue, settings: AppSettings, ears: (any EarsArming)? = nil, recent: RecentClips = RecentClips(), makeLLM: @escaping @Sendable @MainActor (AppSettings) -> any LLM) {
        self.registry = registry
        self.queue = queue
        self.settings = settings
        self.ears = ears
        self.recent = recent
        self.makeLLM = makeLLM
    }

    /// One provider for everything; the tests and any single-provider caller.
    convenience init(provider: any Provider, queue: PlaybackQueue, settings: AppSettings, ears: (any EarsArming)? = nil, recent: RecentClips = RecentClips(), makeLLM: @escaping @Sendable @MainActor (AppSettings) -> any LLM) {
        self.init(registry: ProviderRegistry([provider]), queue: queue, settings: settings, ears: ears, recent: recent, makeLLM: makeLLM)
    }

    /// Copies a clip about to be played into the recent folder when the toggle is on. Read at
    /// delivery, like listening, so flipping it mid-reply wins. A failure is log only.
    private func keepIfWanted(_ audio: AudioClip, role: Role) async {
        guard await MainActor.run(body: { settings.keepsRecentClips }) else { return }
        do { try recent.keep(audio, role: role) } catch { Log.log("recent clips: could not keep \(role.rawValue): \(error)") }
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
        let provider: any Provider
        let llm: any LLM
        let classifier: (any ToneClassifier)?
        let pronunciations: [Pronunciation]
    }

    /// `profile` is the name from the hook URL; nil, blank or unknown means the default profile.
    /// `session` is where a spoken answer goes once the last clip has played, when listening is on.
    func speak(_ text: String, profile name: String? = nil, session: SessionKey? = nil) async {
        // Checked on its own before the snapshot: off must cost nothing, and the snapshot builds an LLM client.
        let isEnabled = await MainActor.run { settings.isEnabled }
        guard isEnabled else {
            Log.log("speaking is off, reply dropped")
            return
        }
        let snapshot = await MainActor.run {
            let profile = resolveProfile(named: name)
            let llm = makeLLM(settings)
            return Snapshot(
                generation: queue.generation,
                // Playback rule 3: no preamble while listening is on. Rule 4: none when the reply will queue behind audio already playing.
                preambleSkipReason: !settings.speaksPreamble ? "preamble is off" : settings.listensAfterReply ? "listening is on" : queue.isPlaying ? "audio already playing" : nil,
                speaksMainReply: settings.speaksMainReply,
                monologuePersona: settings.persona(for: .monologue, in: profile),
                mainPersona: settings.persona(for: .main, in: profile),
                voices: Dictionary(uniqueKeysWithValues: Role.allCases.map { ($0, settings.voiceID(for: $0, in: profile)) }),
                provider: registry.provider(id: profile.providerID),
                llm: llm,
                classifier: classifier(for: settings.toneSource, llm: llm),
                pronunciations: settings.pronunciations
            )
        }
        let provider = snapshot.provider
        let includePreamble = snapshot.preambleSkipReason == nil
        if let reason = snapshot.preambleSkipReason { Log.log("\(reason), skipping the preamble") }
        guard includePreamble || snapshot.speaksMainReply else {
            Log.log("reply is off and the preamble is skipped, nothing to speak")
            return
        }

        let clips = await ReplyPlanner(llm: snapshot.llm).plan(
            text, monologuePersona: snapshot.monologuePersona, mainPersona: snapshot.mainPersona,
            includePreamble: includePreamble, includeMain: snapshot.speaksMainReply, mainCap: provider.maxMainCharacters, markupHint: provider.markupHint,
            classifier: snapshot.classifier
        )

        // Synthesise concurrently, but hand clips to the queue in planned order as each becomes ready.
        await withTaskGroup(of: (Int, Result<AudioClip, Error>).self) { group in
            for (index, clip) in clips.enumerated() {
                let voice = snapshot.voices[clip.role] ?? KokoroProvider.defaultVoiceID
                let spoken = Pronunciations.apply(clip.text, snapshot.pronunciations)
                group.addTask { [provider] in
                    do { return (index, .success(try await provider.synthesise(spoken, voice: voice, language: nil, tone: clip.tone))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var ready: [Int: Result<AudioClip, Error>] = [:]
            var next = 0
            for await (index, result) in group {
                ready[index] = result
                while let result = ready.removeValue(forKey: next) {
                    let isLast = next == clips.count - 1
                    await deliver(clips[next], result, generation: snapshot.generation, provider: provider, armAfter: isLast ? session : nil)
                    next += 1
                }
            }
        }
    }

    /// Everything a quip needs from main-actor state, in one hop.
    private struct QuipSnapshot: Sendable {
        let generation: Int
        let persona: Persona?
        let voice: String
        let languages: NotificationLanguages
        let history: [String]
        let provider: any Provider
        let llm: any LLM
        let pronunciations: [Pronunciation]
    }

    /// A Notification hook: one short in-character line, dropped rather than queued when audio is
    /// already playing (playback rule 2, blether-VYQvH). The queue is checked before any LLM work and
    /// again when the clip is ready. A failure beeps; the quip itself is the information.
    func quip(profile name: String? = nil) async {
        let snapshot: QuipSnapshot? = await MainActor.run {
            guard settings.isEnabled else {
                Log.log("speaking is off, notification dropped")
                return nil
            }
            guard settings.speaksNotifications else {
                Log.log("notifications are off, dropped")
                return nil
            }
            guard !queue.isPlaying else {
                Log.log("audio already playing, notification dropped")
                return nil
            }
            let profile = resolveProfile(named: name)
            return QuipSnapshot(
                generation: queue.generation,
                persona: settings.persona(for: .notification, in: profile),
                voice: settings.voiceID(for: .notification, in: profile),
                languages: NotificationLanguages(parsing: settings.notificationLanguages),
                history: settings.recentQuips,
                provider: registry.provider(id: profile.providerID),
                llm: makeLLM(settings),
                pronunciations: settings.pronunciations
            )
        }
        guard let snapshot else { return }
        let provider = snapshot.provider

        guard let quip = await QuipPlanner(llm: snapshot.llm).plan(persona: snapshot.persona, languages: snapshot.languages, history: snapshot.history) else {
            Log.log("notification line failed, beeping")
            await MainActor.run { NSSound.beep() }
            return
        }
        await MainActor.run { settings.rememberQuip(quip.text) }

        let audio: AudioClip
        do {
            audio = try await provider.synthesise(Pronunciations.apply(quip.text, snapshot.pronunciations), voice: snapshot.voice, language: quip.language, tone: nil)
        } catch {
            Log.log("synthesis failed (\(provider.name), notification): \(error)")
            await MainActor.run { NSSound.beep() }
            return
        }
        await keepIfWanted(audio, role: .notification)
        await MainActor.run {
            if queue.isPlaying {
                Log.log("audio started during synthesis, notification dropped")
                try? FileManager.default.removeItem(at: audio.url)
            } else {
                queue.enqueue(audio, generation: snapshot.generation)
            }
        }
    }

    /// Off is nil; Jev reads its key off the main actor like the providers; the LLM path reuses this reply's client.
    @MainActor
    private func classifier(for source: ToneSource, llm: any LLM) -> (any ToneClassifier)? {
        switch source {
        case .off: nil
        case .jev: JevToneClassifier(apiKey: settings.apiKeyReader(for: "jev"))
        case .llm: LLMToneClassifier(llm: llm)
        }
    }

    /// The profile a hook named, or the default, with a log line when the name was not found.
    @MainActor
    private func resolveProfile(named name: String?) -> Profile {
        let profile = settings.profile(named: name)
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
            Log.log("profile \"\(name)\" not found, using \"\(profile.name)\"")
        }
        return profile
    }

    /// `armAfter` is set for the reply's last clip: once it has played, the ears open for that session.
    /// Listening is read here, at delivery, not in the snapshot, so switching it off mid-reply wins.
    private func deliver(_ clip: PlannedClip, _ result: Result<AudioClip, Error>, generation: Int, provider: any Provider, armAfter session: SessionKey?) async {
        let arm: (@MainActor () -> Void)? = await MainActor.run {
            guard let session, let ears, settings.listensAfterReply else { return nil }
            return { ears.arm(for: session) }
        }
        switch result {
        case .success(let audio):
            await keepIfWanted(audio, role: clip.role)
            await queue.enqueue(audio, generation: generation, onFinished: arm)
        case .failure(let error):
            Log.log("synthesis failed (\(provider.name), \(clip.role.rawValue)): \(error)")
            // The preamble is a garnish; losing the reply itself must be heard.
            if clip.role == .main { await MainActor.run { NSSound.beep() } }
            // Nothing will finish playing for this clip, so open the ears now rather than never; unless
            // the user pressed stop meanwhile, when the audio would have been dropped and so is the arming.
            if let arm, await queue.generation == generation { await arm() }
        }
    }
}
