import XCTest
@testable import Blether

@MainActor
final class FakeStreamPlayer: StreamPlayer {
    var played: [URL] = []
    var paused = 0
    var resumed = 0
    var stopped = 0
    var volume: Float = 1
    var isLive: Bool? = true
    var onFailed: (() -> Void)?
    func play(_ url: URL) { played.append(url) }
    func pause() { paused += 1 }
    func resume() { resumed += 1 }
    func stop() { stopped += 1 }
    func fail() { onFailed?() }
}

@MainActor
final class BackgroundStreamTests: XCTestCase {
    private let a = URL(string: "http://a.example.com/live")!
    private let b = URL(string: "http://b.example.com/live")!
    private var player: FakeStreamPlayer!
    private var statuses: [String?] = []
    private var stream: BackgroundStream!

    override func setUp() async throws {
        player = FakeStreamPlayer()
        statuses = []
        stream = BackgroundStream(player: player, status: { [weak self] in self?.statuses.append($0) }, sleep: { _ in })
    }

    private func settle() async { await stream.fade?.value }

    func testStartPlaysTheFirstURL() {
        stream.start(urls: [a, b])
        XCTAssertEqual(player.played, [a])
        XCTAssertTrue(stream.isPlaying)
    }

    func testAFailureMovesToTheNextURL() {
        stream.start(urls: [a, b])
        player.fail()
        XCTAssertEqual(player.played, [a, b])
        XCTAssertTrue(stream.isPlaying)
    }

    func testAllFailingStopsAndReportsOnce() {
        stream.start(urls: [a, b])
        player.fail()
        player.fail()
        player.fail()
        XCTAssertFalse(stream.isPlaying)
        XCTAssertEqual(player.played, [a, b])
        XCTAssertEqual(statuses.last, "Stream: could not reach or play a.example.com")
    }

    func testDuckingALiveStreamFadesToAQuarterAndBack() async {
        stream.start(urls: [a])
        stream.duck()
        await settle()
        XCTAssertEqual(player.volume, BackgroundStream.duckedVolume, accuracy: 0.001)
        stream.restore()
        await settle()
        XCTAssertEqual(player.volume, 1, accuracy: 0.001)
        XCTAssertEqual(player.paused, 0)
    }

    func testUnknownLivenessIsTreatedAsLive() async {
        player.isLive = nil
        stream.start(urls: [a])
        stream.duck()
        await settle()
        XCTAssertEqual(player.paused, 0)
        XCTAssertEqual(player.volume, BackgroundStream.duckedVolume, accuracy: 0.001)
    }

    func testDuckingARecordingPausesAndResumes() async {
        player.isLive = false
        stream.start(urls: [a])
        stream.duck()
        XCTAssertEqual(player.paused, 1)
        stream.restore()
        XCTAssertEqual(player.resumed, 1)
        XCTAssertEqual(player.volume, 1)
    }

    func testDuckTwiceRestoreOnce() async {
        player.isLive = false
        stream.start(urls: [a])
        stream.duck()
        stream.duck()
        stream.restore()
        XCTAssertEqual(player.paused, 1)
        XCTAssertEqual(player.resumed, 1)
    }

    func testRestoreWithoutDuckDoesNothing() {
        player.isLive = false
        stream.start(urls: [a])
        stream.restore()
        XCTAssertEqual(player.resumed, 0)
        XCTAssertNil(stream.fade)
    }

    func testStopDuringAFadeLeavesNothingRunning() async {
        stream.start(urls: [a])
        stream.duck()
        stream.stop()
        XCTAssertNil(stream.fade)
        XCTAssertFalse(stream.isPlaying)
        XCTAssertEqual(player.volume, 1)
    }

    func testDuckWhileStoppedDoesNothing() {
        stream.duck()
        XCTAssertEqual(player.paused, 0)
        XCTAssertNil(stream.fade)
    }

    func testFadeOutAndStopStopsThenReports() async {
        stream.start(urls: [a])
        stream.fadeOutAndStop(saying: "gone")
        XCTAssertTrue(stream.isPlaying)  // still fading
        await settle()
        XCTAssertFalse(stream.isPlaying)
        XCTAssertEqual(player.stopped, 1)
        XCTAssertEqual(statuses.last, "gone")
    }

    func testADuckDuringTheFadeOutKeepsItPlaying() async {
        stream.start(urls: [a])
        stream.fadeOutAndStop(saying: "gone")
        stream.duck()
        await settle()
        XCTAssertTrue(stream.isPlaying)
        XCTAssertEqual(player.volume, BackgroundStream.duckedVolume, accuracy: 0.001)
        XCTAssertFalse(statuses.contains("gone"))
    }
}
