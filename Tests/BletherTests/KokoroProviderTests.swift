import AVFoundation
import XCTest
@testable import Blether

/// Drives KokoroProvider with the fake helper, so no uv or Kokoro is needed here.
final class KokoroProviderTests: XCTestCase {
    private var provider: KokoroProvider!

    private func makeProvider(timeout: Duration = .seconds(5)) throws -> KokoroProvider {
        KokoroProvider(
            executable: URL(filePath: "/usr/bin/python3"),
            arguments: [try HelperProcessTests.fakeScript().path],
            requestTimeout: timeout
        ) { _ in }
    }

    override func tearDown() {
        provider?.stop()
    }

    func testVoicesComeFromTheHelper() async throws {
        provider = try makeProvider()
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["af_heart", "bm_george"])
        XCTAssertEqual(voices.map(\.name), ["Heart", "George"])
    }

    func testSynthesiseWritesAPlayableWAV() async throws {
        provider = try makeProvider()
        await provider.start()
        let clip = try await provider.synthesise("Hello from blether", voice: "af_heart")
        defer { try? FileManager.default.removeItem(at: clip.url) }
        let file = try AVAudioFile(forReading: clip.url)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertEqual(file.fileFormat.sampleRate, 24000)
    }

    func testRefusedVoiceIsAProviderError() async throws {
        provider = try makeProvider()
        await provider.start()
        do {
            _ = try await provider.synthesise("x", voice: "bad")
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .other("unknown voice"))
        }
    }

    func testHangTimesOut() async throws {
        provider = try makeProvider(timeout: .milliseconds(500))
        await provider.start()
        do {
            _ = try await provider.synthesise("hang", voice: "af_heart")
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testProviderCapIsThreeThousand() {
        XCTAssertEqual(KokoroProvider(executable: URL(filePath: "/usr/bin/true"), arguments: []) { _ in }.maxMainCharacters, 3000)
    }
}
