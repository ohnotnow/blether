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

    func persona(for role: Role) -> Persona? {
        guard let id = roles[role]?.personaID else { return nil }
        return personas.first { $0.id == id }
    }

    func voiceID(for role: Role) -> String {
        roles[role]?.voiceID ?? AppleVoicesProvider.defaultVoiceID()
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
        let voice = AppleVoicesProvider.defaultVoiceID()
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
