import SwiftUI

/// Endpoint, model and the API key.
struct LLMSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            TextField("Base URL", text: $settings.llmBaseURL)
                .textContentType(.URL)
            TextField("Model", text: $settings.llmModel)
            APIKeyRows(title: "LLM", hasKey: settings.hasLLMKey, save: { settings.llmAPIKey = $0 }, remove: { settings.llmAPIKey = nil })
        } header: {
            Text("LLM")
        } footer: {
            Text("Keys stay in your macOS Keychain and are sent only to the LLM endpoint above.")
        }
    }
}
