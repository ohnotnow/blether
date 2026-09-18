/// The three speech roles from claude-speaks. Declared in the order they are heard, which is the
/// order the settings window lists them; a notification is heard on its own, so it comes last.
/// CodingKeyRepresentable makes a `[Role: X]` dictionary encode as a JSON object rather than a flat array.
enum Role: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case monologue
    case main
    case notification

    /// The user-facing name. A switch on purpose: a new role fails to build until it is named here.
    var displayName: String {
        switch self {
        case .monologue: "Preamble"
        case .main: "Reply"
        case .notification: "Notification"
        }
    }
}
