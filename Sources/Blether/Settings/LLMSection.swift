import SwiftUI

/// Endpoint, model, the API key, and the extra request body.
struct LLMSection: View {
    @Bindable var settings: AppSettings
    /// The provider being looked at. Not the one in use: switching segments to check a model name
    /// must not change where replies go (the user, 2026-09-19). "Use this provider" does that.
    @State private var viewing: LLMProvider = .compatible

    private var isInUse: Bool { viewing == settings.llmProvider }

    var body: some View {
        Section {
            Picker("Provider", selection: $viewing) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            if viewing == .compatible {
                TextField("Base URL", text: Binding(get: { settings.llmBaseURL(for: .compatible) }, set: { settings.setLLMBaseURL($0) }))
                    .textContentType(.URL)
            }
            TextField("Model", text: Binding(get: { settings.llmModel(for: viewing) }, set: { settings.setLLMModel($0, for: viewing) }), prompt: Text(viewing.defaultModel))
            APIKeyRows(
                title: viewing.displayName,
                hasKey: settings.hasAPIKey(for: viewing.keychainAccount),
                save: { settings.setAPIKey($0, for: viewing.keychainAccount) },
                remove: { settings.setAPIKey(nil, for: viewing.keychainAccount) }
            )
            .id(viewing)
            Toggle(isOn: Binding(get: { isInUse }, set: { if $0 { settings.llmProvider = viewing } })) {
                VStack(alignment: .leading) {
                    Text("Use this provider")
                    Text(isInUse
                        ? "Replies are summarised by \(viewing.displayName) using \(settings.llmModel(for: viewing))."
                        : "Replies currently go to \(settings.llmProvider.displayName). Switch on to send them here instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isInUse)
        } footer: {
            Text(keyFootnote)
        }
        .task { viewing = settings.llmProvider }
        Section {
            TextField("Extra request body (JSON)", text: $settings.llmExtraBody, axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(3...)
            feedback
        } header: {
            Text("Advanced")
        } footer: {
            Text("Merged into every LLM request. Ollama users put {\"reasoning_effort\": \"none\"} here to stop a reasoning model spending a minute thinking about a 40-word summary.")
        }
    }

    private var keyFootnote: String {
        switch viewing {
        case .anthropic: "Through Anthropic's OpenAI-compatible endpoint. Keys stay in your macOS Keychain and are sent only to Anthropic."
        case .compatible: "Ollama, LM Studio, OpenRouter, or anything else that speaks OpenAI chat completions. Keys stay in your macOS Keychain and are sent only to the endpoint above; a local server needs none."
        case .openai, .xai, .mistral: "The same key as on the TTS Providers page; enter it once. It stays in your macOS Keychain and is sent only to \(viewing.displayName)."
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let problem = ExtraBody.problem(settings.llmExtraBody) {
            let message = "Not a JSON object: \(problem)"
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel(message)
        } else {
            Text("Valid JSON object")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
