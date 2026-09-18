/// One way a Claude sounds: a voice and persona per role. A hook picks one by name with
/// `?profile=` on its URL; the default profile speaks when none is named (blether-7qsQV).
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var roles: [Role: RoleSettings]
    /// Which provider speaks this profile (`Provider.name`). nil means the registry's default, and
    /// profiles saved before slice 5 decode with nil.
    var providerID: String?
}
