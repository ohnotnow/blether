/// The three speech roles from claude-speaks; notification arrives in slice 4.
/// Declared in the order they are heard, which is the order the settings window lists them.
enum Role: String, CaseIterable, Codable, Sendable {
    case monologue
    case main

    /// The user-facing name. A switch on purpose: a new role fails to build until it is named here.
    var displayName: String {
        switch self {
        case .monologue: "Preamble"
        case .main: "Reply"
        }
    }
}
