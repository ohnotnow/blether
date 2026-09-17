struct RoleSettings: Codable, Hashable, Sendable {
    /// Which persona speaks in this role, or nil for none (the main role default).
    var personaID: String?
    var voiceID: String
}
