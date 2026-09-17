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
        static let roles = "roles"
        static let isEnabled = "isEnabled"
        static let speaksPreamble = "speaksPreamble"
        static let speaksMainReply = "speaksMainReply"
        static let uvPath = "uvPath"
    }
    private static let llmKeyAccount = "llm"

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

    var roles: [Role: RoleSettings] {
        get {
            _ = revision
            if let stored: [String: RoleSettings] = decode(Key.roles) {
                var result: [Role: RoleSettings] = [:]
                for (key, value) in stored { if let role = Role(rawValue: key) { result[role] = value } }
                return result
            }
            return Self.defaultRoles()
        }
        set {
            encode(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) }), Key.roles)
            revision += 1
        }
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

    /// Removes the persona; any role that used it keeps its voice and falls back to no persona.
    func deletePersona(id: String) {
        personas.removeAll { $0.id == id }
        var roles = roles
        for (role, var settings) in roles where settings.personaID == id {
            settings.personaID = nil
            roles[role] = settings
        }
        self.roles = roles
    }

    func persona(for role: Role) -> Persona? {
        guard let id = roles[role]?.personaID else { return nil }
        return personas.first { $0.id == id }
    }

    /// Voice ids from the Apple-voices scaffolding (slices 1 to 3) are not Kokoro's; fall back rather than have the helper refuse them.
    func voiceID(for role: Role) -> String {
        guard let stored = roles[role]?.voiceID, !stored.hasPrefix("com.apple.") else { return KokoroProvider.defaultVoiceID }
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

    private static func defaultRoles() -> [Role: RoleSettings] {
        let voice = KokoroProvider.defaultVoiceID
        return [
            .main: RoleSettings(personaID: nil, voiceID: voice),
            .monologue: RoleSettings(personaID: Persona.marvin.id, voiceID: voice),
        ]
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
