import XCTest
@testable import Blether

@MainActor
final class FakeMicrophone: MicrophoneSource {
    var onSamples: (@Sendable ([Float]) -> Void)?
    var started = 0
    var stopped = 0
    var choice = Microphone.Choice.systemDefault
    var failure: Error?

    func start(deviceID: String?, onSamples: @escaping @Sendable ([Float]) -> Void) throws -> Microphone.Choice {
        if let failure { throw failure }
        started += 1
        self.onSamples = onSamples
        return choice
    }

    func stop() { stopped += 1 }

    /// Pushes `seconds` of one chunk, as the audio thread would, one chunk at a time.
    func hear(_ chunk: [Float], seconds: TimeInterval) {
        let count = Int((seconds * Microphone.sampleRate / Double(Microphone.chunkSize)).rounded(.up))
        for _ in 0..<count { onSamples?(chunk) }
    }
}

/// `play` is main-actor only, so the record needs no lock; the class is Sendable by isolation.
@MainActor
final class FakeSounds: Sounds {
    private(set) var played: [SoundCue] = []
    func play(_ cue: SoundCue) { played.append(cue) }
}

final class RecordingTests: XCTestCase {
    private let quiet = [Float](repeating: 0, count: Microphone.chunkSize)
    private let speech = [Float](repeating: 0.1, count: Microphone.chunkSize)

    @MainActor
    private func makeRecording(mic: FakeMicrophone, sounds: FakeSounds, deviceID: String? = nil) -> (Recording, () async -> Recording.Outcome?) {
        let box = OutcomeBox()
        let recording = Recording(microphone: mic, sounds: sounds, deviceID: deviceID) { box.value = $0 }
        return (recording, {
            for _ in 0..<50 where box.value == nil { await Task.yield() }
            return box.value
        })
    }

    @MainActor final class OutcomeBox { var value: Recording.Outcome? }

    @MainActor func testArmPlaysTheArmedCueAndReportsTheDevice() throws {
        let mic = FakeMicrophone()
        mic.choice = .fallback(missingID: "USB-1")
        let sounds = FakeSounds()
        let (recording, _) = makeRecording(mic: mic, sounds: sounds, deviceID: "USB-1")
        XCTAssertEqual(try recording.start(), .fallback(missingID: "USB-1"))
        XCTAssertEqual(sounds.played, [.armed])
        XCTAssertEqual(mic.started, 1)
    }

    @MainActor func testSpeechThenSilenceSendsEverySampleHeard() async throws {
        let mic = FakeMicrophone()
        let sounds = FakeSounds()
        let (recording, outcome) = makeRecording(mic: mic, sounds: sounds)
        _ = try recording.start()
        mic.hear(speech, seconds: 1)
        mic.hear(quiet, seconds: 3)
        guard case .transcribe(let samples) = await outcome() else { return XCTFail("expected a transcript") }
        // 32 chunks of speech (one second rounds up) end at 1.024 s; the trailing quiet is cut to the margin.
        XCTAssertEqual(samples.count, Int((1.024 + SilenceDetector.margin) * Microphone.sampleRate), "speech plus the margin, not the whole 2.5 s of quiet")
        XCTAssertEqual(sounds.played, [.armed, .sent])
        XCTAssertEqual(mic.stopped, 1)
        withExtendedLifetime(recording) {}
    }

    @MainActor func testLeadingSilenceIsCutOffBeforeTranscription() async throws {
        let mic = FakeMicrophone()
        let sounds = FakeSounds()
        let (recording, outcome) = makeRecording(mic: mic, sounds: sounds)
        _ = try recording.start()
        mic.hear(quiet, seconds: 2)
        mic.hear(speech, seconds: 1)
        mic.hear(quiet, seconds: 3)
        guard case .transcribe(let samples) = await outcome() else { return XCTFail("expected a transcript") }
        let start = 2.048 - 0.032 - SilenceDetector.margin
        let end = 3.04 + SilenceDetector.margin
        XCTAssertEqual(samples.count, Int(end * Microphone.sampleRate) - Int(start * Microphone.sampleRate))
        XCTAssertEqual(samples.first, 0, "the margin before the first word is quiet")
        XCTAssertTrue(samples[Int(0.4 * Microphone.sampleRate)] == 0.1, "and the speech is inside")
        withExtendedLifetime(recording) {}
    }

    func testTrimWithNoRangeKeepsEverything() {
        XCTAssertEqual(Recording.trim([1, 2, 3], to: nil), [1, 2, 3])
    }

    @MainActor func testNoSpeechCancelsWithTheCancelledCue() async throws {
        let mic = FakeMicrophone()
        let sounds = FakeSounds()
        let (recording, outcome) = makeRecording(mic: mic, sounds: sounds)
        _ = try recording.start()
        mic.hear(quiet, seconds: 16)
        let result = await outcome()
        XCTAssertEqual(result, .cancelled("no speech"))
        XCTAssertEqual(sounds.played, [.armed, .cancelled])
        withExtendedLifetime(recording) {}
    }

    @MainActor func testExternalCancelStopsTheMicAndReportsStopped() async throws {
        let mic = FakeMicrophone()
        let sounds = FakeSounds()
        let (recording, outcome) = makeRecording(mic: mic, sounds: sounds)
        _ = try recording.start()
        mic.hear(speech, seconds: 1)
        recording.cancel()
        let result = await outcome()
        XCTAssertEqual(result, .cancelled("stopped"))
        XCTAssertEqual(mic.stopped, 1)
        XCTAssertEqual(sounds.played, [.armed, .cancelled])
        // Chunks still arriving after the cancel change nothing.
        mic.hear(quiet, seconds: 3)
        recording.cancel()
        XCTAssertEqual(mic.stopped, 1)
        XCTAssertEqual(sounds.played, [.armed, .cancelled])
    }

    @MainActor func testMicFailureThrowsWithoutACue() {
        let mic = FakeMicrophone()
        mic.failure = MicrophoneError.noInput
        let sounds = FakeSounds()
        let (recording, _) = makeRecording(mic: mic, sounds: sounds)
        XCTAssertThrowsError(try recording.start())
        XCTAssertEqual(sounds.played, [])
    }
}
