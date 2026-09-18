/// Every provider the app can speak through, keyed by `Provider.name`, built once at launch.
/// A profile names one by id; nil or an unknown id means the default, Kokoro.
final class ProviderRegistry: Sendable {
    static let defaultID = "kokoro"

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

    /// The user-facing name. A switch on purpose: a new provider fails to build until it is named here,
    /// and the default arm keeps test fakes displayable.
    static func displayName(id: String) -> String {
        switch id {
        case "kokoro": "Kokoro"
        case "elevenlabs": "ElevenLabs"
        case "openai": "OpenAI"
        case "xai": "xAI"
        case "mistral": "Mistral"
        default: id.capitalized
        }
    }
}
