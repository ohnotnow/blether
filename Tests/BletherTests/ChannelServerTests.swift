import Foundation
import Network
import Synchronization
import XCTest
@testable import Blether

/// A line-at-a-time TCP client standing in for the nc one-liner Claude Code runs.
final class LineClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "line-client")
    private var buffer = Data()
    private var waiters: [CheckedContinuation<String, Error>] = []
    private var lines: [String] = []

    init(port: UInt16) async throws {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Mutex(false)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if !once.withLock({ let was = $0; $0 = true; return was }) { continuation.resume() }
                case .failed(let error): if !once.withLock({ let was = $0; $0 = true; return was }) { continuation.resume(throwing: error) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
        receive()
    }

    func send(_ line: String) {
        connection.send(content: Data((line + "\n").utf8), completion: .contentProcessed { _ in })
    }

    func send(json: [String: Any]) {
        send(String(decoding: try! JSONSerialization.data(withJSONObject: json), as: UTF8.self))
    }

    /// The next line the server sends, as parsed JSON.
    func next() async throws -> [String: Any] {
        let line = try await nextLine()
        return try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    }

    func close() { connection.cancel() }

    private func nextLine() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if !self.lines.isEmpty { continuation.resume(returning: self.lines.removeFirst()) } else { self.waiters.append(continuation) }
            }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { buffer.append(data) }
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                if !waiters.isEmpty { waiters.removeFirst().resume(returning: line) } else { lines.append(line) }
            }
            if isComplete || error != nil {
                waiters.forEach { $0.resume(throwing: error ?? URLError(.networkConnectionLost)) }
                waiters.removeAll()
                return
            }
            receive()
        }
    }
}

/// Records handsfree tool calls from the server's queue. A class, because Mutex itself cannot be captured.
final class HandsfreeCalls: Sendable {
    private let calls = Mutex<[String]>([])
    func record(_ action: String) { calls.withLock { $0.append(action) } }
    var all: [String] { calls.withLock { $0 } }
}

final class ChannelServerTests: XCTestCase {
    private var server: ChannelServer!
    private let handsfreeCalls = HandsfreeCalls()

    override func setUpWithError() throws {
        let calls = handsfreeCalls
        server = ChannelServer(port: 0) { action, reply in
            calls.record(action)
            reply("Listening after replies is \(action == "off" ? "off" : "on").")
        }
        try server.start()
    }

    override func tearDown() {
        server.stop()
    }

    /// Connects as the one-liner would and completes the MCP handshake, returning the initialize result.
    private func connectAndInitialise(sessionID: String, pid: Int32) async throws -> (LineClient, [String: Any]) {
        let client = try await LineClient(port: server.boundPort!)
        client.send("blether \(sessionID) \(pid)")
        client.send(json: ["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": ["protocolVersion": "2025-11-25", "clientInfo": ["name": "test"]]])
        let reply = try await client.next()
        client.send(json: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        return (client, reply)
    }

    private func waitForSessions(_ count: Int) async throws {
        for _ in 0..<40 where server.sessionCount != count { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(server.sessionCount, count)
    }

    func testInitialiseDeclaresTheChannelCapabilityAndInstructions() async throws {
        let (client, reply) = try await connectAndInitialise(sessionID: "s-1", pid: 11)
        defer { client.close() }
        XCTAssertEqual(reply["id"] as? Int, 0)
        let result = reply["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-11-25")
        let capabilities = result?["capabilities"] as? [String: Any]
        XCTAssertNotNil((capabilities?["experimental"] as? [String: Any])?["claude/channel"])
        XCTAssertNotNil(capabilities?["tools"])
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "blether")
        XCTAssertTrue((result?["instructions"] as? String ?? "").contains("handsfree"))
        try await waitForSessions(1)
    }

    func testToolsListOffersHandsfreeAndCallingItReportsBack() async throws {
        let (client, _) = try await connectAndInitialise(sessionID: "s-1", pid: 11)
        defer { client.close() }
        client.send(json: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let list = try await client.next()
        let tools = (list["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.map { $0["name"] as? String }, ["handsfree"])

        client.send(json: ["jsonrpc": "2.0", "id": "req-2", "method": "tools/call", "params": ["name": "handsfree", "arguments": ["action": "on"]]])
        let call = try await client.next()
        XCTAssertEqual(call["id"] as? String, "req-2", "string ids are echoed as strings")
        let content = (call["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "Listening after replies is on.")
        XCTAssertEqual(handsfreeCalls.all, ["on"])
    }

    func testDeliverWritesTheChannelNotificationToTheMatchingSession() async throws {
        let (first, _) = try await connectAndInitialise(sessionID: "s-1", pid: 11)
        let (second, _) = try await connectAndInitialise(sessionID: "s-2", pid: 22)
        defer { first.close(); second.close() }
        try await waitForSessions(2)

        XCTAssertTrue(server.deliver("hello from the mic", to: SessionKey(id: "s-2", pid: nil)))
        let event = try await second.next()
        XCTAssertEqual(event["method"] as? String, "notifications/claude/channel")
        XCTAssertEqual((event["params"] as? [String: Any])?["content"] as? String, "hello from the mic")

        XCTAssertTrue(server.deliver("by pid", to: SessionKey(id: "stale", pid: 11)), "a resumed session is found by pid")
        let byPid = try await first.next()
        XCTAssertEqual((byPid["params"] as? [String: Any])?["content"] as? String, "by pid")

        XCTAssertFalse(server.deliver("nowhere", to: SessionKey(id: "s-9", pid: 99)))
    }

    func testUnknownMethodWithAnIDGetsMethodNotFoundAndNotificationsAreIgnored() async throws {
        let (client, _) = try await connectAndInitialise(sessionID: "s-1", pid: 11)
        defer { client.close() }
        client.send(json: ["jsonrpc": "2.0", "method": "notifications/something/else"])
        client.send(json: ["jsonrpc": "2.0", "id": 5, "method": "resources/list"])
        let reply = try await client.next()
        XCTAssertEqual(reply["id"] as? Int, 5)
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testClosingTheConnectionRemovesTheSession() async throws {
        let (client, _) = try await connectAndInitialise(sessionID: "s-1", pid: 11)
        try await waitForSessions(1)
        client.close()
        try await waitForSessions(0)
        XCTAssertFalse(server.deliver("gone", to: SessionKey(id: "s-1", pid: 11)))
    }

    func testAConnectionWithoutTheHeaderStillWorksAsAnAnonymousSession() async throws {
        let client = try await LineClient(port: server.boundPort!)
        defer { client.close() }
        client.send(json: ["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": [:]])
        let reply = try await client.next()
        XCTAssertNotNil(reply["result"])
        try await waitForSessions(1)
        XCTAssertTrue(server.deliver("only one here", to: SessionKey(id: "anything", pid: nil)))
    }
}
