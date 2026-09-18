import Foundation
@testable import Blether

/// Answers preamble, summary and notification prompts from three scripts and records every call.
final class FakeLLM: LLM, @unchecked Sendable {
    typealias Script = @Sendable (String) throws -> String
    private let lock = NSLock()
    private var recorded: [(system: String, user: String)] = []
    var preambleScript: Script = { _ in "Oh joy, another reply" }
    var summaryScript: Script = { _ in "Compressed." }
    var quipScript: Script = { _ in "Typical." }
    var toneScript: Script = { _ in #"{"style": "neutral"}"# }

    var calls: [(system: String, user: String)] { lock.withLock { recorded } }
    // The summary prompt itself contains the word "preamble", so route on the summary's phrase.
    private static func isSummary(_ system: String) -> Bool { system.contains("Compress aggressively") }
    private static func isQuip(_ system: String) -> Bool { system.contains("left waiting") }
    private static func isTone(_ system: String) -> Bool { system.contains("classify the tone") }
    var preambleCalls: Int { calls.filter { !Self.isSummary($0.system) && !Self.isQuip($0.system) && !Self.isTone($0.system) }.count }
    var toneCalls: Int { calls.filter { Self.isTone($0.system) }.count }
    var summaryCalls: Int { calls.filter { Self.isSummary($0.system) }.count }
    var quipCalls: Int { calls.filter { Self.isQuip($0.system) }.count }

    func complete(system: String, user: String) async throws -> String {
        lock.withLock { recorded.append((system, user)) }
        if Self.isSummary(system) { return try summaryScript(user) }
        if Self.isQuip(system) { return try quipScript(user) }
        if Self.isTone(system) { return try toneScript(user) }
        return try preambleScript(user)
    }
}
