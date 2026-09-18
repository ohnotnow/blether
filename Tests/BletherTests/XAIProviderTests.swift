import XCTest
@testable import Blether

final class XAIProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = XAIProvider(apiKey: { "x-key" }, session: session)
    private lazy var keyless = XAIProvider(apiKey: { "" }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    func testVoicesParseEitherLenientShape() async throws {
        ProviderTestSupport.respond(200, Data(#"{"voices":[{"voice_id":"eve","name":"Eve","language":"en"},{"id":"ara"}]}"#.utf8)) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/tts/voices")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer x-key")
        }
        var voices = try await provider.voices()
        XCTAssertEqual(voices, [Voice(id: "eve", name: "Eve", language: "en"), Voice(id: "ara", name: "Ara", language: "unknown")])

        ProviderTestSupport.respond(200, Data(#"[{"id":"rex","name":"Rex"}]"#.utf8))
        voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["rex"])
    }

    func testUnrecognisedVoiceListFallsBackToTheKnownIds() async throws {
        ProviderTestSupport.respond(200, Data(#"{"data":"something else"}"#.utf8))
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["eve", "ara", "rex"])
    }

    func testSynthesiseAlwaysSendsAutoLanguageAndTheMP3Format() async throws {
        ProviderTestSupport.respond(200, Data([3, 4])) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/tts")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer x-key")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["text"] as? String, "Hello")
            XCTAssertEqual(json["voice_id"] as? String, "eve")
            XCTAssertEqual(json["language"] as? String, "auto")
            let format = try XCTUnwrap(json["output_format"] as? [String: Any])
            XCTAssertEqual(format["codec"] as? String, "mp3")
            XCTAssertEqual(format["sample_rate"] as? Int, 24000)
            XCTAssertEqual(format["bit_rate"] as? Int, 64000)
        }
        let clip = try await provider.synthesise("Hello", voice: "eve", language: "French", tone: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(try Data(contentsOf: clip.url), Data([3, 4]))
    }

    func testPaymentRequiredAndMissingKey() async {
        ProviderTestSupport.respond(402, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(402) { _ = try await provider.synthesise("x", voice: "eve", language: nil, tone: nil) }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.voices() }
    }

    func testMarkupHintNamesTheTags() {
        XCTAssertTrue(provider.markupHint?.contains("<emphasis>") == true)
        XCTAssertTrue(provider.markupHint?.contains("<whisper>") == true)
    }
}
