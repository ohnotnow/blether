import XCTest
@testable import Blether

final class SilenceDetectorTests: XCTestCase {
    private let quiet = [Float](repeating: 0, count: Microphone.chunkSize)
    private let speech = [Float](repeating: 0.1, count: Microphone.chunkSize)

    /// Feeds `seconds` worth of one chunk, returning the last verdict.
    private func feed(_ chunk: [Float], seconds: TimeInterval, into detector: inout SilenceDetector) -> SilenceDetector.Verdict {
        var verdict = SilenceDetector.Verdict.listening
        let count = Int((seconds / detector.secondsPerChunk).rounded(.up))
        for _ in 0..<count { verdict = detector.feed(chunk) }
        return verdict
    }

    func testSilenceAloneCancelsOnlyAtFifteenSeconds() {
        var detector = SilenceDetector()
        XCTAssertEqual(feed(quiet, seconds: 14.5, into: &detector), .listening)
        XCTAssertEqual(feed(quiet, seconds: 1, into: &detector), .cancel(reason: "no speech"))
        XCTAssertFalse(detector.heardSpeech)
    }

    func testSpeechThenTrailingSilenceSends() {
        var detector = SilenceDetector()
        XCTAssertEqual(feed(speech, seconds: 1, into: &detector), .listening)
        XCTAssertEqual(feed(quiet, seconds: 2, into: &detector), .listening)
        XCTAssertEqual(feed(quiet, seconds: 1, into: &detector), .send)
        XCTAssertEqual(detector.peakRMS, 0.1, accuracy: 0.0001)
    }

    func testPausesShorterThanTheTrailingSilenceKeepListening() {
        var detector = SilenceDetector()
        for _ in 0..<5 {
            XCTAssertEqual(feed(speech, seconds: 0.5, into: &detector), .listening)
            XCTAssertEqual(feed(quiet, seconds: 2, into: &detector), .listening)
        }
        XCTAssertGreaterThan(detector.elapsed, 12)
    }

    func testCapSendsWhenSpeechWasHeardAndCancelsWhenNot() {
        var talker = SilenceDetector()
        // Speech every second keeps the trailing-silence rule from firing; the cap must.
        var verdict = SilenceDetector.Verdict.listening
        while talker.elapsed < 89 {
            verdict = feed(speech, seconds: 1, into: &talker)
            XCTAssertEqual(verdict, .listening)
        }
        XCTAssertEqual(feed(speech, seconds: 1.5, into: &talker), .send)
    }

    func testSpeechRangeCoversFirstToLastSpeechWithAMarginEitherSide() {
        var detector = SilenceDetector()
        XCTAssertNil(detector.speechRange)
        _ = feed(quiet, seconds: 2, into: &detector)
        _ = feed(speech, seconds: 1, into: &detector)
        _ = feed(quiet, seconds: 3, into: &detector)
        let range = detector.speechRange!
        // 2 s of quiet is 63 chunks (2.016 s); the first speech chunk ends at 2.048 s and the 32nd at 3.04 s.
        XCTAssertEqual(range.lowerBound, 2.048 - 0.032 - SilenceDetector.margin, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 3.04 + SilenceDetector.margin, accuracy: 0.001)
    }

    func testSpeechRangeNeverStartsBeforeZero() {
        var detector = SilenceDetector()
        _ = feed(speech, seconds: 0.1, into: &detector)
        XCTAssertEqual(detector.speechRange?.lowerBound, 0)
    }

    func testQuietChunksBelowThresholdAreNotSpeech() {
        var detector = SilenceDetector()
        let hum = [Float](repeating: 0.005, count: Microphone.chunkSize)
        XCTAssertEqual(feed(hum, seconds: 1, into: &detector), .listening)
        XCTAssertFalse(detector.heardSpeech)
        XCTAssertEqual(SilenceDetector.rms([3, 4]), 3.5355, accuracy: 0.001)
    }
}
