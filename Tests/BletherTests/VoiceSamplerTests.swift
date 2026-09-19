import XCTest
@testable import Blether

/// Counts synthesis calls and writes a real file, so the sampler has something to move and copy.
private final class CountingProvider: Provider, @unchecked Sendable {
    let name = "counting"
    let maxMainCharacters = 3000
    private let lock = NSLock()
    private var texts: [String] = []
    var calls: [String] { lock.withLock { texts } }
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        lock.withLock { texts.append("\(voice): \(text)") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: url)
        return AudioClip(url: url)
    }
}

@MainActor
final class VoiceSamplerTests: XCTestCase {
    private let provider = CountingProvider()
    private let fakes = FakePlayers()
    private var directory: URL!
    private var sampler: VoiceSampler!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("blether-samples-\(UUID().uuidString)")
        sampler = VoiceSampler(registry: ProviderRegistry([provider]), directory: directory, queue: PlaybackQueue(makePlayer: fakes.make))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSecondPlayOfAVoiceComesFromTheCache() async throws {
        try await sampler.play(providerID: "counting", voiceID: "v1", name: "Siwis")
        try await sampler.play(providerID: "counting", voiceID: "v1", name: "Siwis")
        XCTAssertEqual(provider.calls, ["v1: Hello, I'm Siwis. This is how I sound."])
        XCTAssertEqual(fakes.all.count, 2, "played twice")
        XCTAssertTrue(fakes.all[1].played)

        try await sampler.play(providerID: "counting", voiceID: "v2", name: "v2")
        XCTAssertEqual(provider.calls.count, 2, "a different voice is synthesised")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testTheCacheSurvivesPlaybackFinishing() async throws {
        try await sampler.play(providerID: "counting", voiceID: "v1", name: "Siwis")
        let playedURL = fakes.all[0].url
        XCTAssertNotEqual(playedURL.deletingLastPathComponent(), directory, "the queue gets a copy")
        XCTAssertTrue(sampler.isPlaying)
        fakes.all[0].finish()
        XCTAssertFalse(sampler.isPlaying)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playedURL.path), "the copy is gone")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1, "the original stays")
    }

    func testFileStemIsSafeAndChangesWithTheLine() {
        let a = VoiceSampler.fileStem(providerID: "mistral", voiceID: "fr/slug one", text: "x")
        XCTAssertFalse(a.contains("/"))
        XCTAssertFalse(a.contains(" "))
        XCTAssertTrue(a.hasPrefix("mistral-fr%2Fslug%20one-"))
        XCTAssertNotEqual(a, VoiceSampler.fileStem(providerID: "mistral", voiceID: "fr/slug one", text: "y"))
    }
}
