import XCTest
@testable import Blether

final class ReplyPlannerTests: XCTestCase {
    private let llm = FakeLLM()
    private lazy var planner = ReplyPlanner(llm: llm)
    private let short = "Done. Two files changed and the tests pass."
    private let long = Array(repeating: "word", count: 70).joined(separator: " ")

    private func plan(_ text: String, monologue: Persona? = .marvin, main: Persona? = nil, preamble: Bool = true) async -> [PlannedClip] {
        await planner.plan(text, monologuePersona: monologue, mainPersona: main, includePreamble: preamble)
    }

    func testShortReplyGetsPreambleAndRawText() async {
        let clips = await plan(short)
        XCTAssertEqual(llm.preambleCalls, 1)
        XCTAssertEqual(llm.summaryCalls, 0)
        XCTAssertEqual(clips, [PlannedClip(text: "Oh joy, another reply ...", role: .monologue), PlannedClip(text: short, role: .main)])
    }

    func testLongReplyIsSummarised() async {
        let clips = await plan(long)
        XCTAssertEqual(llm.preambleCalls, 1)
        XCTAssertEqual(llm.summaryCalls, 1)
        XCTAssertEqual(clips.map(\.role), [.monologue, .main])
        XCTAssertEqual(clips[1].text, "Compressed.")
        XCTAssertEqual(llm.calls.first { $0.system.contains("Compress") }?.user, long)
    }

    func testNoPreambleWhenNotWanted() async {
        let clips = await plan(short, preamble: false)
        XCTAssertEqual(llm.preambleCalls, 0)
        XCTAssertEqual(clips, [PlannedClip(text: short, role: .main)])
    }

    func testNoPreambleWithoutAPersona() async {
        let clips = await plan(short, monologue: nil)
        XCTAssertEqual(llm.preambleCalls, 0)
        XCTAssertEqual(clips.count, 1)
    }

    func testPreambleIsCleanedToOneBareLine() async {
        llm.preambleScript = { _ in "\"Oh joy.\"\nSecond line" }
        let clips = await plan(short)
        XCTAssertEqual(clips[0].text, "Oh joy ...")
    }

    func testPreambleFailureIsHeardAsHeadsUp() async {
        llm.preambleScript = { _ in throw LLMError.emptyResponse }
        let clips = await plan(short)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips[0].text, "Heads up, the preamble call fell over. Raw reply coming up. " + short)
    }

    /// Matches marvinise in the old code: nothing usable means no preamble, not a heads-up.
    func testEmptyPreambleIsDroppedQuietly() async {
        llm.preambleScript = { _ in "\"\"" }
        let clips = await plan(short)
        XCTAssertEqual(clips, [PlannedClip(text: short, role: .main)])
    }

    func testSummaryFailureSpeaksRawTextWithHeadsUp() async {
        llm.summaryScript = { _ in throw LLMError.http(500, "boom") }
        let clips = await plan(long)
        XCTAssertEqual(clips.count, 2)
        XCTAssertTrue(clips[1].text.hasPrefix("Heads up, the summariser call fell over. Raw reply coming up. word word"))
    }

    func testBothFailuresAreNamed() async {
        llm.preambleScript = { _ in throw LLMError.emptyResponse }
        llm.summaryScript = { _ in throw LLMError.emptyResponse }
        let clips = await plan(long)
        XCTAssertEqual(clips.count, 1)
        XCTAssertTrue(clips[0].text.hasPrefix("Heads up, the preamble and summariser call fell over."))
    }

    func testEmptySummaryFallsBackToRawTextQuietly() async {
        llm.summaryScript = { _ in "  " }
        let clips = await plan(long, preamble: false)
        XCTAssertEqual(clips, [PlannedClip(text: long, role: .main)])
    }

    func testMainClipIsCappedAt800() async {
        llm.summaryScript = { _ in "" }
        let text = Array(repeating: "abcdefghi", count: 100).joined(separator: " ")
        let clips = await plan(text, preamble: false)
        // 100 words of 9 letters plus spaces: the cut lands at the last space under 800, then the ellipsis.
        XCTAssertEqual(clips[0].text, Array(repeating: "abcdefghi", count: 80).joined(separator: " ") + "…")
        XCTAssertLessThanOrEqual(clips[0].text.count, 801)
    }

    func testMainPersonaIsAddedToSummaryPrompt() async {
        _ = await plan(long, main: .marvin, preamble: false)
        XCTAssertTrue(llm.calls[0].system.contains("written in the voice of: Marvin the Paranoid Android"))
        _ = await plan(long, main: nil, preamble: false)
        XCTAssertFalse(llm.calls[1].system.contains("written in the voice of"))
    }
}
