import AVFoundation

/// What the background stream needs from a player. The real one wraps AVPlayer; tests use a fake.
@MainActor
protocol StreamPlayer: AnyObject {
    func play(_ url: URL)
    func pause()
    func resume()
    func stop()
    var volume: Float { get set }
    /// nil until the item is ready. True when its duration is indefinite, which is how a live stream shows.
    var isLive: Bool? { get }
    /// Called when the current URL fails to start, or fails part way through.
    var onFailed: (() -> Void)? { get set }
}

/// Plays the user's one background stream and makes room for blether's voice (ant blether-pHUqx):
/// a live stream fades down and back up, a recording pauses and resumes so nothing is missed.
@MainActor
final class BackgroundStream {
    /// Starting guesses, the user's (2026-09-26), to be tuned by ear.
    static let duckedVolume: Float = 0.25
    static let fadeSeconds = 2.0
    private static let fadeSteps = 20

    private let player: any StreamPlayer
    private let status: @MainActor (String?) -> Void
    private let sleep: @Sendable (Double) async -> Void
    private var urls: [URL] = []
    private var index = 0
    private var ducked = false
    private var pausedForDuck = false
    /// The fade in progress; internal so tests can wait for it.
    private(set) var fade: Task<Void, Never>?

    private(set) var isPlaying = false

    init(player: any StreamPlayer = AVStreamPlayer(),
         status: @escaping @MainActor (String?) -> Void,
         sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.player = player
        self.status = status
        self.sleep = sleep
        player.onFailed = { [weak self] in self?.failed() }
    }

    /// Plays the first URL; each failure moves on to the next, once through the list (mirrors from a .pls).
    func start(urls: [URL]) {
        stop()
        guard let first = urls.first else { return }
        self.urls = urls
        index = 0
        isPlaying = true
        status(nil)
        Log.log("stream: playing \(first.absoluteString)")
        player.play(first)
    }

    func stop() {
        fade?.cancel()
        fade = nil
        if isPlaying { player.stop() }
        isPlaying = false
        ducked = false
        pausedForDuck = false
        player.volume = 1
    }

    /// Idempotent: the ducker calls it on every busy tick.
    func duck() {
        guard isPlaying, !ducked else { return }
        ducked = true
        // Not yet known counts as live: fading is harmless, pausing a radio stream is not.
        if player.isLive == false {
            pausedForDuck = true
            player.pause()
        } else {
            fadeTo(Self.duckedVolume)
        }
    }

    func restore() {
        guard isPlaying, ducked else { return }
        ducked = false
        if pausedForDuck {
            pausedForDuck = false
            player.resume()
        } else {
            fadeTo(1)
        }
    }

    /// Fades to silence, stops, and shows `message` as the status line, which also turns the switch off.
    /// A duck during the fade cancels it and the stream plays on: something from Claude arrived.
    func fadeOutAndStop(saying message: String) {
        guard isPlaying else { return }
        Log.log("stream: \(message)")
        fadeTo(0) { [weak self] in
            self?.stop()
            self?.status(message)
        }
    }

    private func failed() {
        guard isPlaying else { return }
        index += 1
        guard index < urls.count else {
            let host = urls.first?.host() ?? "the stream"
            Log.log("stream: nothing in the list would play")
            stop()
            status("Stream: could not reach or play \(host)")
            return
        }
        Log.log("stream: failed, trying \(urls[index].absoluteString)")
        player.play(urls[index])
    }

    private func fadeTo(_ target: Float, then done: (@MainActor () -> Void)? = nil) {
        fade?.cancel()
        let from = player.volume
        let steps = Self.fadeSteps
        let sleep = self.sleep
        fade = Task { [weak self] in
            for step in 1...steps {
                await sleep(Self.fadeSeconds / Double(steps))
                guard !Task.isCancelled, let self else { return }
                self.player.volume = from + (target - from) * Float(step) / Float(steps)
            }
            done?()
        }
    }
}

@MainActor
final class AVStreamPlayer: StreamPlayer {
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    var onFailed: (() -> Void)?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var isLive: Bool? {
        guard let item = player.currentItem, item.status == .readyToPlay else { return nil }
        return item.duration.isIndefinite
    }

    func play(_ url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Log.log("stream: \(item.error.map { "\($0)" } ?? "failed")")
            Task { @MainActor in self?.onFailed?() }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onFailed?() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func pause() { player.pause() }
    func resume() { player.play() }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
    }
}
