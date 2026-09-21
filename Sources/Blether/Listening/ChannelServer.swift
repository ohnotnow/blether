import Foundation
import Network
import Synchronization

/// The Claude Code channel protocol, served by blether itself. Claude Code spawns a one-line shell
/// command per session (README, "Install the channel") that sends `blether <session-id> <pid>` and then
/// pipes the session's MCP stdio to this port through nc. Blether answers the JSON-RPC handshake,
/// offers one tool, and injects transcripts as `notifications/claude/channel` (channels2.md).
/// Loopback only, whatever the hook listener does: this pipe puts words in front of Claude.
final class ChannelServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 8766
    static let serverName = "blether"
    static let maxLineBytes = 1 << 20

    /// What Claude is told when the server connects. Ported from claude-listens' server.py.
    static let instructions = """
        Events from <channel source="blether"> are the user speaking by voice, transcribed by local \
        speech-to-text; treat them exactly as user input (transcription may introduce small word errors). \
        A user replying by voice is away from the keyboard: prefer plain-text questions over the \
        AskUserQuestion tool while this channel is in use; dialogs block until someone reaches a keyboard, \
        and voice replies queue behind them. The `handsfree` tool turns listening on or off: use it when \
        the user asks to go hands-free (or to stop), and report what it returns so they know whether the \
        microphone will actually open after your replies. The `heard_words` tool adds a word the \
        transcriber keeps mishearing to blether's correction list: use it only when the user says a word \
        was misheard, never on your own guess, and read its description for what it can and cannot fix.
        """

    /// A JSON-RPC request id, which the spec allows to be a number or a string. Kept as a Sendable
    /// value so it can cross into the handsfree reply closure.
    private enum RPCID: Sendable {
        case number(Int)
        case string(String)
        init?(_ raw: Any?) {
            if let n = raw as? Int { self = .number(n) } else if let s = raw as? String { self = .string(s) } else { return nil }
        }
        var json: Any {
            switch self {
            case .number(let n): n
            case .string(let s): s
            }
        }
    }

    /// The `handsfree` tool: on, off or status in; one human line back, delivered on the server's queue.
    typealias Handsfree = @Sendable (_ action: String, _ reply: @escaping @Sendable (String) -> Void) -> Void
    /// The `heard_words` tool: add or list, with the words to add; one human line back, same as handsfree.
    typealias HeardWords = @Sendable (_ action: String, _ words: [String], _ reply: @escaping @Sendable (String) -> Void) -> Void

    private let queue = DispatchQueue(label: "uk.ohnotnow.blether.channel-server")
    private let requestedPort: UInt16
    private let handsfree: Handsfree
    private let heardWords: HeardWords
    private var listener: NWListener?
    private var readyPort: UInt16?
    private var connections: [UUID: Connection] = [:]
    private var registry = SessionRegistry<UUID>()

    var boundPort: UInt16? { queue.sync { readyPort } }
    var sessionCount: Int { queue.sync { registry.count } }

    init(port: UInt16 = ChannelServer.defaultPort, handsfree: @escaping Handsfree, heardWords: @escaping HeardWords) {
        requestedPort = port
        self.handsfree = handsfree
        self.heardWords = heardWords
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: requestedPort)!)
        let listener = try NWListener(using: parameters)
        let outcome = Mutex<Result<UInt16, HookServerError>?>(nil)
        let settled = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            let result: Result<UInt16, HookServerError>
            switch state {
            case .ready: result = .success(listener.port?.rawValue ?? 0)
            case .failed(let error): result = .failure(.listenFailed(error))
            default: return
            }
            let first = outcome.withLock { current -> Bool in
                guard current == nil else { return false }
                current = result
                return true
            }
            if first { settled.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        queue.sync { self.listener = listener }
        listener.start(queue: queue)
        guard settled.wait(timeout: .now() + 2) == .success else {
            listener.cancel()
            throw HookServerError.timedOut
        }
        switch outcome.withLock({ $0 }) {
        case .success(let port):
            queue.sync { readyPort = port }
            Log.log("channel listener ready on 127.0.0.1:\(port)")
        case .failure(let error):
            throw error
        case nil:
            throw HookServerError.timedOut
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            readyPort = nil
            connections.values.forEach { $0.connection.cancel() }
            connections.removeAll()
            registry = SessionRegistry()
        }
    }

    /// Injects `text` into the session `key` names. False when no connected session matches; the caller
    /// must make that heard.
    func deliver(_ text: String, to key: SessionKey) -> Bool {
        queue.sync {
            guard let id = registry.lookup(key), let connection = connections[id] else { return false }
            let params: [String: Any] = ["content": text]
            send(["jsonrpc": "2.0", "method": "notifications/claude/channel", "params": params], on: connection)
            Log.log("channel: delivered to \(connection.label): \(Log.content(text))")
            return true
        }
    }

    // MARK: - Connections (everything below runs on `queue`)

    private final class Connection: @unchecked Sendable {
        let id = UUID()
        let connection: NWConnection
        var buffer = Data()
        var key: SessionKey?
        var closed = false
        var label: String { key.map { "session \($0.id ?? "?") pid \($0.pid.map(String.init) ?? "?")" } ?? "unregistered connection" }
        init(connection: NWConnection) { self.connection = connection }
    }

    private func accept(_ nw: NWConnection) {
        let connection = Connection(connection: nw)
        connections[connection.id] = connection
        nw.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled: self.close(connection)
            default: break
            }
        }
        nw.start(queue: queue)
        receive(connection)
    }

    private func receive(_ connection: Connection) {
        connection.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !connection.closed else { return }
            if let data { connection.buffer.append(data) }
            self.drainLines(connection)
            if isComplete || error != nil {
                self.close(connection)
                return
            }
            if connection.buffer.count > Self.maxLineBytes {
                Log.log("channel: line too long from \(connection.label), closing")
                self.close(connection)
                return
            }
            self.receive(connection)
        }
    }

    private func close(_ connection: Connection) {
        guard !connection.closed else { return }
        connection.closed = true
        connection.connection.cancel()
        connections.removeValue(forKey: connection.id)
        registry.remove(connection.id)
        Log.log("channel: \(connection.label) closed")
    }

    private func drainLines(_ connection: Connection) {
        while let newline = connection.buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = connection.buffer[connection.buffer.startIndex..<newline]
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            handle(line, on: connection)
        }
    }

    /// The first line is the header the shell one-liner sends; anything starting with `{` is JSON-RPC.
    private func handle(_ line: String, on connection: Connection) {
        if connection.key == nil, !line.hasPrefix("{") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.first == Self.serverName else {
                Log.log("channel: unexpected first line, closing: \(Log.preview(line))")
                close(connection)
                return
            }
            let id = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            let pid = parts.count > 2 ? Int32(parts[2]) : nil
            register(connection, key: SessionKey(id: id, pid: pid))
            return
        }
        if connection.key == nil { register(connection, key: SessionKey(id: nil, pid: nil)) }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.log("channel: bad json from \(connection.label)")
            return
        }
        let method = message["method"] as? String
        let id = RPCID(message["id"])
        switch method {
        case "initialize":
            let protocolVersion = ((message["params"] as? [String: Any])?["protocolVersion"] as? String) ?? "2025-11-25"
            respond(id, result: [
                "protocolVersion": protocolVersion,
                "serverInfo": ["name": Self.serverName, "version": "1.0"],
                "capabilities": ["experimental": ["claude/channel": [:]], "tools": [:]],
                "instructions": Self.instructions,
            ], on: connection)
        case "tools/list":
            respond(id, result: ["tools": [Self.handsfreeTool(), Self.heardWordsTool()]], on: connection)
        case "tools/call":
            let params = message["params"] as? [String: Any]
            let arguments = params?["arguments"] as? [String: Any]
            let connectionID = connection.id
            let queue = queue
            let reply: @Sendable (String) -> Void = { [weak self] text in
                queue.async { [weak self] in
                    guard let self, let connection = self.connections[connectionID] else { return }
                    self.respond(id, result: ["content": [["type": "text", "text": text]]], on: connection)
                }
            }
            switch params?["name"] as? String {
            case "handsfree":
                handsfree(arguments?["action"] as? String ?? "status", reply)
            case "heard_words":
                heardWords(arguments?["action"] as? String ?? "list", arguments?["words"] as? [String] ?? [], reply)
            default:
                respond(id, error: (-32602, "unknown tool"), on: connection)
            }
        case "ping":
            respond(id, result: [:], on: connection)
        case let method? where method.hasPrefix("notifications/"):
            break
        case let method?:
            if id != nil { respond(id, error: (-32601, "method not found: \(method)"), on: connection) }
        case nil:
            break
        }
    }

    private func register(_ connection: Connection, key: SessionKey) {
        connection.key = key
        registry.register(connection.id, key: key)
        Log.log("channel: \(connection.label) connected")
    }

    private static func handsfreeTool() -> [String: Any] { [
        "name": "handsfree",
        "description": "Turn listening after replies on or off, or report its state. On means blether opens the microphone when a reply finishes speaking and sends what the user says into this session.",
        "inputSchema": [
            "type": "object",
            "properties": ["action": ["type": "string", "enum": ["on", "off", "status"], "description": "on: listen after replies; off: stop; status: report only."]],
            "required": ["action"],
        ],
    ] }

    private static func heardWordsTool() -> [String: Any] { [
        "name": "heard_words",
        "description": "Add words the speech-to-text keeps mishearing to blether's correction list, or list it. After each transcription blether swaps anything close in spelling or sound for a listed word, so it fixes \"lara vel\" or \"larravel\" to \"laravel\" and \"live wire\" to \"livewire\". It cannot fix a wild miss (\"daughter\" for \"env\"); that needs the user to say the word differently. Words under three letters are refused: they match too easily. Only add a word the user has said was misheard.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": ["add", "list"], "description": "add: append the words; list: report the current list."],
                "words": ["type": "array", "items": ["type": "string"], "description": "The correctly spelled words to add, for add."],
            ],
            "required": ["action"],
        ],
    ] }

    private func respond(_ id: RPCID?, result: [String: Any], on connection: Connection) {
        guard let id else { return }
        send(["jsonrpc": "2.0", "id": id.json, "result": result], on: connection)
    }

    private func respond(_ id: RPCID?, error: (code: Int, message: String), on connection: Connection) {
        guard let id else { return }
        send(["jsonrpc": "2.0", "id": id.json, "error": ["code": error.code, "message": error.message]], on: connection)
    }

    private func send(_ message: [String: Any], on connection: Connection) {
        guard !connection.closed, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        connection.connection.send(content: data + Data([UInt8(ascii: "\n")]), completion: .contentProcessed { _ in })
    }
}
