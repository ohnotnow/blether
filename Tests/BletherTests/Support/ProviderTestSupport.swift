import XCTest
@testable import Blether

/// Shared bits for the API provider tests: a stubbed session, a canned response, and the
/// "no key means no request" check every provider has.
enum ProviderTestSupport {
    static func respond(_ status: Int, _ body: Data, check: (@Sendable (URLRequest) throws -> Void)? = nil) {
        URLProtocolStub.install { request in
            try check?(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    static func neverCalled() {
        URLProtocolStub.install { request in
            XCTFail("unexpected request to \(request.url?.absoluteString ?? "?")")
            throw URLError(.badURL)
        }
    }

    /// A call counter usable from the stub's Sendable handler.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    static func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    static func assertHTTP(_ status: Int, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ProviderError, .http(status))
        }
    }

    static func assertNoKeyThrowsWithoutARequest(_ body: () async throws -> Void) async {
        neverCalled()
        do {
            try await body()
            XCTFail("expected a throw")
        } catch {
            guard case .other(let message)? = error as? ProviderError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("no API key"), message)
        }
    }
}
