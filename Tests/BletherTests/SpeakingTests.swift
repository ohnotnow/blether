import XCTest
@testable import Blether

@MainActor
final class SpeakingTests: XCTestCase {
    private let suite = "uk.ohnotnow.blether.tests.\(UUID().uuidString)"
    private lazy var settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, keychain: KeychainStore(service: "uk.ohnotnow.blether.tests.speaking"))
    private let state = AppState()
    private let player = FakeStreamPlayer()
    private lazy var stream = BackgroundStream(player: player, status: { _ in }, sleep: { _ in })

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func testStreamingOnWithNoURLStaysOffAndSaysWhy() {
        settings.streamURL = "  "
        XCTAssertNil(setStreaming(true, settings: settings, stream: stream, state: state))
        XCTAssertFalse(settings.playsStream)
        XCTAssertEqual(state.streamStatus, "Stream: add a stream URL in Settings, General")
    }

    func testStreamingOnWithANonWebURLStaysOffAndSaysWhy() {
        for text in ["not a url", "ftp://example.com/live", "http://"] {
            settings.streamURL = text
            XCTAssertNil(setStreaming(true, settings: settings, stream: stream, state: state), text)
            XCTAssertFalse(settings.playsStream)
            XCTAssertEqual(state.streamStatus, "Stream: the URL must start with http:// or https://", text)
        }
    }

    func testStreamingOnPlaysAndOffStops() async {
        settings.streamURL = "http://example.com/live"
        await setStreaming(true, settings: settings, stream: stream, state: state)?.value
        XCTAssertTrue(settings.playsStream)
        XCTAssertEqual(player.played, [URL(string: "http://example.com/live")!])
        setStreaming(false, settings: settings, stream: stream, state: state)
        XCTAssertFalse(settings.playsStream)
        XCTAssertFalse(stream.isPlaying)
        XCTAssertEqual(player.stopped, 1)
    }

    func testStreamingOnFollowsAPlaylist() async {
        settings.streamURL = "http://example.com/station.pls"
        await setStreaming(true, settings: settings, stream: stream, state: state) { _ in
            Data("[playlist]\nFile1=http://ice.example.com/live\n".utf8)
        }?.value
        XCTAssertEqual(player.played, [URL(string: "http://ice.example.com/live")!])
    }

    func testAStreamIsRememberedOnlyOnceItPlays() async {
        settings.streamURL = " http://example.com/station.pls "
        await setStreaming(true, settings: settings, stream: stream, state: state) { _ in
            Data("[playlist]\nFile1=http://ice.example.com/live\n".utf8)
        }?.value
        XCTAssertEqual(settings.recentStreams, [])
        player.ready()
        XCTAssertEqual(settings.recentStreams, ["http://example.com/station.pls"], "the link as typed, trimmed, not the playlist entry")
    }

    func testAStreamThatFailsIsNotRemembered() async {
        settings.streamURL = "http://example.com/live"
        await setStreaming(true, settings: settings, stream: stream, state: state)?.value
        player.fail()
        XCTAssertEqual(settings.recentStreams, [])
    }

    func testAnUnreadablePlaylistSwitchesBackOff() async {
        settings.streamURL = "http://example.com/station.pls"
        await setStreaming(true, settings: settings, stream: stream, state: state) { _ in throw URLError(.notConnectedToInternet) }?.value
        XCTAssertFalse(settings.playsStream)
        XCTAssertEqual(state.streamStatus?.hasPrefix("Stream: could not reach example.com: "), true)
        XCTAssertEqual(player.played, [])
    }
}
