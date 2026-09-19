import Foundation
import Synchronization

enum HelperError: Error, Equatable {
    case notReady
    case exited(Int32)
    case timedOut
    case refused(String)
    case badReply(String)
}

/// One long-lived child process speaking the JSON-lines helper protocol (see Helpers/kokoro.py for
/// the contract). Knows nothing about what the child synthesises. Restarts it if it dies.
actor HelperProcess {
    struct Voice: Decodable, Sendable, Equatable {
        let id: String
        let name: String
        let language: String
    }

    enum State: Equatable, Sendable {
        case starting
        case ready
        case failed(String)
    }

    static let maxConsecutiveFailures = 5
    static let maxRespawnDelay: Duration = .seconds(30)

    private let executable: URL
    private let arguments: [String]
    private let firstRespawnDelay: Duration
    private let onState: @Sendable (State) -> Void

    /// Reachable from the nonisolated `stop()`, which the app calls while terminating and cannot await.
    private struct Live: @unchecked Sendable {
        var process: Process?
        var stdin: FileHandle?
        var stopped = false
    }
    private let live = Mutex(Live())

    private(set) var state: State = .failed("not started")
    private(set) var voices: [Voice] = []
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]
    private var generation = 0
    private var consecutiveFailures = 0
    private var fatalSeen = false
    private var lastStderrLine = ""
    private var stdoutLines = LineBuffer()
    private var stderrLines = LineBuffer()
    private var respawn: Task<Void, Never>?

    init(executable: URL, arguments: [String], firstRespawnDelay: Duration = .seconds(2), onState: @escaping @Sendable (State) -> Void) {
        self.executable = executable
        self.arguments = arguments
        self.firstRespawnDelay = firstRespawnDelay
        self.onState = onState
    }

    /// Spawns (or respawns after a gave-up) and returns once the child is `.ready` or `.failed`.
    func start() async {
        if state == .ready { return }
        if state != .starting {
            consecutiveFailures = 0
            fatalSeen = false
            live.withLock { $0.stopped = false }
            spawn()
        }
        while state == .starting {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Sends one request and waits for its reply. Waits through `.starting` (warm-up, first-run model
    /// download, respawn) bounded by `timeout`; only `.failed` throws `.notReady` at once.
    /// `lang` is Kokoro's code for the language of the text; nil leaves the helper's default (British English).
    func request(text: String, voice: String, out: URL, lang: String? = nil, timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        while state == .starting {
            if ContinuousClock.now >= deadline { throw HelperError.timedOut }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard state == .ready, let stdin = live.withLock({ $0.stdin }) else { throw HelperError.notReady }

        let id = UUID().uuidString
        let line = try JSONEncoder().encode(Request(id: id, text: text, voice: voice, out: out.path, lang: lang)) + Data("\n".utf8)
        do {
            try stdin.write(contentsOf: line)
        } catch {
            throw HelperError.notReady
        }
        let watchdog = Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            self.timeOut(id)
        }
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending[id] = continuation
        }
    }

    /// Kills the child and cancels any respawn. Synchronous so applicationWillTerminate can call it.
    nonisolated func stop() {
        let process = live.withLock { live -> Process? in
            live.stopped = true
            return live.process
        }
        process?.terminate()
    }

    nonisolated var isRunning: Bool {
        live.withLock { $0.process?.isRunning ?? false }
    }

    // MARK: - Lifecycle

    private struct Request: Encodable {
        let id: String
        let text: String
        let voice: String
        let out: String
        /// Omitted from the JSON when nil; the helper then uses its default.
        let lang: String?
    }

    private struct ReadyEvent: Decodable {
        let voices: [Voice]
    }

    private func setState(_ new: State) {
        state = new
        onState(new)
    }

    private func spawn() {
        generation += 1
        let gen = generation
        stdoutLines = LineBuffer()
        stderrLines = LineBuffer()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.exited(status, generation: gen) }
        }

        setState(.starting)
        do {
            try process.run()
        } catch {
            setState(.failed("could not launch \(executable.lastPathComponent): \(error.localizedDescription)"))
            return
        }
        live.withLock {
            $0.process = process
            $0.stdin = stdin.fileHandleForWriting
        }
        Log.log("helper \(executable.lastPathComponent) started, pid \(process.processIdentifier)")

        // FileHandle.bytes.lines holds lines back until the pipe closes, so read with the readability
        // handler instead. It runs on a private serial queue; the LineBuffer keeps order into the actor.
        let outBuffer = stdoutLines, errBuffer = stderrLines
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            outBuffer.append(data)
            Task { await self?.drainStdout(generation: gen) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            errBuffer.append(data)
            Task { await self?.drainStderr(generation: gen) }
        }
    }

    private func drainStdout(generation gen: Int) {
        guard gen == generation else { return }
        for line in stdoutLines.popLines() { handle(line: line, generation: gen) }
    }

    private func drainStderr(generation gen: Int) {
        guard gen == generation else { return }
        let name = executable.lastPathComponent
        for line in stderrLines.popLines() {
            lastStderrLine = line
            Log.log("\(name): \(line)")
        }
    }

    private func handle(line: String, generation gen: Int) {
        guard gen == generation else { return }
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.log("helper: non-JSON line ignored: \(Log.content(line))")
            return
        }
        if let event = object["event"] as? String {
            switch event {
            case "ready":
                voices = (try? JSONDecoder().decode(ReadyEvent.self, from: data))?.voices ?? []
                consecutiveFailures = 0
                setState(.ready)
            case "status":
                Log.log("helper status: \(object["message"] as? String ?? "")")
            case "fatal":
                fatalSeen = true
                let message = object["message"] as? String ?? "fatal"
                failPending(with: .notReady)
                setState(.failed(message))
            default:
                Log.log("helper: unknown event \(event) ignored")
            }
            return
        }
        guard let id = object["id"] as? String else {
            Log.log("helper: line with neither event nor id ignored")
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else {
            Log.log("helper: reply for unknown or timed-out id dropped")
            return
        }
        if object["ok"] as? Bool == true {
            continuation.resume()
        } else if let error = object["error"] as? String {
            continuation.resume(throwing: HelperError.refused(error))
        } else {
            continuation.resume(throwing: HelperError.badReply(line))
        }
    }

    private func timeOut(_ id: String) {
        pending.removeValue(forKey: id)?.resume(throwing: HelperError.timedOut)
    }

    private func failPending(with error: HelperError) {
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: error) }
    }

    private func exited(_ status: Int32, generation gen: Int) {
        guard gen == generation else { return }
        let stopped = live.withLock { live -> Bool in
            live.process = nil
            live.stdin = nil
            return live.stopped
        }
        failPending(with: .exited(status))
        if fatalSeen { return }  // the fatal event already set the state; a fatal child is not respawned
        if stopped {
            setState(.failed("stopped"))
            return
        }
        consecutiveFailures += 1
        if consecutiveFailures >= Self.maxConsecutiveFailures {
            setState(.failed("gave up after \(Self.maxConsecutiveFailures) attempts: \(lastStderrLine)"))
            return
        }
        let delay = min(firstRespawnDelay * Double(1 << (consecutiveFailures - 1)), Self.maxRespawnDelay)
        setState(.failed("exited with \(status), restarting in \(delay)"))
        respawn = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, gen == self.generation, !self.live.withLock({ $0.stopped }) else { return }
            self.spawn()
        }
    }
}

/// Bytes in from any thread, complete lines out in arrival order.
private final class LineBuffer: Sendable {
    private let state = Mutex<(pending: Data, lines: [String])>((Data(), []))

    func append(_ data: Data) {
        state.withLock { state in
            state.pending.append(data)
            while let newline = state.pending.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = state.pending.subdata(in: state.pending.startIndex ..< newline)
                state.pending.removeSubrange(state.pending.startIndex ... newline)
                state.lines.append(String(decoding: lineData, as: UTF8.self))
            }
        }
    }

    func popLines() -> [String] {
        state.withLock { state in
            defer { state.lines.removeAll() }
            return state.lines
        }
    }
}
