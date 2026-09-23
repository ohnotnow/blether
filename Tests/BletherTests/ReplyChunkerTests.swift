import XCTest
@testable import Blether

final class ReplyChunkerTests: XCTestCase {
    func testShortSentencesJoinUpToTheLimit() {
        XCTAssertEqual(ReplyChunker.split("One two. Three four. Five six.", limit: 20), ["One two. Three four.", "Five six."])
    }

    func testAParagraphBreakAlwaysEndsAChunk() {
        XCTAssertEqual(ReplyChunker.split("First.\n\nSecond.", limit: 200), ["First.", "Second."])
    }

    func testASentenceLongerThanTheLimitStandsAlone() {
        let long = "This sentence is rather longer than the limit allows."
        XCTAssertEqual(ReplyChunker.split("Hi. \(long) Bye.", limit: 20), ["Hi.", long, "Bye."])
    }

    func testAbbreviationsDoNotEndASentence() {
        XCTAssertEqual(ReplyChunker.split("Ask Dr. Smith about it. Then stop.", limit: 25), ["Ask Dr. Smith about it.", "Then stop."])
    }

    func testBlankOrEmptyTextGivesNoChunks() {
        XCTAssertEqual(ReplyChunker.split(""), [])
        XCTAssertEqual(ReplyChunker.split("  \n\n "), [])
    }
}
