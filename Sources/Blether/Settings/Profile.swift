/// One way a Claude sounds: a voice and persona per role. A hook picks one by name with
/// `?profile=` on its URL; the default profile speaks when none is named (blether-7qsQV).
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var roles: [Role: RoleSettings]
    /// Which provider speaks this profile (`Provider.name`). nil means the registry's default, and
    /// profiles saved before slice 5 decode with nil.
    var providerID: String?
    /// The voice each role last had under each provider, keyed by provider name, so switching
    /// ElevenLabs to Kokoro and back restores what was there (the user's ask, 2026-09-18).
    var rememberedVoices: [String: [Role: String]] = [:]

    init(id: String, name: String, roles: [Role: RoleSettings], providerID: String? = nil, rememberedVoices: [String: [Role: String]] = [:]) {
        self.id = id
        self.name = name
        self.roles = roles
        self.providerID = providerID
        self.rememberedVoices = rememberedVoices
    }

    /// Profiles saved before the memory existed decode with none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        roles = try container.decode([Role: RoleSettings].self, forKey: .roles)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        rememberedVoices = try container.decodeIfPresent([String: [Role: String]].self, forKey: .rememberedVoices) ?? [:]
    }
}
