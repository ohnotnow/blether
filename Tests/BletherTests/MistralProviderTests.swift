import XCTest
@testable import Blether

final class MistralProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = MistralProvider(apiKey: { "m-key" }, session: session)
    private lazy var keyless = MistralProvider(apiKey: { nil }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    func testVoicesMapTheItems() async throws {
        ProviderTestSupport.respond(200, Data(#"{"items":[{"id":"gb_jane","name":"Jane","languages":["en","fr"]},{"id":"0000-1111"}],"page":1,"total_pages":1}"#.utf8)) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/voices")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer m-key")
        }
        let voices = try await provider.voices()
        XCTAssertEqual(voices, [Voice(id: "gb_jane", name: "Jane", language: "en"), Voice(id: "0000-1111", name: "0000-1111", language: "unknown")])
        XCTAssertNil(provider.markupHint)
    }

    func testSynthesiseDecodesBase64AudioFromTheJSONReply() async throws {
        let audio = Data([0xFF, 0xFB, 9, 9])
        ProviderTestSupport.respond(200, Data(#"{"audio_data":"\#(audio.base64EncodedString())"}"#.utf8)) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/speech")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["model"] as? String, "voxtral-mini-tts-2603")
            XCTAssertEqual(json["voice_id"] as? String, "gb_jane")
            XCTAssertEqual(json["response_format"] as? String, "mp3")
            XCTAssertEqual(json.count, 4)
        }
        let clip = try await provider.synthesise("Hello", voice: "gb_jane", language: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: clip.url), audio)
    }

    func testReplyWithoutAudioDataIsNoAudio() async {
        ProviderTestSupport.respond(200, Data(#"{"model":"voxtral-mini-tts-2603"}"#.utf8))
        do {
            _ = try await provider.synthesise("x", voice: "gb_jane", language: nil)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .noAudio)
        }
    }

    func testUnauthorisedAndMissingKey() async {
        ProviderTestSupport.respond(401, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(401) { _ = try await provider.voices() }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.synthesise("x", voice: "gb_jane", language: nil) }
    }
}
