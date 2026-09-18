import XCTest
@testable import Blether

final class SpeechHTTPTests: XCTestCase {
    private let session = URLProtocolStub.makeSession()
    private let url = URL(string: "https://speech.example/v1/say")!
    private struct Body: Encodable { let text: String }

    override func tearDown() {
        URLProtocolStub.reset()
    }

    func testPostSendsJSONWithABearerHeaderAndReturnsTheBody() async throws {
        URLProtocolStub.install { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), #"{"text":"hi"}"#)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data([1, 2, 3]))
        }
        let data = try await SpeechHTTP.post(url, auth: .bearer("k-1"), json: Body(text: "hi"), session: session)
        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testGetSendsANamedHeader() async throws {
        URLProtocolStub.install { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "k-2")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        let data = try await SpeechHTTP.get(url, auth: .header(name: "xi-api-key", value: "k-2"), session: session)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[]")
    }

    func testNon2xxThrowsHTTPWithTheStatus() async {
        URLProtocolStub.install { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data(#"{"detail":"bad key"}"#.utf8))
        }
        do {
            _ = try await SpeechHTTP.post(url, auth: .bearer("x"), json: Body(text: "hi"), session: session)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .http(401))
        }
    }

    func testTransportFailureThrowsOther() async {
        URLProtocolStub.install { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await SpeechHTTP.get(url, auth: .bearer("x"), session: session)
            XCTFail("expected a throw")
        } catch {
            guard case .other = error as? ProviderError else { return XCTFail("\(error)") }
        }
    }

    func testClipWritesTheBytesWithTheExtensionAndRejectsEmptyData() throws {
        let clip = try SpeechHTTP.clip(from: Data([9, 8, 7]), extension: "mp3")
        defer { try? FileManager.default.removeItem(at: clip.url) }
        XCTAssertEqual(clip.url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: clip.url), Data([9, 8, 7]))
        XCTAssertThrowsError(try SpeechHTTP.clip(from: Data(), extension: "mp3")) { error in
            XCTAssertEqual(error as? ProviderError, .noAudio)
        }
    }
}
