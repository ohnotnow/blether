import Foundation

/// What the speech pipeline needs from the ears: open them for a session once a reply has played.
@MainActor
protocol EarsArming: AnyObject, Sendable {
    func arm(for session: SessionKey)
}

/// Owns the one recording that may be live, the transcriber, and the target it will answer to.
/// The privacy gate lives here: `arm` reads the setting every time and never caches it.
@MainActor
final class Ears: EarsArming {
    private let settings: AppSettings
    private let microphone: any MicrophoneSource
    private let transcriber: any Transcribing
    private let sounds: any Sounds
    private let status: @MainActor (String?) -> Void
    /// Hands a transcript to the session it was armed for. The channel server provides this.
    private let deliver: @MainActor (String, SessionKey) -> Void
    private var current: Recording?
    private var arming = false

    init(settings: AppSettings, microphone: any MicrophoneSource, transcriber: any Transcribing, sounds: any Sounds,
         status: @escaping @MainActor (String?) -> Void, deliver: @escaping @MainActor (String, SessionKey) -> Void) {
        self.settings = settings
        self.microphone = microphone
        self.transcriber = transcriber
        self.sounds = sounds
        self.status = status
        self.deliver = deliver
    }

    var isListening: Bool { current != nil || arming }

    /// Fetch and load the model ahead of the first reply. Failures are shown, not thrown: the next arm retries.
    func warmUp() async {
        do { try await transcriber.warmUp() } catch { Log.log("ears: warm-up failed: \(error)") }
    }

    func arm(for session: SessionKey) {
        guard settings.listensAfterReply else {
            Log.log("listening is off, not arming")
            return
        }
        guard !isListening else {
            Log.log("already listening, second reply loses")
            return
        }
        arming = true
        Task { await open(for: session) }
    }

    /// The stop hotkey, or listening switched off: close the microphone without sending anything.
    func cancel() {
        current?.cancel()
    }

    private func open(for session: SessionKey) async {
        defer { arming = false }
        do { try await transcriber.warmUp() } catch {
            Log.log("ears: cannot listen, \(error)")
            sounds.play(.cancelled)
            return
        }
        // The download may have taken a while; the gate is re-read, and a stop meanwhile wins.
        guard settings.listensAfterReply else {
            Log.log("listening switched off while the ears were getting ready")
            return
        }
        let recording = Recording(microphone: microphone, sounds: sounds, deviceID: settings.microphoneID) { [weak self] outcome in
            self?.finished(outcome, for: session)
        }
        do {
            let choice = try recording.start()
            if case .fallback = choice { status(Microphone.describe(choice)) } else { status(nil) }
            current = recording
        } catch {
            Log.log("ears: microphone failed to open: \(error)")
            status("Ears: microphone failed to open")
            sounds.play(.cancelled)
        }
    }

    private func finished(_ outcome: Recording.Outcome, for session: SessionKey) {
        current = nil
        switch outcome {
        case .cancelled(let reason):
            Log.log("ears: nothing sent (\(reason))")
        case .transcribe(let samples):
            Task { await transcribe(samples, for: session) }
        }
    }

    private func transcribe(_ samples: [Float], for session: SessionKey) async {
        do {
            let text = try await transcriber.transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                Log.log("ears: heard nothing worth sending")
                sounds.play(.cancelled)
                return
            }
            deliver(text, session)
        } catch {
            Log.log("ears: transcription failed: \(error)")
            status("Ears: \(error)")
            sounds.play(.cancelled)
        }
    }
}
