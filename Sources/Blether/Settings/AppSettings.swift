import Foundation
import Observation

/// Everything the user can set, backed by UserDefaults, with the LLM key in Keychain.
/// Defaults point at a local Ollama so a fresh install works with no configuration.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let llmBaseURL = "llmBaseURL"
        static let llmModel = "llmModel"
        static let llmExtraBody = "llmExtraBody"
        static let personas = "personas"
        /// Pre-profile installs stored one set of roles here. Read once to seed the Default profile, never written again.
        static let roles = "roles"
        static let profiles = "profiles"
        static let defaultProfileID = "defaultProfileID"
        static let isEnabled = "isEnabled"
        static let speaksPreamble = "speaksPreamble"
        static let speaksMainReply = "speaksMainReply"
        static let speaksNotifications = "speaksNotifications"
        static let notificationLanguages = "notificationLanguages"
        static let recentQuips = "recentQuips"
        static let uvPath = "uvPath"
        static let listensOnLAN = "listensOnLAN"
    }
    private static let llmKeyAccount = "llm"

    /// The old claude-speaks weighting (English rare, everything else 5), restricted to the languages
    /// Kokoro can pronounce with what the helper installs. Japanese is deliberately absent: its
    /// pronunciation model needs a compile step and a hand-run dictionary download (blether-Mzvjf).
    static let defaultNotificationLanguages = """
    English 1
    French 5
    Spanish 5
    Italian 5
    Portuguese 5
    Hindi 5
    Chinese (Simplified) 5
    """
    static let quipHistoryLimit = 10

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore

    /// @Observable tracks stored properties only, and everything below is computed over
    /// `defaults`. Every setter bumps this and every getter reads it, so SwiftUI re-renders.
    private var revision = 0

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    var llmBaseURL: String {
        get { _ = revision; return defaults.string(forKey: Key.llmBaseURL) ?? "http://127.0.0.1:11434/v1" }
        set { defaults.set(newValue, forKey: Key.llmBaseURL); revision += 1 }
    }

    var llmModel: String {
        get { _ = revision; return defaults.string(forKey: Key.llmModel) ?? "maternion/minicpm5:2b" }
        set { defaults.set(newValue, forKey: Key.llmModel); revision += 1 }
    }

    /// A JSON object merged into every LLM request, for endpoint-specific knobs that are not
    /// standard OpenAI. Ollama users put {"reasoning_effort": "none"} here to stop a reasoning
    /// model spending a minute thinking about a 40-word summary. Empty object by default.
    var llmExtraBody: String {
        get { _ = revision; return defaults.string(forKey: Key.llmExtraBody) ?? "{}" }
        set { defaults.set(newValue, forKey: Key.llmExtraBody); revision += 1 }
    }

    var personas: [Persona] {
        get { _ = revision; return decode(Key.personas) ?? [Persona.marvin] }
        set { encode(newValue, Key.personas); revision += 1 }
    }

    /// Never empty. An install from before profiles gets its old roles as a "Default" profile, and a
    /// profile saved before a role existed gets that role's defaults; nothing is written until a
    /// profile setter runs.
    var profiles: [Profile] {
        get { _ = revision; return (decode(Key.profiles) ?? [migratedProfile()]).map(Self.fillingMissingRoles) }
        set { encode(newValue, Key.profiles); revision += 1 }
    }

    /// Falls back to the first profile when nothing is stored or the stored id no longer exists.
    var defaultProfileID: String {
        get {
            _ = revision
            let profiles = profiles
            if let stored = defaults.string(forKey: Key.defaultProfileID), profiles.contains(where: { $0.id == stored }) { return stored }
            return profiles[0].id
        }
        set { defaults.set(newValue, forKey: Key.defaultProfileID); revision += 1 }
    }

    var defaultProfile: Profile {
        let id = defaultProfileID
        return profiles.first { $0.id == id } ?? profiles[0]
    }

    /// Case-insensitive on the trimmed name. Nil, blank or unknown gives the default profile, so a
    /// hook is never silent for want of a profile; the caller logs the fallback.
    func profile(named name: String?) -> Profile {
        let wanted = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return defaultProfile }
        return profiles.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame } ?? defaultProfile
    }

    /// The default profile's roles. A view kept so callers written before profiles keep working.
    var roles: [Role: RoleSettings] {
        get { defaultProfile.roles }
        set { updateRoles(newValue, in: defaultProfileID) }
    }

    /// Trims the name and copies the default profile's roles under a fresh id.
    @discardableResult
    func addProfile(name: String) -> Profile {
        let profile = Profile(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), roles: defaultProfile.roles)
        profiles.append(profile)
        return profile
    }

    /// Unknown id is a no-op.
    func renameProfile(id: String, name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Refuses to delete the last profile. Deleting the default hands default to the first remaining one.
    func deleteProfile(id: String) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return }
        let wasDefault = defaultProfileID == id
        profiles.removeAll { $0.id == id }
        if wasDefault { defaultProfileID = profiles[0].id }
    }

    /// Unknown profile id is a no-op. nil provider means the registry's default.
    func setProvider(id: String?, in profileID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].providerID = id
    }

    /// Unknown id is a no-op.
    func updateRoles(_ roles: [Role: RoleSettings], in profileID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].roles = roles
    }

    /// Master switch. When false a hook payload does nothing: no LLM call, no synthesis, no audio.
    var isEnabled: Bool {
        get { flag(Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled); revision += 1 }
    }

    /// Speak the in-character preamble before the reply.
    var speaksPreamble: Bool {
        get { flag(Key.speaksPreamble) }
        set { defaults.set(newValue, forKey: Key.speaksPreamble); revision += 1 }
    }

    /// Speak the reply itself (or its compressed form). Off means only the preamble is heard.
    var speaksMainReply: Bool {
        get { flag(Key.speaksMainReply) }
        set { defaults.set(newValue, forKey: Key.speaksMainReply); revision += 1 }
    }

    /// Speak a short in-character line on a Notification hook event. Off ignores those events.
    var speaksNotifications: Bool {
        get { flag(Key.speaksNotifications) }
        set { defaults.set(newValue, forKey: Key.speaksNotifications); revision += 1 }
    }

    /// The languages a notification line may be written in, one per line with an optional weight,
    /// as the user typed it. Parsed by NotificationLanguages at quip time, never here.
    var notificationLanguages: String {
        get { _ = revision; return defaults.string(forKey: Key.notificationLanguages) ?? Self.defaultNotificationLanguages }
        set { defaults.set(newValue, forKey: Key.notificationLanguages); revision += 1 }
    }

    /// The last few notification lines, oldest first, fed back to the LLM so it does not repeat itself.
    /// State rather than a preference, kept here so it shares the suite with everything else.
    private(set) var recentQuips: [String] {
        get { _ = revision; return defaults.stringArray(forKey: Key.recentQuips) ?? [] }
        set { defaults.set(newValue, forKey: Key.recentQuips); revision += 1 }
    }

    func rememberQuip(_ line: String) {
        recentQuips = Array((recentQuips + [line]).suffix(Self.quipHistoryLimit))
    }

    /// Bind the hook listener on every interface so other machines on the LAN can post replies.
    /// Off by default (loopback only) and read once at launch. Not `flag(_:)`: that defaults to true.
    var listensOnLAN: Bool {
        get { _ = revision; return defaults.bool(forKey: Key.listensOnLAN) }
        set { defaults.set(newValue, forKey: Key.listensOnLAN); revision += 1 }
    }

    /// Where `uv` lives, when it is not in one of the usual places. Empty means look for it.
    var uvPath: String {
        get { _ = revision; return defaults.string(forKey: Key.uvPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.uvPath); revision += 1 }
    }

    /// A Bool that defaults to true when unset; `bool(forKey:)` alone would default to false.
    private func flag(_ key: String) -> Bool {
        _ = revision
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    /// Trims both strings and appends under a fresh id. Nothing is assigned to a role.
    func addPersona(name: String, description: String) {
        personas.append(Persona(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }

    /// Replaces the persona with the same id. An unknown id is a no-op.
    func updatePersona(_ persona: Persona) {
        guard let index = personas.firstIndex(where: { $0.id == persona.id }) else { return }
        personas[index] = persona
    }

    /// Removes the persona; any role in any profile that used it keeps its voice and falls back to no persona.
    func deletePersona(id: String) {
        personas.removeAll { $0.id == id }
        var profiles = profiles
        for p in profiles.indices {
            for (role, var settings) in profiles[p].roles where settings.personaID == id {
                settings.personaID = nil
                profiles[p].roles[role] = settings
            }
        }
        self.profiles = profiles
    }

    /// Nil profile means the default one.
    func persona(for role: Role, in profile: Profile? = nil) -> Persona? {
        guard let id = (profile ?? defaultProfile).roles[role]?.personaID else { return nil }
        return personas.first { $0.id == id }
    }

    /// Nil profile means the default one. Voice ids from the Apple-voices scaffolding (slices 1 to 3)
    /// are not Kokoro's; fall back rather than have the helper refuse them.
    func voiceID(for role: Role, in profile: Profile? = nil) -> String {
        guard let stored = (profile ?? defaultProfile).roles[role]?.voiceID, !stored.hasPrefix("com.apple.") else { return KokoroProvider.defaultVoiceID }
        return stored
    }

    var llmAPIKey: String? {
        get {
            _ = revision
            do { return try keychain.secret(account: Self.llmKeyAccount) } catch {
                Log.log("keychain read failed: \(error)")
                return nil
            }
        }
        set {
            do {
                if let newValue { try keychain.save(newValue, account: Self.llmKeyAccount) } else { try keychain.delete(account: Self.llmKeyAccount) }
            } catch {
                Log.log("keychain write failed: \(error)")
            }
            revision += 1
        }
    }

    var hasLLMKey: Bool { llmAPIKey != nil }

    /// A speech provider's key, under a Keychain account named after the provider ("elevenlabs", "openai", ...).
    func apiKey(for provider: String) -> String? {
        _ = revision
        do { return try keychain.secret(account: provider) } catch {
            Log.log("keychain read failed for \(provider): \(error)")
            return nil
        }
    }

    /// nil removes the key.
    func setAPIKey(_ key: String?, for provider: String) {
        do {
            if let key { try keychain.save(key, account: provider) } else { try keychain.delete(account: provider) }
        } catch {
            Log.log("keychain write failed for \(provider): \(error)")
        }
        revision += 1
    }

    func hasAPIKey(for provider: String) -> Bool { apiKey(for: provider) != nil }

    /// A key reader for a provider to call from any thread at synthesis time. The Keychain is
    /// thread-safe and the value is read on each call, so a key saved in Settings is used on the next
    /// reply. Not `apiKey(for:)`: that is main-actor, and providers synthesise off it (a crash on
    /// 2026-09-18 came from asserting otherwise).
    nonisolated func apiKeyReader(for provider: String) -> @Sendable () -> String? {
        let keychain = keychain
        return {
            do { return try keychain.secret(account: provider) } catch {
                Log.log("keychain read failed for \(provider): \(error)")
                return nil
            }
        }
    }

    /// What an install from before profiles becomes: its stored roles, or the defaults, as "Default".
    private func migratedProfile() -> Profile {
        var roles = Self.defaultRoles()
        if let stored: [String: RoleSettings] = decode(Key.roles) {
            roles = [:]
            for (key, value) in stored { if let role = Role(rawValue: key) { roles[role] = value } }
        }
        return Profile(id: "default", name: "Default", roles: roles)
    }

    private static func defaultRoles() -> [Role: RoleSettings] {
        let voice = KokoroProvider.defaultVoiceID
        return [
            .main: RoleSettings(personaID: nil, voiceID: voice),
            .monologue: RoleSettings(personaID: Persona.marvin.id, voiceID: voice),
            .notification: RoleSettings(personaID: Persona.marvin.id, voiceID: voice),
        ]
    }

    /// A role added after a profile was saved (notification arrived in slice 4) starts from the defaults.
    private static func fillingMissingRoles(_ profile: Profile) -> Profile {
        var profile = profile
        profile.roles.merge(defaultRoles()) { stored, _ in stored }
        return profile
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
