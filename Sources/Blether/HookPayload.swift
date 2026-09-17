import Foundation

/// The Claude Code hook payload, as posted to /hook. Unknown keys are ignored.
struct HookPayload: Decodable {
    let hookEventName: String
    let lastAssistantMessage: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case lastAssistantMessage = "last_assistant_message"
        case sessionId = "session_id"
    }
}
