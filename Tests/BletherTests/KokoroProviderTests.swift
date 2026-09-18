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
        let clip = try await provider.synthesise("Hello from blether", voice: "af_heart", language: nil, tone: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        let file = try AVAudioFile(forReading: clip.url)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertEqual(file.fileFormat.sampleRate, 24000)
    }

    func testLanguageNamesMapToKokoroCodes() {
        XCTAssertEqual(KokoroProvider.langCode(for: "French"), "f")
        XCTAssertEqual(KokoroProvider.langCode(for: "Chinese (Simplified)"), "z")
        XCTAssertEqual(KokoroProvider.langCode(for: "American English"), "a")
        XCTAssertEqual(KokoroProvider.langCode(for: "english"), "b")
        XCTAssertEqual(KokoroProvider.langCode(for: "Japanese"), "j", "mapped even though the helper lacks the model; it logs and falls back there")
        XCTAssertNil(KokoroProvider.langCode(for: nil))
        XCTAssertNil(KokoroProvider.langCode(for: "Klingon"))
        XCTAssertNil(KokoroProvider.langCode(for: ""))
    }

    func testLanguageReachesTheHelperAsALangCode() async throws {
        provider = try makeProvider()
        await provider.start()
        let french = try await provider.synthesise("Merde", voice: "af_heart", language: "French", tone: nil)
        defer { try? FileManager.default.removeItem(at: french.url) }
        XCTAssertEqual(try String(contentsOf: french.url.appendingPathExtension("lang"), encoding: .utf8), "f")
        let plain = try await provider.synthesise("Hello", voice: "af_heart", language: nil, tone: nil)
        defer { try? FileManager.default.removeItem(at: plain.url) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.url.appendingPathExtension("lang").path), "no lang key on the wire when nil")
    }

    func testRefusedVoiceIsAProviderError() async throws {
        provider = try makeProvider()
        await provider.start()
        do {
            _ = try await provider.synthesise("x", voice: "bad", language: nil, tone: nil)
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .other("unknown voice"))
        }
    }

    func testHangTimesOut() async throws {
        provider = try makeProvider(timeout: .milliseconds(500))
        await provider.start()
        do {
            _ = try await provider.synthesise("hang", voice: "af_heart", language: nil, tone: nil)
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testProviderCapIsThreeThousand() {
        XCTAssertEqual(KokoroProvider(executable: URL(filePath: "/usr/bin/true"), arguments: []) { _ in }.maxMainCharacters, 3000)
    }
}
