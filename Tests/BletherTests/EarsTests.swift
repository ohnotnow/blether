import XCTest
@testable import Blether

/// Main-actor isolated so its counters need no lock; the protocol's async methods hop here.
@MainActor
final class FakeTranscriber: Transcribing {
    private(set) var warmUps = 0
    private(set) var heard: [[Float]] = []
    var reply = "hello there"
    var warmUpFailure: Error?

    func warmUp() async throws {
        warmUps += 1
        if let warmUpFailure { throw warmUpFailure }
    }

    func transcribe(_ pcm: [Float]) async throws -> String {
        heard.append(pcm)
        return reply
    }
}

@MainActor
final class EarsTests: XCTestCase {
    private let suite = "uk.ohnotnow.blether.tests.\(UUID().uuidString)"
    private lazy var settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, keychain: KeychainStore(service: "uk.ohnotnow.blether.tests.ears"))
    private let mic = FakeMicrophone()
    private let transcriber = FakeTranscriber()
    private let sounds = FakeSounds()
    private var statuses: [String?] = []
    private var delivered: [(String, SessionKey)] = []
    private let speech = [Float](repeating: 0.1, count: Microphone.chunkSize)
    private let quiet = [Float](repeating: 0, count: Microphone.chunkSize)
    private let session = SessionKey(id: "s-1", pid: 1)

    private lazy var ears = Ears(settings: settings, microphone: mic, transcriber: transcriber, sounds: sounds,
                                 status: { [weak self] in self?.statuses.append($0) },
                                 deliver: { [weak self] text, key in self?.delivered.append((text, key)) })

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func testGateOffNeverOpensTheMicrophoneEvenWhenAsked() async {
        ears.arm(for: session)
        await settle()
        XCTAssertEqual(mic.started, 0)
        XCTAssertEqual(transcriber.warmUps, 0)
        XCTAssertEqual(sounds.played, [])
    }

    func testArmWarmsUpOpensTheMicAndPlaysTheCue() async {
        settings.listensAfterReply = true
        ears.arm(for: session)
        await settle()
        XCTAssertEqual(transcriber.warmUps, 1)
        XCTAssertEqual(mic.started, 1)
        XCTAssertEqual(sounds.played, [.armed])
        XCTAssertTrue(ears.isListening)
    }

    func testSecondArmWhileListeningIsRefused() async {
        settings.listensAfterReply = true
        ears.arm(for: session)
        await settle()
        ears.arm(for: SessionKey(id: "s-2", pid: 2))
        await settle()
        XCTAssertEqual(mic.started, 1)
    }

    func testTranscriptIsDeliveredToTheSessionItWasArmedFor() async {
        settings.listensAfterReply = true
        ears.arm(for: session)
        await settle()
        mic.hear(speech, seconds: 1)
        mic.hear(quiet, seconds: 3)
        await settle()
        XCTAssertEqual(delivered.map(\.0), ["hello there"])
        XCTAssertEqual(delivered.map(\.1), [session])
        XCTAssertEqual(transcriber.heard.count, 1)
        XCTAssertEqual(sounds.played, [.armed, .sent])
        XCTAssertFalse(ears.isListening)
    }

    func testEmptyTranscriptIsNotDeliveredAndSaysSo() async {
        settings.listensAfterReply = true
        transcriber.reply = "   "
        ears.arm(for: session)
        await settle()
        mic.hear(speech, seconds: 1)
        mic.hear(quiet, seconds: 3)
        await settle()
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(sounds.played, [.armed, .sent, .cancelled])
    }

    /// The 2026-09-20 review: the channel's `handsfree off` flipped the setting and left the mic open.
    func testSetListeningOffClosesAnOpenMic() async {
        setListening(true, settings: settings, ears: ears)
        await settle()
        XCTAssertEqual(transcriber.warmUps, 1, "on warms the model")
        ears.arm(for: session)
        await settle()
        XCTAssertTrue(ears.isListening)
        setListening(false, settings: settings, ears: ears)
        await settle()
        XCTAssertFalse(settings.listensAfterReply)
        XCTAssertFalse(ears.isListening)
        XCTAssertEqual(mic.stopped, 1)
        XCTAssertTrue(delivered.isEmpty)
    }

    func testCancelClosesTheMicWithoutDelivering() async {
        settings.listensAfterReply = true
        ears.arm(for: session)
        await settle()
        mic.hear(speech, seconds: 1)
        ears.cancel()
        await settle()
        XCTAssertEqual(mic.stopped, 1)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertFalse(ears.isListening)
    }

    func testSwitchingOffDuringWarmUpDoesNotOpenTheMic() async {
        settings.listensAfterReply = true
        let gate = settings
        let slow = SlowTranscriber { gate.listensAfterReply = false }
        let ears = Ears(settings: settings, microphone: mic, transcriber: slow, sounds: sounds, status: { _ in }, deliver: { _, _ in })
        ears.arm(for: session)
        await settle()
        XCTAssertEqual(mic.started, 0)
    }

    func testWarmUpFailurePlaysTheCancelledCueAndDoesNotOpenTheMic() async {
        settings.listensAfterReply = true
        transcriber.warmUpFailure = ModelStoreError.badStatus(503)
        ears.arm(for: session)
        await settle()
        XCTAssertEqual(mic.started, 0)
        XCTAssertEqual(sounds.played, [.cancelled])
        XCTAssertFalse(ears.isListening)
    }

    func testAbsentMicrophoneFallbackIsShownInTheStatus() async {
        settings.listensAfterReply = true
        settings.microphoneID = "USB-9"
        mic.choice = .fallback(missingID: "USB-9")
        ears.arm(for: session)
        await settle()
        XCTAssertEqual(statuses, ["microphone USB-9 not connected, using the system default"])
    }
}

/// Flips something during warm-up, to test the gate being re-read afterwards.
@MainActor
final class SlowTranscriber: Transcribing {
    private let during: @MainActor () -> Void
    init(during: @escaping @MainActor () -> Void) { self.during = during }
    func warmUp() async throws { during() }
    func transcribe(_ pcm: [Float]) async throws -> String { "" }
}
