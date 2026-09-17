import Network
import Synchronization
import XCTest
@testable import Blether

/// Thread-safe list of texts the server handed to its callback.
private final class Received: Sendable {
    private let texts = Mutex<[String]>([])
    func append(_ text: String) { texts.withLock { $0.append(text) } }
    var all: [String] { texts.withLock { $0 } }
}

final class HookServerTests: XCTestCase {
    private var server: HookServer!
    private let received = Received()

    override func setUpWithError() throws {
        let received = received
        server = HookServer(port: 0) { text in
            received.append(text)
        }
        try server.start()
        XCTAssertNotNil(server.boundPort)
        XCTAssertNotEqual(server.boundPort, 0)
    }

    override func tearDown() {
        server.stop()
    }

    private func send(_ method: String, _ path: String, body: String?) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.boundPort!)\(path)")!)
        request.httpMethod = method
        request.httpBody = body.map { Data($0.utf8) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    func testStopPayloadIsAcknowledgedAndSpoken() async throws {
        let (status, body) = try await send("POST", "/hook", body: #"{"hook_event_name":"Stop","last_assistant_message":"**Hello** there"}"#)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body, #"{"ok":true}"#)
        for _ in 0 ..< 40 where received.all.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(received.all, ["Hello there"])
    }

    func testNonStopEventIsAcknowledgedNotSpoken() async throws {
        let (status, _) = try await send("POST", "/hook", body: #"{"hook_event_name":"Notification","last_assistant_message":"x"}"#)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(received.all.isEmpty)
    }

    func testEmptyAfterStrippingIsNotSpoken() async throws {
        let (status, _) = try await send("POST", "/hook", body: #"{"hook_event_name":"Stop","last_assistant_message":"```\ncode only\n```"}"#)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(received.all.isEmpty)
    }

    /// Writes raw bytes over TCP and returns whatever the server sends back before closing.
    /// URLSession would set its own Content-Length, so malformed headers need this.
    private func sendRaw(_ bytes: String) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.boundPort!)!, using: .tcp)
        connection.start(queue: .global())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes.utf8), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        let reply: String = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let error { continuation.resume(throwing: error) } else {
                    continuation.resume(returning: String(decoding: data ?? Data(), as: UTF8.self))
                }
            }
        }
        connection.cancel()
        return reply
    }

    func testNegativeContentLengthIs400NotACrash() async throws {
        let reply = try await sendRaw("POST /hook HTTP/1.1\r\nContent-Length: -1\r\n\r\n")
        XCTAssertTrue(reply.hasPrefix("HTTP/1.1 400 "), reply)
        XCTAssertTrue(reply.hasSuffix(#"{"error":"bad content-length"}"#), reply)
        XCTAssertTrue(received.all.isEmpty)
    }

    func testBadJSONIs400() async throws {
        let (status, body) = try await send("POST", "/hook", body: "not json")
        XCTAssertEqual(status, 400)
        XCTAssertEqual(body, #"{"error":"bad json"}"#)
        let (status2, _) = try await send("POST", "/hook", body: #"{"no_event":true}"#)
        XCTAssertEqual(status2, 400)
    }

    func testOtherPathIs404() async throws {
        let (status, _) = try await send("POST", "/other", body: "{}")
        XCTAssertEqual(status, 404)
    }

    func testGetOnHookIs405() async throws {
        let (status, _) = try await send("GET", "/hook", body: nil)
        XCTAssertEqual(status, 405)
    }

    func testPortInUseThrows() throws {
        let second = HookServer(port: server.boundPort!) { _ in }
        XCTAssertThrowsError(try second.start())
    }
}
