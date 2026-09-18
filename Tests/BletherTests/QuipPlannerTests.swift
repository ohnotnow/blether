import XCTest
@testable import Blether

final class QuipPlannerTests: XCTestCase {
    private let llm = FakeLLM()
    private lazy var planner = QuipPlanner(llm: llm)
    private let french = NotificationLanguages(parsing: "French")

    func testPromptCarriesPersonaLanguageAndHistory() async {
        let quip = await planner.plan(persona: .marvin, languages: french, history: ["Oh no.", "Typical."])
        XCTAssertEqual(quip, PlannedQuip(text: "Typical.", language: "French"))
        XCTAssertEqual(llm.quipCalls, 1)
        let system = llm.calls[0].system
        XCTAssertTrue(system.contains(Persona.marvin.description), system)
        XCTAssertTrue(system.contains("Reply in French."), system)
        XCTAssertTrue(system.contains("- Oh no.\n- Typical."), system)
        XCTAssertEqual(llm.calls[0].user, "")
    }

    func testNoHistoryAndNoPersonaStillQuip() async {
        _ = await planner.plan(persona: nil, languages: french, history: [])
        let system = llm.calls[0].system
        XCTAssertTrue(system.contains("in the voice of: a coding assistant."), system)
        XCTAssertTrue(system.contains("(no recent history)"), system)
    }

    func testFirstLineIsKeptQuotesGoAndTrailingPunctuationStays() async {
        llm.quipScript = { _ in "\n \"Merde!\" \nAnd a second line the model should not have written." }
        let quip = await planner.plan(persona: .marvin, languages: french, history: [])
        XCTAssertEqual(quip?.text, "Merde!")
    }

    func testEmptyReplyAndThrownErrorGiveNil() async {
        llm.quipScript = { _ in "  \n " }
        let empty = await planner.plan(persona: .marvin, languages: french, history: [])
        XCTAssertNil(empty)
        llm.quipScript = { _ in throw URLError(.cannotConnectToHost) }
        let failed = await planner.plan(persona: .marvin, languages: french, history: [])
        XCTAssertNil(failed)
    }

    func testLongLineIsCapped() async {
        llm.quipScript = { _ in Array(repeating: "sigh", count: 100).joined(separator: " ") }
        let quip = await planner.plan(persona: .marvin, languages: french, history: [])
        XCTAssertLessThanOrEqual(quip!.text.count, QuipPlanner.cap + 1, "cap plus the ellipsis")
        XCTAssertTrue(quip!.text.hasSuffix("…"))
    }
}
