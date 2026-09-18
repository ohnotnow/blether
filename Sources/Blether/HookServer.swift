import Foundation
import Network
import Synchronization

enum HookServerError: Error, CustomStringConvertible {
    case timedOut
    case listenFailed(NWError)

    var description: String {
        switch self {
        case .timedOut: "listener did not become ready in time"
        case .listenFailed(let error): "\(error)"
        }
    }
}

/// What a hook payload asks for. Stop carries the reply, markdown already stripped; Notification
/// carries nothing (its message and type are ignored on purpose, the hook matcher filters types).
enum HookEvent: Sendable, Equatable {
    case stop(text: String)
    case notification
}

/// Localhost HTTP listener for the Claude Code hook payload. One transport for local and remote.
/// Hands the caller the event and the `profile` query parameter, if any.
/// All mutable state is confined to `queue`.
final class HookServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 8765
    static let maxBodyBytes = 1 << 20
    static let idleTimeout: TimeInterval = 10

    private let queue = DispatchQueue(label: "uk.ohnotnow.blether.hook-server")
    private let requestedPort: UInt16
    private let allInterfaces: Bool
    private let onEvent: @Sendable (_ event: HookEvent, _ profile: String?) -> Void
    private var listener: NWListener?
    private var readyPort: UInt16?

    /// The port actually bound, once `start()` has returned. Useful when asking for port 0.
    var boundPort: UInt16? { queue.sync { readyPort } }

    /// `allInterfaces` binds the port on every interface, IPv4 and IPv6, for remote mode (blether-csm6b:
    /// LAN-only, no authentication). False binds loopback only.
    init(port: UInt16 = HookServer.defaultPort, allInterfaces: Bool = false, onEvent: @escaping @Sendable (_ event: HookEvent, _ profile: String?) -> Void) {
        requestedPort = port
        self.allInterfaces = allInterfaces
        self.onEvent = onEvent
    }

    /// Binds and waits (at most two seconds) for the listener to be ready.
    /// Throws if the port is taken or the listener fails to come up.
    func start() throws {
        let parameters = NWParameters.tcp
        let port = NWEndpoint.Port(rawValue: requestedPort)!
        let listener: NWListener
        if allInterfaces {
            listener = try NWListener(using: parameters, on: port)
        } else {
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            listener = try NWListener(using: parameters)
        }
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
            Log.log(allInterfaces ? "hook listener ready on all interfaces, port \(port) (LAN)" : "hook listener ready on 127.0.0.1:\(port)")
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
        }
    }

    // MARK: - Connections (everything below runs on `queue`)

    /// Per-connection receive buffer. Confined to `queue`, hence the unchecked Sendable.
    private final class Session: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var finished = false
        init(connection: NWConnection) { self.connection = connection }
    }

    private func accept(_ connection: NWConnection) {
        let session = Session(connection: connection)
        connection.start(queue: queue)
        receive(session)
        queue.asyncAfter(deadline: .now() + Self.idleTimeout) {
            guard !session.finished else { return }
            session.finished = true
            connection.cancel()
        }
    }

    private func receive(_ session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !session.finished else { return }
            if let data { session.buffer.append(data) }
            if error != nil {
                session.finished = true
                session.connection.cancel()
                return
            }
            self.process(session, atEnd: isComplete)
        }
    }

    private func process(_ session: Session, atEnd: Bool) {
        if let (head, _) = HTTPRequest.parseHead(session.buffer) {
            guard let length = head.declaredContentLength else {
                respond(session, status: 400, body: #"{"error":"bad content-length"}"#)
                return
            }
            if length > Self.maxBodyBytes {
                respond(session, status: 413, body: #"{"error":"payload too large"}"#)
                return
            }
        }
        guard let request = HTTPRequest.parse(session.buffer) else {
            if atEnd || session.buffer.count > Self.maxBodyBytes {
                session.finished = true
                session.connection.cancel()
            } else {
                receive(session)
            }
            return
        }
        handle(request, on: session)
    }

    private func handle(_ request: HTTPRequest, on session: Session) {
        // The old claude-speaks clients still send an Authorization header. Nothing reads it, on purpose:
        // blether is LAN-only and has no shared secret (blether-csm6b).
        guard request.path == "/hook" else {
            respond(session, status: 404, body: #"{"error":"not found"}"#)
            return
        }
        guard request.method == "POST" else {
            respond(session, status: 405, body: #"{"error":"method not allowed"}"#)
            return
        }
        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: request.body)
        } catch {
            Log.log("hook rejected: bad json")
            respond(session, status: 400, body: #"{"error":"bad json"}"#)
            return
        }
        // Answer before any speech work so the hook never waits on synthesis.
        respond(session, status: 200, body: #"{"ok":true}"#)

        let profile = request.query["profile"]
        let label = profile.map { " (profile: \($0))" } ?? ""
        switch payload.hookEventName {
        case "Stop":
            let text = SpeechText.stripMarkdown(payload.lastAssistantMessage ?? "")
            guard !text.isEmpty else {
                Log.log("hook Stop: empty reply, nothing to speak")
                return
            }
            Log.log("hook Stop\(label): \(Log.preview(text))")
            onEvent(.stop(text: text), profile)
        case "Notification":
            Log.log("hook Notification\(label)")
            onEvent(.notification, profile)
        default:
            Log.log("hook \(payload.hookEventName) ignored")
        }
    }

    private static let reasons: [Int: String] = [
        200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
    ]

    private func respond(_ session: Session, status: Int, body: String) {
        session.finished = true
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "")\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(bytes.count)\r\n"
            + "Connection: close\r\n\r\n"
        let connection = session.connection
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
