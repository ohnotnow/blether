import SwiftUI

/// Endpoint, model and the API key. The key rows follow Naiku's settings pattern: a green
/// "saved" line with Replace and Remove once a key exists, otherwise a paste field and Save.
struct LLMSection: View {
    @Bindable var settings: AppSettings
    @State private var keyDraft = ""
    @State private var isReplacingKey = false

    var body: some View {
        Section {
            TextField("Base URL", text: $settings.llmBaseURL)
                .textContentType(.URL)
            TextField("Model", text: $settings.llmModel)
            keyRows
        } header: {
            Text("LLM")
        } footer: {
            Text("Keys stay in your macOS Keychain and are sent only to the LLM endpoint above.")
        }
        // The Settings scene has no window controller, so an unsaved draft is cleared here when the window closes.
        .onDisappear {
            keyDraft = ""
            isReplacingKey = false
        }
    }

    @ViewBuilder
    private var keyRows: some View {
        if settings.hasLLMKey, !isReplacingKey {
            HStack {
                Label("Key saved in Keychain", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Replace...") { isReplacingKey = true }
                Button("Remove", role: .destructive) { settings.llmAPIKey = nil }
            }
        } else {
            SecureField("Paste API key", text: $keyDraft)
            HStack {
                Button("Save key") {
                    settings.llmAPIKey = trimmedDraft
                    keyDraft = ""
                    isReplacingKey = false
                }
                .disabled(trimmedDraft.isEmpty)
                if isReplacingKey {
                    Button("Cancel") {
                        keyDraft = ""
                        isReplacingKey = false
                    }
                }
            }
        }
    }

    private var trimmedDraft: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
