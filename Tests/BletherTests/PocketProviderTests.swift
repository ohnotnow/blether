import AVFoundation
import XCTest
@testable import Blether

/// Drives PocketProvider with the fake helper, so no uv or Pocket is needed here.
final class PocketProviderTests: XCTestCase {
    private var provider: PocketProvider!

    private func makeProvider() throws -> PocketProvider {
        PocketProvider(
            executable: URL(filePath: "/usr/bin/python3"),
            arguments: [try HelperProcessTests.fakeScript().path],
            requestTimeout: .seconds(5)
        ) { _ in }
    }

    override func tearDown() {
        provider?.stop()
    }

    func testVoicesComeFromTheHelper() async throws {
        provider = try makeProvider()
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["af_heart", "bm_george"])
    }

    func testSynthesiseStartsTheHelperAndWritesAPlayableWAVWithNoLanguage() async throws {
        provider = try makeProvider()
        let clip = try await provider.synthesise("Hello from blether", voice: "af_heart", language: "French", tone: .sarcasm)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        let file = try AVAudioFile(forReading: clip.url)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.url.path + ".lang"), "Pocket sends no language")
    }
}
