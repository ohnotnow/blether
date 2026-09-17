import XCTest
@testable import Blether

final class HookPayloadTests: XCTestCase {
    private func decode(_ json: String) throws -> HookPayload {
        try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
    }

    func testDecodesAllFields() throws {
        let payload = try decode(#"{"hook_event_name":"Stop","last_assistant_message":"hi","session_id":"abc"}"#)
        XCTAssertEqual(payload.hookEventName, "Stop")
        XCTAssertEqual(payload.lastAssistantMessage, "hi")
        XCTAssertEqual(payload.sessionId, "abc")
    }

    func testIgnoresUnknownKeysAndMissingOptionals() throws {
        let payload = try decode(#"{"hook_event_name":"Notification","claude_speaks":{"voice":"x"}}"#)
        XCTAssertEqual(payload.hookEventName, "Notification")
        XCTAssertNil(payload.lastAssistantMessage)
        XCTAssertNil(payload.sessionId)
    }

    func testMissingEventNameFails() {
        XCTAssertThrowsError(try decode(#"{"last_assistant_message":"hi"}"#))
    }

    func testNonObjectFails() {
        XCTAssertThrowsError(try decode(#"[1,2,3]"#))
        XCTAssertThrowsError(try decode(#""just a string""#))
    }
}
