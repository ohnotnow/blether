import AVFoundation
import AppKit

/// What the queue needs from a player. The real one wraps AVAudioPlayer; tests use a fake.
@MainActor
protocol Player: AnyObject {
    /// False when playback could not start (AVAudioPlayer.play returns false); the queue moves on.
    func play() -> Bool
    func stop()
    /// Called once when the clip ends, whether it finished, or failed to decode.
    var onFinish: (() -> Void)? { get set }
}

enum PlaybackError: Error {
    case couldNotStart
}

/// Plays clips one at a time in arrival order. Owns the clip files and deletes them when done.
@MainActor
final class PlaybackQueue {
    private let makePlayer: @MainActor (URL) throws -> any Player
    private var pending: [AudioClip] = []
    private var current: (player: any Player, clip: AudioClip)?
    /// Called once when that clip finishes playing, or when `stop()` kills it: the user's decision
    /// (2026-09-19) is that stopping a reply skips straight to listening, as the old loop did. Not
    /// called when a clip fails to start.
    private var finishHandlers: [URL: @MainActor () -> Void] = [:]

    /// Bumped by `stop()`. A clip synthesised under an older generation is dropped on arrival.
    private(set) var generation = 0

    var isPlaying: Bool { current != nil }

    init(makePlayer: @escaping @MainActor (URL) throws -> any Player = { try AVAudioPlayerAdapter(url: $0) }) {
        self.makePlayer = makePlayer
    }

    func enqueue(_ clip: AudioClip, generation: Int? = nil, onFinished: (@MainActor () -> Void)? = nil) {
        if let generation, generation != self.generation {
            Log.log("dropping clip synthesised before stop: \(clip.url.lastPathComponent)")
            remove(clip)
            return
        }
        if let onFinished { finishHandlers[clip.url] = onFinished }
        pending.append(clip)
        if current == nil { playNext() }
    }

    /// Kill the current clip and drop everything queued. The finish handler of the last queued clip
    /// that has one still runs, so a stopped reply arms the ears just as a finished one would.
    func stop() {
        generation += 1
        let skippedTo = ([current?.clip].compactMap { $0 } + pending).last { finishHandlers[$0.url] != nil }.flatMap { finishHandlers[$0.url] }
        if let current {
            current.player.stop()
            remove(current.clip)
        }
        current = nil
        pending.forEach(remove)
        pending.removeAll()
        finishHandlers.removeAll()
        skippedTo?()
    }

    private func playNext() {
        guard current == nil, !pending.isEmpty else { return }
        let clip = pending.removeFirst()
        do {
            let player = try makePlayer(clip.url)
            player.onFinish = { [weak self] in self?.finished(clip) }
            current = (player, clip)
            guard player.play() else {
                current = nil
                throw PlaybackError.couldNotStart
            }
        } catch {
            Log.log("playback failed for \(clip.url.lastPathComponent): \(error)")
            NSSound.beep()
            remove(clip)
            playNext()
        }
    }

    private func finished(_ clip: AudioClip) {
        guard current?.clip.url == clip.url else { return }
        current = nil
        let handler = finishHandlers.removeValue(forKey: clip.url)
        remove(clip)
        playNext()
        handler?()
    }

    private func remove(_ clip: AudioClip) {
        finishHandlers.removeValue(forKey: clip.url)
        try? FileManager.default.removeItem(at: clip.url)
    }
}

@MainActor
final class AVAudioPlayerAdapter: NSObject, Player, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish?() }
    }

    /// Without this a decode error would leave the queue waiting on a clip that never finishes.
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Log.log("playback decode error: \(error.map { "\($0)" } ?? "unknown")")
        Task { @MainActor in self.onFinish?() }
    }
}
