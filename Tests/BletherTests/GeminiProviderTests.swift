import XCTest
@testable import Blether

final class GeminiProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = GeminiProvider(apiKey: { "or-key" }, session: session)
    private lazy var keyless = GeminiProvider(apiKey: { nil }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    func testVoicesAreTheFixedListWithoutANetworkCall() async throws {
        ProviderTestSupport.neverCalled()
        let voices = try await provider.voices()
        XCTAssertEqual(voices.count, 30)
        XCTAssertEqual(voices[3].id, "Kore")
        XCTAssertEqual(voices[3].name, "Kore")
        XCTAssertNil(provider.markupHint)
    }

    func testSynthesiseAsksOpenRouterForPCMAndWritesAWav() async throws {
        ProviderTestSupport.respond(200, Data([1, 2, 3, 4])) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/speech")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer or-key")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["model"] as? String, "google/gemini-3.8-flash-tts")
            XCTAssertEqual(json["voice"] as? String, "Kore")
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["response_format"] as? String, "pcm")
            XCTAssertEqual(json.count, 4, "no instructions without a tone")
        }
        let clip = try await provider.synthesise("Hello", voice: "Kore", language: nil, tone: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "wav")
        XCTAssertEqual(try Data(contentsOf: clip.url), GeminiProvider.wav(Data([1, 2, 3, 4])))
    }

    func testToneSendsOpenAIsInstructionsSentence() async throws {
        ProviderTestSupport.respond(200, Data([1, 2])) { request in
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["instructions"] as? String, OpenAIProvider.instructions[.sad])
        }
        let clip = try await provider.synthesise("x", voice: "Puck", language: nil, tone: .sad)
        try? FileManager.default.removeItem(at: clip.url)
    }

    func testWavHeaderDescribes24kHzSixteenBitMono() {
        let wav = GeminiProvider.wav(Data(count: 480))
        func u32(_ at: Int) -> UInt32 { wav.subdata(in: at ..< at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func u16(_ at: Int) -> UInt16 { wav.subdata(in: at ..< at + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
        XCTAssertEqual(wav.count, 44 + 480)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(u32(4), 36 + 480)
        XCTAssertEqual(u16(20), 1, "PCM")
        XCTAssertEqual(u16(22), 1, "mono")
        XCTAssertEqual(u32(24), 24000)
        XCTAssertEqual(u32(28), 48000, "bytes per second")
        XCTAssertEqual(u16(34), 16)
        XCTAssertEqual(u32(40), 480)
    }

    func testEmptyAudioRateLimitedAndMissingKey() async {
        ProviderTestSupport.respond(200, Data())
        do {
            _ = try await provider.synthesise("x", voice: "Kore", language: nil, tone: nil)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .noAudio)
        }
        ProviderTestSupport.respond(429, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(429) { _ = try await provider.synthesise("x", voice: "Kore", language: nil, tone: nil) }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.synthesise("x", voice: "Kore", language: nil, tone: nil) }
    }
}
