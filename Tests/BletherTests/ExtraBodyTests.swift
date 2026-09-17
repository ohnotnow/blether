import XCTest
@testable import Blether

final class ExtraBodyTests: XCTestCase {
    func testEmptyAndBlankAndBracesAreAnEmptyObject() {
        for text in ["{}", "", "  \n", " {} "] {
            XCTAssertEqual(ExtraBody.parse(text)?.count, 0, text)
            XCTAssertNil(ExtraBody.problem(text), text)
        }
    }

    func testObjectKeysComeThrough() throws {
        let parsed = try XCTUnwrap(ExtraBody.parse(#"{"reasoning_effort": "none", "n": 1}"#))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed["reasoning_effort"] as? String, "none")
    }

    func testNonObjectsAreNil() {
        for text in ["[1]", "nope", "\"str\"", "{\"a\":", "42"] {
            XCTAssertNil(ExtraBody.parse(text), text)
            XCTAssertNotNil(ExtraBody.problem(text), text)
        }
    }

    func testProblemDistinguishesArrayFromGarbage() {
        XCTAssertEqual(ExtraBody.problem("[1]"), "top level is not an object")
        XCTAssertFalse(ExtraBody.problem("nope")?.isEmpty ?? true)
    }
}
