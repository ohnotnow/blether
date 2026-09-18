import SwiftUI

/// The key rows every service shares: a green "saved" line with Replace and Remove once a key exists,
/// otherwise a paste field and Save. Used by the LLM section and once per API provider.
struct APIKeyRows: View {
    let title: String
    let hasKey: Bool
    let save: (String) -> Void
    let remove: () -> Void
    @State private var keyDraft = ""
    @State private var isReplacingKey = false

    var body: some View {
        Group {
            if hasKey, !isReplacingKey {
                HStack {
                    Label("\(title) key saved in Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Replace...") { isReplacingKey = true }
                        .accessibilityLabel("Replace \(title) key")
                    Button("Remove", role: .destructive) { remove() }
                        .accessibilityLabel("Remove \(title) key")
                }
            } else {
                SecureField("Paste \(title) API key", text: $keyDraft)
                HStack {
                    Button("Save key") {
                        save(trimmedDraft)
                        keyDraft = ""
                        isReplacingKey = false
                    }
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel("Save \(title) key")
                    if isReplacingKey {
                        Button("Cancel") {
                            keyDraft = ""
                            isReplacingKey = false
                        }
                        .accessibilityLabel("Cancel replacing \(title) key")
                    }
                }
            }
        }
        // The Settings scene has no window controller, so an unsaved draft is cleared here when the window closes.
        .onDisappear {
            keyDraft = ""
            isReplacingKey = false
        }
    }

    private var trimmedDraft: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
