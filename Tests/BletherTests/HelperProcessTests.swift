import Synchronization
import XCTest
@testable import Blether

/// Records the states a HelperProcess reports, from whatever thread it reports them on.
final class StateBox: Sendable {
    private let states = Mutex<[HelperProcess.State]>([])
    func append(_ state: HelperProcess.State) { states.withLock { $0.append(state) } }
    var all: [HelperProcess.State] { states.withLock { $0 } }
}

final class HelperProcessTests: XCTestCase {
    private let states = StateBox()
    private var helper: HelperProcess!

    static func fakeScript() throws -> URL {
        try XCTUnwrap(Bundle(for: HelperProcessTests.self).url(forResource: "fake_helper", withExtension: "py"))
    }

    private func makeHelper(_ flags: [String] = [], respawnDelay: Duration = .milliseconds(200)) throws -> HelperProcess {
        let states = states
        return HelperProcess(
            executable: URL(filePath: "/usr/bin/python3"),
            arguments: [try Self.fakeScript().path] + flags,
            firstRespawnDelay: respawnDelay
        ) { states.append($0) }
    }

    private func tempWAV() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("blether-helper-\(UUID().uuidString).wav")
    }

    override func tearDown() async throws {
        helper?.stop()
        for _ in 0 ..< 40 where helper?.isRunning == true { try await Task.sleep(for: .milliseconds(50)) }
    }

    func testStartReachesReadyAndPublishesTheFakeVoices() async throws {
        helper = try makeHelper()
        await helper.start()
        let voices = await helper.voices
        XCTAssertEqual(voices.map(\.id), ["af_heart", "bm_george"])
        XCTAssertEqual(voices.map(\.language), ["en-US", "en-GB"])
        XCTAssertEqual(states.all, [.starting, .ready])
    }

    func testRequestWritesTheFileAndConcurrentRequestsBothReturn() async throws {
        helper = try makeHelper()
        await helper.start()
        let a = tempWAV(), b = tempWAV()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let helper = helper!
        async let first: Void = helper.request(text: "one", voice: "af_heart", out: a, timeout: .seconds(5))
        async let second: Void = helper.request(text: "two", voice: "bm_george", out: b, timeout: .seconds(5))
        try await first
        try await second
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testRefusedVoiceThrowsRefused() async throws {
        helper = try makeHelper()
        await helper.start()
        await assertThrows(.refused("unknown voice")) {
            try await self.helper.request(text: "x", voice: "bad", out: self.tempWAV(), timeout: .seconds(5))
        }
    }

    func testHangTimesOutAndTheNextRequestStillWorks() async throws {
        helper = try makeHelper()
        await helper.start()
        await assertThrows(.timedOut) {
            try await self.helper.request(text: "hang", voice: "af_heart", out: self.tempWAV(), timeout: .seconds(1))
        }
        let out = tempWAV()
        defer { try? FileManager.default.removeItem(at: out) }
        try await helper.request(text: "fine", voice: "af_heart", out: out, timeout: .seconds(5))
    }

    func testGarbledReplyThrowsBadReply() async throws {
        helper = try makeHelper()
        await helper.start()
        do {
            try await helper.request(text: "garble", voice: "af_heart", out: tempWAV(), timeout: .seconds(5))
            XCTFail("expected a throw")
        } catch let error as HelperError {
            guard case .badReply = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testCrashFailsThePendingRequestThenRespawns() async throws {
        helper = try makeHelper()
        await helper.start()
        await assertThrows(.exited(3)) {
            try await self.helper.request(text: "crash", voice: "af_heart", out: self.tempWAV(), timeout: .seconds(5))
        }
        for _ in 0 ..< 100 where states.all.filter({ $0 == .ready }).count < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(states.all.filter { $0 == .ready }.count, 2, "\(states.all)")
        XCTAssertTrue(states.all.contains { if case .failed = $0 { true } else { false } })
        let out = tempWAV()
        defer { try? FileManager.default.removeItem(at: out) }
        try await helper.request(text: "after", voice: "af_heart", out: out, timeout: .seconds(5))
    }

    func testFatalIsTerminalAndNotRespawned() async throws {
        helper = try makeHelper(["--fatal"])
        await helper.start()
        let state = await helper.state
        XCTAssertEqual(state, .failed("fake could not start"))
        try await Task.sleep(for: .milliseconds(700))
        let later = await helper.state
        XCTAssertEqual(later, .failed("fake could not start"))
        XCTAssertEqual(states.all.filter { $0 == .starting }.count, 1, "\(states.all)")
        await assertThrows(.notReady) {
            try await self.helper.request(text: "x", voice: "af_heart", out: self.tempWAV(), timeout: .seconds(5))
        }
    }

    func testRequestDuringStartingWaitsForReady() async throws {
        helper = try makeHelper(["--delay", "1"])
        let helper = helper!
        Task { await helper.start() }
        for _ in 0 ..< 40 {
            if await helper.state == .starting { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let out = tempWAV()
        defer { try? FileManager.default.removeItem(at: out) }
        try await helper.request(text: "early", voice: "af_heart", out: out, timeout: .seconds(10))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func testStopLeavesNoChildRunning() async throws {
        helper = try makeHelper()
        await helper.start()
        XCTAssertTrue(helper.isRunning)
        helper.stop()
        for _ in 0 ..< 40 where helper.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(helper.isRunning)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(helper.isRunning, "must not respawn after stop")
    }

    private func assertThrows(_ expected: HelperError, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)")
        } catch let error as HelperError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
