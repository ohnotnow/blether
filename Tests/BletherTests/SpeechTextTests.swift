import XCTest
@testable import Blether

final class SpeechTextTests: XCTestCase {
    func testDropsFencedCodeBlocks() {
        XCTAssertEqual(SpeechText.stripMarkdown("before\n```swift\nlet x = 1\n```\nafter"), "before\n\nafter")
    }

    func testKeepsLinkTextDropsURL() {
        XCTAssertEqual(SpeechText.stripMarkdown("see [the docs](https://example.com/x) now"), "see the docs now")
    }

    func testUnwrapsInlineCode() {
        XCTAssertEqual(SpeechText.stripMarkdown("run `make test` twice"), "run make test twice")
    }

    func testDropsHeadingHashes() {
        XCTAssertEqual(SpeechText.stripMarkdown("## Title\nbody"), "Title\nbody")
    }

    func testDropsListBullets() {
        XCTAssertEqual(SpeechText.stripMarkdown("- one\n* two\n  - three"), "one\ntwo\nthree")
    }

    func testDropsListNumbering() {
        XCTAssertEqual(SpeechText.stripMarkdown("1. one\n2. two\n10. ten"), "one\ntwo\nten")
    }

    func testRemovesRemainingAsterisks() {
        XCTAssertEqual(SpeechText.stripMarkdown("**bold** and *italic* and a*b"), "bold and italic and ab")
    }

    func testCollapsesThreeOrMoreNewlines() {
        XCTAssertEqual(SpeechText.stripMarkdown("a\n\n\n\nb\n\n\nc"), "a\n\nb\n\nc")
    }

    /// The bullet regex swallows the blank line before a list; the Python original does the same.
    func testMixedExample() {
        let input = """
        # Done

        I changed **two** files:

        - `Makefile`, see [the notes](https://example.com)
        - `project.yml`

        ```sh
        make test
        ```



        All green.
        """
        XCTAssertEqual(SpeechText.stripMarkdown(input), "Done\n\nI changed two files:\nMakefile, see the notes\nproject.yml\n\nAll green.")
    }
}

final class SpeechTextHelpersTests: XCTestCase {
    func testCapLeavesShortTextAlone() {
        XCTAssertEqual(SpeechText.cap("short", limit: 10), "short")
    }

    func testCapCutsAtLastSpaceAndMarksTheCut() {
        XCTAssertEqual(SpeechText.cap("one two three four", limit: 12), "one two…")
    }

    func testCapWithNoSpaceCutsHard() {
        XCTAssertEqual(SpeechText.cap("abcdefghij", limit: 5), "abcde…")
    }

    func testFirstLineSkipsBlankLines() {
        XCTAssertEqual(SpeechText.firstLine("\n\n  Oh joy.  \nmore"), "Oh joy.")
        XCTAssertEqual(SpeechText.firstLine("  \n "), "")
    }
}
