import XCTest
@testable import Blether

final class HTTPRequestTests: XCTestCase {
    private let full = "POST /hook HTTP/1.1\r\nHost: x\r\nContent-Length: 11\r\n\r\nhello world"

    func testParsesCompleteRequest() throws {
        let request = try XCTUnwrap(HTTPRequest.parse(Data(full.utf8)))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/hook")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "hello world")
    }

    func testQueryIsSplitFromThePathAndPercentDecoded() throws {
        let request = try XCTUnwrap(HTTPRequest.parse(Data("POST /hook?profile=Serious%20and%20stern&profile=second&x=1 HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertEqual(request.path, "/hook")
        XCTAssertEqual(request.query, ["profile": "Serious and stern", "x": "1"], "first value wins")
    }

    func testNoQueryGivesAnEmptyDictionary() throws {
        let request = try XCTUnwrap(HTTPRequest.parse(Data(full.utf8)))
        XCTAssertEqual(request.query, [:])
        let bare = try XCTUnwrap(HTTPRequest.parse(Data("POST /hook?profile= HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertEqual(bare.query, ["profile": ""])
    }

    /// URLComponents is lenient (a space in the target parses), so the one target it refuses on this
    /// macOS is an absolute URL with an unclosed bracket. That is enough to pin the fallback.
    func testUnparseableTargetIsKeptWholeAsThePath() {
        let (path, query) = HTTPRequest.splitTarget("http://[::1")
        XCTAssertEqual(path, "http://[::1")
        XCTAssertEqual(query, [:])
        XCTAssertEqual(HTTPRequest.splitTarget("/ho ok?a=b").path, "/ho ok", "a space is tolerated, not rejected")
    }

    func testRequestSplitAcrossTwoChunks() {
        let bytes = Array(full.utf8)
        var buffer = Data(bytes[..<30])
        XCTAssertNil(HTTPRequest.parse(buffer))
        buffer.append(contentsOf: bytes[30...])
        XCTAssertNotNil(HTTPRequest.parse(buffer))
    }

    func testBodyShorterThanContentLengthIsNil() {
        let short = "POST /hook HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello"
        XCTAssertNil(HTTPRequest.parse(Data(short.utf8)))
    }

    func testHeaderLookupIsCaseInsensitive() throws {
        let request = try XCTUnwrap(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nAuthorization: Bearer t\r\n\r\n".utf8)))
        XCTAssertEqual(request.header("authorization"), "Bearer t")
        XCTAssertEqual(request.header("AUTHORIZATION"), "Bearer t")
    }

    func testNoContentLengthMeansEmptyBody() throws {
        let request = try XCTUnwrap(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n".utf8)))
        XCTAssertTrue(request.body.isEmpty)
    }

    func testIncompleteHeadersIsNil() {
        XCTAssertNil(HTTPRequest.parse(Data("POST /hook HTTP/1.1\r\nHost: x\r\n".utf8)))
    }

    func testNegativeOrGarbageContentLengthIsRejectedNotTrapped() {
        for value in ["-1", "-5", "abc", "1e3", ""] {
            let raw = Data("POST /hook HTTP/1.1\r\nContent-Length: \(value)\r\n\r\nhello".utf8)
            XCTAssertNil(HTTPRequest.parse(raw), "value \(value)")
            let head = HTTPRequest.parseHead(raw)?.request
            XCTAssertNil(head?.declaredContentLength, "value \(value)")
        }
    }

    func testAbsentContentLengthIsZeroNotNil() {
        let head = HTTPRequest.parseHead(Data("GET / HTTP/1.1\r\n\r\n".utf8))?.request
        XCTAssertEqual(head?.declaredContentLength, 0)
    }
}
