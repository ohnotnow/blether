import XCTest
@testable import Blether

final class ToneClassifierTests: XCTestCase {
    private let llm = FakeLLM()
    private let session = URLProtocolStub.makeSession()

    override func tearDown() { URLProtocolStub.reset() }

    func testLLMClassifierParsesTheStyleAndTolerantlyIgnoresChatter() async throws {
        let classifier = LLMToneClassifier(llm: llm)
        llm.toneScript = { _ in #"{"style": "sad"}"# }
        let sad = try await classifier.classify("Sorry, I broke it.")
        XCTAssertEqual(sad, .sad)
        XCTAssertEqual(llm.toneCalls, 1)
        XCTAssertEqual(llm.calls[0].user, "Sorry, I broke it.")
        llm.toneScript = { _ in "Sure! {\"style\":\"Curious\"} hope that helps" }
        let curious = try await classifier.classify("x")
        XCTAssertEqual(curious, .curious)
    }

    func testLLMClassifierThrowsOnUnknownMissingOrFailed() async {
        let classifier = LLMToneClassifier(llm: llm)
        llm.toneScript = { _ in #"{"style": "giddy"}"# }
        await assertThrows { _ = try await classifier.classify("x") }
        llm.toneScript = { _ in "{}" }
        await assertThrows { _ = try await classifier.classify("x") }
        llm.toneScript = { _ in "no json here" }
        await assertThrows { _ = try await classifier.classify("x") }
        llm.toneScript = { _ in throw URLError(.cannotConnectToHost) }
        await assertThrows { _ = try await classifier.classify("x") }
    }

    func testJevSendsOneChoiceQuestionWithNineCriteriaAndReadsTheChoice() async throws {
        let body = #"{"model":"jev-latest","answers":{"tone":{"type":"choice","choice":"frustrated","probabilities":{"frustrated":0.8},"confidence":0.612}},"usage":{"input_tokens":30,"output_tokens":4}}"#
        ProviderTestSupport.respond(200, Data(body.utf8)) { request in
            XCTAssertEqual(request.url, JevToneClassifier.url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jev-1")
            let json = try ProviderTestSupport.json(request)
            XCTAssertEqual(json["state"] as? String, "It still does not work.")
            XCTAssertEqual(json["model"] as? String, "jev-latest")
            let questions = try XCTUnwrap(json["questions"] as? [String: Any])
            let tone = try XCTUnwrap(questions["tone"] as? [String: Any])
            XCTAssertEqual(tone["type"] as? String, "choice")
            XCTAssertEqual((tone["criteria"] as? [String: String])?.count, 9)
            XCTAssertEqual((tone["criteria"] as? [String: String])?["sad"], Tone.sad.criterion)
            XCTAssertFalse((tone["instructions"] as? String ?? "").isEmpty)
        }
        let classifier = JevToneClassifier(apiKey: { "jev-1" }, session: session)
        let tone = try await classifier.classify("It still does not work.")
        XCTAssertEqual(tone, .frustrated)
    }

    func testJevFailures() async {
        let classifier = JevToneClassifier(apiKey: { "jev-1" }, session: session)
        ProviderTestSupport.respond(200, Data(#"{"answers":{"tone":{"choice":"giddy"}}}"#.utf8))
        await assertThrows { _ = try await classifier.classify("x") }
        ProviderTestSupport.respond(200, Data(#"{"answers":{}}"#.utf8))
        await assertThrows { _ = try await classifier.classify("x") }
        ProviderTestSupport.respond(401, Data("{}".utf8))
        await ProviderTestSupport.assertHTTP(401) { _ = try await classifier.classify("x") }
        let keyless = JevToneClassifier(apiKey: { nil }, session: session)
        await ProviderTestSupport.assertNoKeyThrowsWithoutARequest { _ = try await keyless.classify("x") }
    }

    private func assertThrows(_ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected a throw")
        } catch {}
    }
}
