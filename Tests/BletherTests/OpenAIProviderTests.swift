import XCTest
@testable import Blether

final class OpenAIProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = OpenAIProvider(apiKey: { "oa-key" }, session: session)
    private lazy var keyless = OpenAIProvider(apiKey: { nil }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    func testVoicesAreTheFixedListWithoutANetworkCall() async throws {
        ProviderTestSupport.neverCalled()
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["alloy", "ash", "ballad", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar"])
        XCTAssertEqual(voices[3].name, "Coral")
        XCTAssertEqual(Set(voices.map(\.language)), ["en"])
        XCTAssertNil(provider.markupHint)
    }

    func testSynthesiseSendsExactlyTheFourFieldsAndWritesAnMP3() async throws {
        ProviderTestSupport.respond(200, Data([1, 2])) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer oa-key")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["model"] as? String, "gpt-4o-mini-tts")
            XCTAssertEqual(json["voice"] as? String, "coral")
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["response_format"] as? String, "mp3")
            XCTAssertEqual(json.count, 4, "no instructions until the tone slice")
        }
        let clip = try await provider.synthesise("Hello", voice: "coral", language: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: clip.url), Data([1, 2]))
    }

    func testRateLimitedAndMissingKey() async {
        ProviderTestSupport.respond(429, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(429) { _ = try await provider.synthesise("x", voice: "ash", language: nil) }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.synthesise("x", voice: "ash", language: nil) }
    }
}
