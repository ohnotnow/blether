import XCTest
@testable import Blether

final class ElevenLabsProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = ElevenLabsProvider(apiKey: { "el-key" }, session: session)
    private lazy var keyless = ElevenLabsProvider(apiKey: { " " }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    func testVoicesUseTheV2ListWithTheKeyHeaderAndALanguageFromLabels() async throws {
        let body = #"{"voices":[{"voice_id":"v1","name":"Jane","labels":{"accent":"British","language":"en"}},{"voice_id":"v2","name":"Pierre","labels":{"accent":"French"}},{"voice_id":"v3","name":"Nobody"}],"has_more":false}"#
        ProviderTestSupport.respond(200, Data(body.utf8)) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v2/voices")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "el-key")
        }
        let voices = try await provider.voices()
        XCTAssertEqual(voices, [Voice(id: "v1", name: "Jane", language: "en"), Voice(id: "v2", name: "Pierre", language: "French"), Voice(id: "v3", name: "Nobody", language: "unknown")])
    }

    func testSynthesiseBuildsThePerVoiceURLAndWritesAnMP3() async throws {
        ProviderTestSupport.respond(200, Data([0xFF, 0xFB, 1])) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/text-to-speech/v1?output_format=mp3_44100_128")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "el-key")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["text"] as? String, "Hello")
            XCTAssertEqual(json["model_id"] as? String, "eleven_v3")
            XCTAssertEqual(json.count, 2)
        }
        let clip = try await provider.synthesise("Hello", voice: "v1", language: "French")
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: clip.url), Data([0xFF, 0xFB, 1]))
    }

    func testUnauthorisedAndMissingKey() async {
        ProviderTestSupport.respond(401, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(401) { _ = try await provider.synthesise("x", voice: "v1", language: nil) }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.voices() }
    }

    func testMarkupHintNamesTheTags() {
        XCTAssertTrue(provider.markupHint?.contains("[sigh]") == true)
        XCTAssertTrue(provider.markupHint?.contains("[deadpan]") == true)
    }
}
