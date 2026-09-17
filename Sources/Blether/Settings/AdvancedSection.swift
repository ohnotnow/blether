import SwiftUI

/// Collapsed by default. Holds only the extra request body until something else needs a home here.
struct AdvancedSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            DisclosureGroup("Advanced") {
                TextField("Extra request body (JSON)", text: $settings.llmExtraBody, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(3...)
                feedback
                Text("Merged into every LLM request. Ollama users put {\"reasoning_effort\": \"none\"} here to stop a reasoning model spending a minute thinking about a 40-word summary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("uv path", text: $settings.uvPath)
                Text("Leave empty to look in the usual places. Takes effect at the next launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
