/// The three speech roles from claude-speaks; notification arrives in slice 4.
enum Role: String, CaseIterable, Codable, Sendable {
    case main
    case monologue
}
