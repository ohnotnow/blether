import Foundation
@testable import Blether

/// Answers preamble and summary prompts from two scripts and records every call.
final class FakeLLM: LLM, @unchecked Sendable {
    typealias Script = @Sendable (String) throws -> String
    private let lock = NSLock()
    private var recorded: [(system: String, user: String)] = []
    var preambleScript: Script = { _ in "Oh joy, another reply" }
    var summaryScript: Script = { _ in "Compressed." }

    var calls: [(system: String, user: String)] { lock.withLock { recorded } }
    // The summary prompt itself contains the word "preamble", so route on the summary's phrase.
    private static func isSummary(_ system: String) -> Bool { system.contains("Compress aggressively") }
    var preambleCalls: Int { calls.filter { !Self.isSummary($0.system) }.count }
    var summaryCalls: Int { calls.filter { Self.isSummary($0.system) }.count }

    func complete(system: String, user: String) async throws -> String {
        lock.withLock { recorded.append((system, user)) }
        return Self.isSummary(system) ? try summaryScript(user) : try preambleScript(user)
    }
}
