import XCTest
@testable import Blether

@MainActor
final class StreamDuckerTests: XCTestCase {
    private var player: FakeStreamPlayer!
    private var stream: BackgroundStream!
    private var busy = false
    private var clock = Date(timeIntervalSince1970: 0)
    private var ducker: StreamDucker!

    override func setUp() async throws {
        player = FakeStreamPlayer()
        player.isLive = false  // pause and resume are counted, so no waiting on fades
        stream = BackgroundStream(player: player, status: { _ in }, sleep: { _ in })
        busy = false
        clock = Date(timeIntervalSince1970: 0)
        ducker = StreamDucker(stream: stream, isBusy: { [unowned self] in busy }, now: { [unowned self] in clock })
        stream.start(urls: [URL(string: "http://example.com/podcast.mp3")!])
    }

    private func wait(_ seconds: Double) {
        clock += seconds
        ducker.check()
    }

    func testBusyDucksAtOnce() {
        busy = true
        ducker.check()
        XCTAssertEqual(player.paused, 1)
    }

    func testQuietShorterThanTheGraceDoesNotRestore() {
        busy = true
        ducker.check()
        busy = false
        ducker.check()
        wait(StreamDucker.quietGrace - 0.5)
        XCTAssertEqual(player.resumed, 0)
    }

    func testQuietLongerThanTheGraceRestoresOnce() {
        busy = true
        ducker.check()
        busy = false
        ducker.check()
        wait(StreamDucker.quietGrace)
        wait(1)
        XCTAssertEqual(player.resumed, 1)
    }

    func testBusyInsideTheGraceCancelsTheRestore() {
        busy = true
        ducker.check()
        busy = false
        ducker.check()
        wait(1)
        busy = true
        wait(0.25)
        busy = false
        wait(1)
        XCTAssertEqual(player.resumed, 0)
        XCTAssertEqual(player.paused, 1)
    }

    func testNothingHappensWhileTheStreamIsOff() {
        stream.stop()
        busy = true
        ducker.check()
        XCTAssertEqual(player.paused, 0)
    }
}
