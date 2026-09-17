import XCTest
@testable import Blether

final class ChatCompletionsClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func client(baseURL: String = "http://127.0.0.1:11434/v1", apiKey: String? = nil, extraBody: String = "{}") -> ChatCompletionsClient {
        ChatCompletionsClient(baseURL: baseURL, model: "test-model", apiKey: apiKey, extraBody: extraBody, session: URLProtocolStub.makeSession())
    }

    func testExtraBodyFieldsAreMergedButCannotReplaceModelOrMessages() async throws {
        URLProtocolStub.install { request in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(json["think"] as? Bool, false)
            XCTAssertEqual(json["max_tokens"] as? Int, 500, "extra fields win over ours")
            XCTAssertEqual(json["model"] as? String, "test-model", "model cannot be overridden")
            XCTAssertEqual((json["messages"] as? [[String: String]])?.count, 2, "messages cannot be overridden")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.okBody.utf8))
        }
        let extra = #"{"think": false, "max_tokens": 500, "model": "evil", "messages": []}"#
        _ = try await client(extraBody: extra).complete(system: "s", user: "u")
    }

    func testInvalidExtraBodyIsIgnored() async throws {
        URLProtocolStub.install { request in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(json["max_tokens"] as? Int, 16000)
            XCTAssertNil(json["think"])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.okBody.utf8))
        }
        _ = try await client(extraBody: "not json").complete(system: "s", user: "u")
    }

    private func respond(_ status: Int, _ body: String) {
        URLProtocolStub.install { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    private static let okBody = #"{"choices":[{"message":{"role":"assistant","content":"  The reply is ready, bleakly.\n","reasoning":"We need a gloomy line..."}}],"usage":{"prompt_tokens":53,"completion_tokens":98}}"#

    func testRequestShapeAndNoAuthHeaderWithoutKey() async throws {
        URLProtocolStub.install { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "test-model")
            XCTAssertEqual(json["max_tokens"] as? Int, 16000)
            XCTAssertEqual(json["stream"] as? Bool, false)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
            XCTAssertEqual(messages.map { $0["content"] }, ["Be gloomy.", "Makefile fixed."])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.okBody.utf8))
        }
        _ = try await client().complete(system: "Be gloomy.", user: "Makefile fixed.")
    }

    func testTrailingSlashOnBaseURLAndBearerHeaderWithKey() async throws {
        URLProtocolStub.install { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-fixture")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.okBody.utf8))
        }
        _ = try await client(baseURL: "https://api.example.test/v1/", apiKey: " sk-fixture ").complete(system: "s", user: "u")
    }

    func testBlankKeySendsNoAuthHeader() async throws {
        URLProtocolStub.install { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.okBody.utf8))
        }
        _ = try await client(apiKey: " \n").complete(system: "s", user: "u")
    }

    func testReturnsTrimmedContentAndIgnoresReasoning() async throws {
        respond(200, Self.okBody)
        let text = try await client().complete(system: "s", user: "u")
        XCTAssertEqual(text, "The reply is ready, bleakly.")
    }

    func testEmptyContentThrows() async {
        respond(200, #"{"choices":[{"message":{"role":"assistant","content":"","reasoning":"ran out of budget"}}]}"#)
        await assertThrows(.emptyResponse)
    }

    func testMissingChoicesThrowsEmpty() async {
        respond(200, #"{"object":"chat.completion"}"#)
        await assertThrows(.emptyResponse)
    }

    func testServerErrorWithMessage() async {
        respond(500, #"{"error":{"message":"boom","type":"server_error"}}"#)
        await assertThrows(.http(500, "boom"))
    }

    func testNotFoundWithNonJSONBody() async {
        respond(404, "404 page not found")
        await assertThrows(.http(404, nil))
    }

    func testBadBaseURLThrowsBeforeNetworking() async {
        URLProtocolStub.install { _ in
            XCTFail("no request expected")
            throw URLError(.badURL)
        }
        do {
            _ = try await client(baseURL: "not a url").complete(system: "s", user: "u")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? LLMError, .badURL("not a url"))
        }
    }

    func testTransportErrorIsWrapped() async {
        URLProtocolStub.install { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await client().complete(system: "s", user: "u")
            XCTFail("expected a throw")
        } catch let error as LLMError {
            guard case .transport = error else { return XCTFail("expected transport, got \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertThrows(_ expected: LLMError) async {
        do {
            _ = try await client().complete(system: "s", user: "u")
            XCTFail("expected \(expected)")
        } catch {
            XCTAssertEqual(error as? LLMError, expected)
        }
    }
}
