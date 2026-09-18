import XCTest
@testable import Blether

final class MistralProviderTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private lazy var provider = MistralProvider(apiKey: { "m-key" }, session: session)
    private lazy var keyless = MistralProvider(apiKey: { nil }, session: session)

    override func tearDown() { URLProtocolStub.reset() }

    /// The shape the live endpoint returned on 2026-09-18, trimmed to the fields read.
    private static let list = #"{"items":[{"id":"u-1","slug":"en_paul_sad","name":"Paul - Sad","languages":["en_us"]},{"id":"u-2","slug":"en_paul_neutral","name":"Paul - Neutral","languages":["en_us"]},{"id":"u-3","slug":"en_paul_confident","name":"Paul - Confident","languages":["en_us"]},{"id":"u-4","slug":"gb_jane_sarcasm","name":"Jane - Sarcastic","languages":["en_gb"]},{"id":"0000-1111","name":"Mine"}],"page":1,"total_pages":1}"#

    func testVoicesUseTheSlugAsTheIdWhenThereIsOne() async throws {
        ProviderTestSupport.respond(200, Data(Self.list.utf8)) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/voices")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer m-key")
        }
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["en_paul_sad", "en_paul_neutral", "en_paul_confident", "gb_jane_sarcasm", "0000-1111"])
        XCTAssertEqual(voices[0], Voice(id: "en_paul_sad", name: "Paul - Sad", language: "en_us"))
        XCTAssertEqual(voices[4], Voice(id: "0000-1111", name: "Mine", language: "unknown"))
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
        let clip = try await provider.synthesise("Hello", voice: "gb_jane", language: nil, tone: nil)
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: clip.url), audio)
    }

    func testToneSwapsToTheSpeakersSiblingOnlyWhenItExists() {
        let moods: [String: Set<String>] = ["en_paul": ["sad", "neutral", "confident"], "gb_jane": ["sarcasm"]]
        XCTAssertEqual(MistralProvider.voiceID("en_paul_neutral", tone: .sad, moods: moods), "en_paul_sad")
        XCTAssertEqual(MistralProvider.voiceID("en_paul_neutral", tone: .shameful, moods: moods), "en_paul_sad", "shameful maps to sad")
        XCTAssertEqual(MistralProvider.voiceID("en_paul_sad", tone: .confident, moods: moods), "en_paul_confident")
        XCTAssertEqual(MistralProvider.voiceID("en_paul_sad", tone: .curious, moods: moods), "en_paul_sad", "no mood word for curious")
        XCTAssertEqual(MistralProvider.voiceID("en_paul_sad", tone: .sarcasm, moods: moods), "en_paul_sad", "Paul has no sarcasm sibling")
        XCTAssertEqual(MistralProvider.voiceID("gb_jane_sarcasm", tone: .sad, moods: moods), "gb_jane_sarcasm", "Jane has no sad sibling")
        XCTAssertEqual(MistralProvider.voiceID("gb_oliver_neutral", tone: .sad, moods: moods), "gb_oliver_neutral", "unknown speaker")
        XCTAssertEqual(MistralProvider.voiceID("0000-1111", tone: .sad, moods: moods), "0000-1111", "a UUID is never touched")
        XCTAssertEqual(MistralProvider.voiceID("en_paul_neutral", tone: nil, moods: moods), "en_paul_neutral")
    }

    func testSynthesisWithAToneListsVoicesOnceThenSpeaksTheSibling() async throws {
        let counter = ProviderTestSupport.Counter()
        URLProtocolStub.install { request in
            if request.httpMethod == "GET" {
                counter.increment()
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.list.utf8))
            }
            XCTAssertEqual(try ProviderTestSupport.json(request)["voice_id"] as? String, "en_paul_sad")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"audio_data":"AAEC"}"#.utf8))
        }
        for _ in 0 ..< 2 {
            let clip = try await provider.synthesise("x", voice: "en_paul_neutral", language: nil, tone: .sad)
            try? FileManager.default.removeItem(at: clip.url)
        }
        XCTAssertEqual(counter.value, 1, "the list is fetched once")
    }

    func testAFailedVoiceListSpeaksTheVoiceAsChosen() async throws {
        URLProtocolStub.install { request in
            if request.httpMethod == "GET" {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            XCTAssertEqual(try ProviderTestSupport.json(request)["voice_id"] as? String, "en_paul_neutral")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"audio_data":"AAEC"}"#.utf8))
        }
        let clip = try await provider.synthesise("x", voice: "en_paul_neutral", language: nil, tone: .sad)
        try? FileManager.default.removeItem(at: clip.url)
    }

    func testReplyWithoutAudioDataIsNoAudio() async {
        ProviderTestSupport.respond(200, Data(#"{"model":"voxtral-mini-tts-2603"}"#.utf8))
        do {
            _ = try await provider.synthesise("x", voice: "gb_jane", language: nil, tone: nil)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .noAudio)
        }
    }

    func testUnauthorisedAndMissingKey() async {
        ProviderTestSupport.respond(401, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(401) { _ = try await provider.voices() }
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.synthesise("x", voice: "gb_jane", language: nil, tone: nil) }
    }
}
