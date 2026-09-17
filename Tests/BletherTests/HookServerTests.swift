import Network
import Synchronization
import XCTest
@testable import Blether

/// Thread-safe list of (text, profile) pairs the server handed to its callback.
private final class Received: Sendable {
    struct Call: Equatable { let text: String; let profile: String? }
    private let calls = Mutex<[Call]>([])
    func append(_ text: String, _ profile: String?) { calls.withLock { $0.append(Call(text: text, profile: profile)) } }
    var all: [String] { calls.withLock { $0.map(\.text) } }
    var pairs: [Call] { calls.withLock { $0 } }
}

final class HookServerTests: XCTestCase {
    private var server: HookServer!
    private let received = Received()

    override func setUpWithError() throws {
        let received = received
        server = HookServer(port: 0) { text, profile in
            received.append(text, profile)
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

    private func waitForCallback() async throws {
        for _ in 0 ..< 40 where received.all.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testProfileQueryParameterIsForwarded() async throws {
        let (status, _) = try await send("POST", "/hook?profile=Serious%20and%20stern", body: #"{"hook_event_name":"Stop","last_assistant_message":"hi"}"#)
        XCTAssertEqual(status, 200)
        try await waitForCallback()
        XCTAssertEqual(received.pairs, [.init(text: "hi", profile: "Serious and stern")])
    }

    func testNoProfileParameterForwardsNil() async throws {
        _ = try await send("POST", "/hook", body: #"{"hook_event_name":"Stop","last_assistant_message":"hi"}"#)
        try await waitForCallback()
        XCTAssertEqual(received.pairs, [.init(text: "hi", profile: nil)])
    }

    /// The claude-speaks remote hook and Hermes plugin still send a Bearer token; it must not get in the way.
    func testAuthorizationHeaderIsIgnored() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.boundPort!)/hook")!)
        request.httpMethod = "POST"
        request.setValue("Bearer whatever", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"hook_event_name":"Stop","last_assistant_message":"hi"}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 200)
        try await waitForCallback()
        XCTAssertEqual(received.all, ["hi"])
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

    func testAllInterfacesStillAnswersOnLoopback() async throws {
        let received = Received()
        let wide = HookServer(port: 0, allInterfaces: true) { text, profile in received.append(text, profile) }
        try wide.start()
        defer { wide.stop() }
        let port = try XCTUnwrap(wide.boundPort)
        XCTAssertNotEqual(port, 0)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook?profile=pi")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"hook_event_name":"Stop","last_assistant_message":"hi"}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 200)
        for _ in 0 ..< 40 where received.all.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(received.pairs, [.init(text: "hi", profile: "pi")])
    }

    func testPortInUseThrows() throws {
        let second = HookServer(port: server.boundPort!) { _, _ in }
        XCTAssertThrowsError(try second.start())
    }
}
