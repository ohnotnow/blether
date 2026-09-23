import CryptoKit
import Foundation
import Observation

/// Speaks a short fixed line in a chosen voice so a person can hear it while choosing (the user's ask,
/// 2026-09-18), and keeps each sample on disk so an API voice is billed once (ant blether-bREz9).
/// Owns its own playback queue: the reply queue's finish handlers arm the ears, and its stop() drops
/// clips by generation, and a sample wants neither.
@MainActor @Observable
final class VoiceSampler {
    static let line = "Hello, I'm %@. This is how I sound."

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let queue: PlaybackQueue
    /// Stored, not read off the queue, so the view re-renders when a sample ends.
    private(set) var isPlaying = false
    /// Voice ids being synthesised right now, so a second press waits rather than paying twice.
    private(set) var inFlight: Set<String> = []

    /// ~/Library/Application Support/blether/samples by default, beside the speech model.
    init(registry: ProviderRegistry, directory: URL? = nil, queue: PlaybackQueue = PlaybackQueue()) {
        self.registry = registry
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("blether/samples", isDirectory: true)
        self.queue = queue
    }

    func stop() { queue.stop() }

    /// Plays the sample for `voice` under `providerID`, synthesising it first if it is not cached.
    /// `name` is what the line calls the voice: the list's name, or the raw id when the list has none.
    /// `variant` is anything else that changes the sound under the same id (a Breeze design's
    /// description and quality), so an edit makes a fresh sample instead of replaying the old one.
    func play(providerID: String, voiceID: String, name: String, variant: String? = nil) async throws {
        let text = String(format: Self.line, name)
        let key = "\(providerID)-\(voiceID)"
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let cached = try await cachedFile(providerID: providerID, voiceID: voiceID, text: text, variant: variant)
        // The queue deletes what it plays, so it gets a copy and the cache keeps the original.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(cached.pathExtension)")
        try FileManager.default.copyItem(at: cached, to: copy)
        queue.stop()
        isPlaying = true
        queue.enqueue(AudioClip(url: copy)) { [weak self] in self?.isPlaying = false }
    }

    /// The cached sample, synthesised and moved into the cache on a miss. Any extension the provider
    /// wrote is kept, since the player decodes by it.
    private func cachedFile(providerID: String, voiceID: String, text: String, variant: String?) async throws -> URL {
        let stem = Self.fileStem(providerID: providerID, voiceID: voiceID, text: text, variant: variant)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let hit = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.deletingPathExtension().lastPathComponent == stem }) {
            return hit
        }
        let clip = try await registry.provider(id: providerID).synthesise(text, voice: voiceID, language: nil, tone: nil)
        let file = directory.appendingPathComponent(stem).appendingPathExtension(clip.url.pathExtension)
        try FileManager.default.moveItem(at: clip.url, to: file)
        Log.log("sample: cached \(providerID) \(voiceID) at \(file.lastPathComponent)")
        return file
    }

    /// provider-voice-hash: the id percent-encoded so a Mistral slug or anything with a slash is a safe
    /// file name, and the first eight hex of the line's SHA-256 so a reworded line makes a fresh sample.
    /// A variant joins the line in the hash; nil leaves the hash as it was, so existing caches stay valid.
    static func fileStem(providerID: String, voiceID: String, text: String, variant: String? = nil) -> String {
        let safeVoice = voiceID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? voiceID
        let hash = SHA256.hash(data: Data((text + (variant.map { "\n" + $0 } ?? "")).utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(providerID)-\(safeVoice)-\(hash)"
    }
}
