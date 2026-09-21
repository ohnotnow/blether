import XCTest
@testable import Blether

final class PronunciationsTests: XCTestCase {
    private let pairs = [
        Pronunciation(original: "kubectl", replacement: "cube-control"),
        Pronunciation(original: "id", replacement: "I.D"),
        Pronunciation(original: ".env", replacement: "dot-env"),
        Pronunciation(original: "SKILL.md", replacement: "skill dot M D"),
    ]

    func testEmptyListIsIdentity() {
        XCTAssertEqual(Pronunciations.apply("run kubectl", []), "run kubectl")
    }

    func testWholeWordsOnly() {
        XCTAssertEqual(Pronunciations.apply("the id of the kid's identity", pairs), "the I.D of the kid's identity")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(Pronunciations.apply("Kubectl and KUBECTL", pairs), "cube-control and cube-control")
    }

    func testDottedOriginalsMatch() {
        XCTAssertEqual(Pronunciations.apply("edit .env and SKILL.md", pairs), "edit dot-env and skill dot M D")
    }

    func testTrailingPunctuationIsKept() {
        XCTAssertEqual(Pronunciations.apply("Run kubectl. Then (kubectl), \"kubectl\"!", pairs), "Run cube-control. Then (kubectl), \"kubectl\"!")
    }

    func testEdgesAndLinesCount() {
        XCTAssertEqual(Pronunciations.apply("id\nid", pairs), "I.D\nI.D")
    }

    func testBlankOriginalIsIgnored() {
        XCTAssertEqual(Pronunciations.apply("hello", [Pronunciation(original: " ", replacement: "x")]), "hello")
    }

    func testRegexCharactersInTheOriginalAreLiteral() {
        XCTAssertEqual(Pronunciations.apply("say c++ now", [Pronunciation(original: "c++", replacement: "see plus plus")]), "say see plus plus now")
    }

    func testPairsApplyInOrder() {
        let pairs = [Pronunciation(original: "a", replacement: "b"), Pronunciation(original: "b", replacement: "c")]
        XCTAssertEqual(Pronunciations.apply("a", pairs), "c")
    }
}
