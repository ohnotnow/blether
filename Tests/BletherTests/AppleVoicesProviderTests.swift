import AVFoundation
import XCTest
@testable import Blether

final class AppleVoicesProviderTests: XCTestCase {
    private let provider = AppleVoicesProvider()

    func testVoicesAreNonEmptyAndRoundTrip() async throws {
        let voices = try await provider.voices()
        XCTAssertFalse(voices.isEmpty)
        for voice in voices {
            XCTAssertNotNil(AVSpeechSynthesisVoice(identifier: voice.id), voice.id)
        }
    }

    func testDefaultVoiceIsARealVoice() {
        let id = AppleVoicesProvider.defaultVoiceID()
        XCTAssertNotNil(AVSpeechSynthesisVoice(identifier: id), id)
    }

    func testSynthesiseProducesAShortPlayableFile() async throws {
        let clip = try await provider.synthesise("Hello from blether", voice: AppleVoicesProvider.defaultVoiceID())
        defer { try? FileManager.default.removeItem(at: clip.url) }
        let file = try AVAudioFile(forReading: clip.url)
        XCTAssertGreaterThan(file.length, 0)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertGreaterThan(duration, 0.5)
        XCTAssertLessThan(duration, 5)
    }

    func testSinkTimeOutResumesOnceAndIgnoresLaterBuffers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blether-sink-\(UUID().uuidString).caf")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
        let empty = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))

        var sink: SynthesisSink!
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sink = SynthesisSink(url: url, continuation: continuation)
                XCTAssertTrue(sink.timeOut())
            }
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .timedOut)
        }

        XCTAssertTrue(sink.isFinished)
        XCTAssertFalse(sink.timeOut(), "a second time-out must be a no-op")
        sink.append(empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "partial file is deleted")
    }

    func testUnknownVoiceThrows() async {
        do {
            _ = try await provider.synthesise("x", voice: "com.apple.voice.nope")
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .unknownVoice("com.apple.voice.nope"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
