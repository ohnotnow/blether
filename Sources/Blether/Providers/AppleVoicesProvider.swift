import AVFoundation
import Foundation

/// Apple system voices, rendered to a CAF file so the playback queue only ever plays audio.
struct AppleVoicesProvider: Provider {
    let name = "apple"

    func voices() async throws -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { Voice(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    /// First en-GB voice, else the system default. Stands in for settings until they exist.
    static func defaultVoiceID() -> String {
        if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language == "en-GB" }) {
            return voice.identifier
        }
        return AVSpeechSynthesisVoice(language: nil)?.identifier ?? ""
    }

    func synthesise(_ text: String, voice id: String) async throws -> AudioClip {
        guard let voice = AVSpeechSynthesisVoice(identifier: id) else {
            throw ProviderError.unknownVoice(id)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        try await Self.render(text, voice: voice, to: url)
        return AudioClip(url: url)
    }

    /// Longest a single render may take before the clip is abandoned. Text is capped at 800
    /// characters upstream, which renders in a few seconds, so this only ever fires on a hang.
    static let renderTimeout: Duration = .seconds(60)

    /// Kicked off on the main actor: AVSpeechSynthesizer.write delivers nothing unless a main
    /// run loop is alive (verified 2026-09-17 on macOS 26.6). Buffers then arrive via the sink.
    @MainActor
    private static func render(_ text: String, voice: AVSpeechSynthesisVoice, to url: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        var watchdog: Task<Void, Never>?
        defer { watchdog?.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let sink = SynthesisSink(url: url, continuation: continuation)
            synthesizer.write(utterance) { buffer in
                sink.append(buffer)
            }
            // If the synthesizer never delivers its completion buffer the continuation would leak
            // and the whole reply would hang behind it, so give up after a while.
            watchdog = Task { @MainActor in
                try? await Task.sleep(for: renderTimeout)
                guard !Task.isCancelled, sink.timeOut() else { return }
                synthesizer.stopSpeaking(at: .immediate)
                Log.log("synthesis timed out after \(renderTimeout)")
            }
        }
        // The synthesizer must outlive the write; without this it can be released mid-render.
        withExtendedLifetime(synthesizer) {}
    }
}

/// Appends PCM buffers from one write call to a file and resumes the continuation exactly once.
/// Locked rather than actor-isolated because the callback thread is not documented.
final class SynthesisSink: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var continuation: CheckedContinuation<Void, Error>?
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0

    init(url: URL, continuation: CheckedContinuation<Void, Error>) {
        self.url = url
        self.continuation = continuation
    }

    /// True once the continuation has been resumed, by whichever path got there first.
    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation == nil
    }

    func append(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        // The empty completion buffer arrives twice on macOS 26; ignore anything after the first.
        guard continuation != nil, let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            if frames == 0 {
                finish(throwing: ProviderError.noAudio)
            } else {
                finish(throwing: nil)
            }
            return
        }
        do {
            if file == nil {
                // Format comes from the first buffer: voices differ (Daniel 22050 Hz, Eddy 16000 Hz).
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            frames += AVAudioFramePosition(pcm.frameLength)
        } catch {
            finish(throwing: error)
        }
    }

    /// Gives up on the render. Returns false if it had already finished, so the caller knows
    /// whether there is a synthesizer to stop.
    func timeOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil else { return false }
        finish(throwing: ProviderError.timedOut)
        return true
    }

    /// Resumes the continuation exactly once. Caller holds the lock. A thrown error deletes the file.
    private func finish(throwing error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        file = nil
        if let error {
            try? FileManager.default.removeItem(at: url)
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
