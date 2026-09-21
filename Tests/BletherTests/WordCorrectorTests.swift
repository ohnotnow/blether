import XCTest
@testable import Blether

final class WordCorrectorTests: XCTestCase {
    private let words = ["laravel", "livewire", "CVE", "postgres"]

    func testEmptyListLeavesTextAlone() {
        XCTAssertEqual(WordCorrector.correct("I use lara vel", words: []), "I use lara vel")
    }

    func testExactMatchTakesTheListedSpelling() {
        XCTAssertEqual(WordCorrector.correct("it is a cve", words: words), "it is a CVE")
    }

    func testOneLetterOutIsCorrected() {
        XCTAssertEqual(WordCorrector.correct("I use larravel a lot", words: words), "I use laravel a lot")
    }

    func testTwoWordsHeardForOneAreJoined() {
        XCTAssertEqual(WordCorrector.correct("I use lara vel and live wire", words: words), "I use laravel and livewire")
    }

    func testSoundalikeIsCorrected() {
        XCTAssertEqual(WordCorrector.correct("try post grass", words: words), "try postgres")
    }

    func testPunctuationAroundTheWordIsKept() {
        XCTAssertEqual(WordCorrector.correct("(larravel, livewyre!)", words: words), "(laravel, livewire!)")
    }

    func testAWindowNeverCrossesPunctuation() {
        XCTAssertEqual(WordCorrector.correct("live, wire", words: words), "live, wire")
    }

    func testCaseOfTheHeardWordIsKept() {
        XCTAssertEqual(WordCorrector.correct("Larravel LARRAVEL", words: words), "Laravel LARAVEL")
    }

    func testUnrelatedWordsAreLeftAlone() {
        XCTAssertEqual(WordCorrector.correct("the cat sat on the mat", words: words), "the cat sat on the mat")
    }

    /// Handy's scoring, kept as is: a short listed word swallows its soundalikes, because one letter
    /// out of two is a big edit but the Soundex bonus forgives it. So the Listening page warns off short words.
    func testAShortListedWordSwallowsItsSoundalikes() {
        XCTAssertEqual(WordCorrector.correct("the id is fine", words: ["id"]), "the id is fine")
        XCTAssertEqual(WordCorrector.correct("it is fine", words: ["id"]), "id is fine")
    }

    func testNonASCIIWordsInTheListAreSkipped() {
        XCTAssertEqual(WordCorrector.correct("hello", words: ["日本語"]), "hello")
    }
}
