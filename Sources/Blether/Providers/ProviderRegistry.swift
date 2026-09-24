/// Every provider the app can speak through, keyed by `Provider.name`, built once at launch.
/// A profile names one by id; nil or an unknown id means the default, Kokoro.
final class ProviderRegistry: Sendable {
    static let defaultID = "kokoro"
    /// Providers that run on this Mac and so have no API key.
    static let localIDs: Set<String> = ["kokoro", "breeze", "pocket"]

    /// In display order.
    let all: [any Provider]

    init(_ providers: [any Provider]) {
        precondition(!providers.isEmpty, "a registry needs at least one provider")
        all = providers
    }

    func provider(id: String?) -> any Provider {
        all.first { $0.name == id } ?? all.first { $0.name == Self.defaultID } ?? all[0]
    }

    var ids: [String] { all.map(\.name) }

    /// The Keychain accounts the API providers read, in display order, each once: one key row per
    /// account on the Providers page, so an OpenRouter key is pasted once however many use it.
    var keyAccounts: [String] {
        var seen = Set<String>()
        return all.filter { !Self.localIDs.contains($0.name) }.map(\.keychainAccount).filter { seen.insert($0).inserted }
    }

    /// The user-facing name. A switch on purpose: a new provider fails to build until it is named here,
    /// and the default arm keeps test fakes displayable.
    static func displayName(id: String) -> String {
        switch id {
        case "kokoro": "Kokoro"
        case "breeze": "Breeze"
        case "pocket": "Pocket"
        case "elevenlabs": "ElevenLabs"
        case "openai": "OpenAI"
        case "xai": "xAI"
        case "mistral": "Mistral"
        case "gemini": "Gemini (OpenRouter)"
        // Not a provider: the key account every OpenRouter provider shares, titled on the Providers page.
        case "openrouter": "OpenRouter"
        default: id.capitalized
        }
    }
}
