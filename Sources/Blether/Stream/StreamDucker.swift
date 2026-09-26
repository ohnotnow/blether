import Foundation

/// Watches for blether being busy (working on a reply, playing one, or listening) and ducks the
/// background stream at once; brings it back only after a spell of quiet, so the gap between the
/// preamble and the reply does not bounce the music up.
@MainActor
final class StreamDucker {
    /// A starting guess, like the fade (ant blether-pHUqx).
    static let quietGrace = 2.0
    static let tick = 0.25

    private let stream: BackgroundStream
    private let isBusy: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private var quietSince: Date?
    private var timer: Timer?

    init(stream: BackgroundStream, isBusy: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date = { Date() }) {
        self.stream = stream
        self.isBusy = isBusy
        self.now = now
    }

    /// Runs the check every tick while the app lives; a check with the stream off costs nothing.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        guard stream.isPlaying else {
            quietSince = nil
            return
        }
        if isBusy() {
            quietSince = nil
            stream.duck()
            return
        }
        let since = quietSince ?? now()
        quietSince = since
        if now().timeIntervalSince(since) >= Self.quietGrace { stream.restore() }
    }
}
