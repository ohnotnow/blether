import AVFoundation
import Foundation
import TranscribeCpp

/// Speech to text. `Transcriber` is the real one over Canary; tests use a fake.
protocol Transcribing: Sendable {
    /// Fetch and load whatever is needed so the first transcription is quick. Safe to call repeatedly.
    func warmUp() async throws
    func transcribe(_ pcm: [Float]) async throws -> String
}

/// Canary 180m flash through the vendored transcribe.cpp binding. One Model kept warm for the life
/// of the app; Session is single-threaded and Model serialises compute, so this actor is the lock.
/// The model is never a global: on Metal it must be released before the process exits.
actor Transcriber: Transcribing {
    /// The language of the person speaking. Canary has no auto-detect; English until asked otherwise (blether-ZP9vQ).
    static let language = "en"

    private let store: ModelStore
    private let onStatus: @Sendable (String?) -> Void
    private var loaded: (model: Model, session: Session)?

    /// `onStatus` carries a download or failure line for the menubar, nil once ready.
    init(store: ModelStore, onStatus: @escaping @Sendable (String?) -> Void) {
        self.store = store
        self.onStatus = onStatus
        Transcribe.setLogHandler { level, message in
            if level == .warn || level == .error { Log.log("transcribe.cpp: \(message)") }
        }
    }

    /// Fetches the model if needed and loads it. The first-ever load on a machine compiles Metal kernels
    /// and takes about ten seconds; later loads take a fraction of a second. Safe to call repeatedly.
    func warmUp() async throws {
        if loaded != nil { return }
        do {
            let url = try await store.ensureModel { line in self.onStatus(line) }
            onStatus("Loading the ears")
            let started = Date()
            let model = try Model(path: url.path)
            let session = try model.session()
            loaded = (model, session)
            Log.log("ears: model loaded in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            onStatus(nil)
        } catch {
            onStatus("Ears: \(error)")
            throw error
        }
    }

    func transcribe(_ pcm: [Float]) async throws -> String {
        try await warmUp()
        guard let loaded else { return "" }
        let started = Date()
        let transcript = try run(loaded.session, pcm)
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.log("ears: \(String(format: "%.1f", Double(pcm.count) / Microphone.sampleRate)) s of audio in \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(Log.preview(text))")
        if text.isEmpty { Self.keepForInspection(pcm) }
        return text
    }

    /// An empty transcript for real audio is a bug somewhere; keep the samples next to the log so they
    /// can be run through the model by hand. One file, overwritten each time.
    static let lastEmptyRecording = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/blether-last-empty.wav")

    private static func keepForInspection(_ pcm: [Float]) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Microphone.sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: pcm.count) }
        do {
            try? FileManager.default.removeItem(at: lastEmptyRecording)
            let file = try AVAudioFile(forWriting: lastEmptyRecording, settings: format.settings)
            try file.write(from: buffer)
            Log.log("ears: kept the audio at \(lastEmptyRecording.path)")
        } catch {
            Log.log("ears: could not keep the audio: \(error)")
        }
    }

    /// Synchronous on purpose: the binding's async `run` would send the non-Sendable Session off this
    /// actor. Blocking the actor for a few hundred milliseconds is the serialisation we want anyway.
    private func run(_ session: Session, _ pcm: [Float]) throws -> Transcript {
        try session.run(pcm, options: RunOptions(language: Self.language))
    }
}
