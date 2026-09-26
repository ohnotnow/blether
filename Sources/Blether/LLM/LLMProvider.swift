/// Where the LLM lives. The four named ones speak OpenAI chat completions at a known address
/// (Anthropic through its OpenAI-compatible layer), so one client serves them all; `compatible` is
/// the typed base URL for Ollama, LM Studio, OpenRouter and the like. The user's ask, 2026-09-19.
enum LLMProvider: String, CaseIterable, Sendable {
    case anthropic, openai, xai, mistral, compatible

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .xai: "xAI"
        case .mistral: "Mistral"
        case .compatible: "OpenAI compatible"
        }
    }

    /// nil for `compatible`, whose base URL is typed.
    var baseURL: String? {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .xai: "https://api.x.ai/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .compatible: nil
        }
    }

    /// The models the user picked on 2026-09-19 as the useful ones for a 40-word summary.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openai: "gpt-5.6-luna"
        case .xai: "grok-4.6"
        case .mistral: "mistral-small-2603"
        case .compatible: "maternion/minicpm5:2b"
        }
    }

    /// The Keychain account the key lives under. OpenAI, xAI and Mistral share theirs with the
    /// speech provider of the same name (`AppSettings.apiKey(for:)`), so a key is entered once.
    var keychainAccount: String {
        switch self {
        case .anthropic: "anthropic"
        case .openai, .xai, .mistral: rawValue
        case .compatible: "llm"
        }
    }

    /// On 2026-09-26 OpenAI answered 400 "Unsupported parameter: 'max_tokens' ... Use
    /// 'max_completion_tokens' instead" for gpt-5.6-luna and gpt-6-luna. The others keep the older
    /// name, which Ollama is known to accept; whether they take the new one was not checked.
    var maxTokensField: String { self == .openai ? "max_completion_tokens" : "max_tokens" }

    var sharesKeyWithSpeech: Bool {
        switch self {
        case .openai, .xai, .mistral: true
        case .anthropic, .compatible: false
        }
    }
}
