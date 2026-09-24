import SwiftUI

/// Who decides a reply's mood, and the Jev key when Jev does.
struct ToneSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Picker("Tone", selection: $settings.toneSource) {
                ForEach(ToneSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            Text("Classifies each reply's mood so Mistral, OpenAI and Gemini voices can match it: perky when the tests pass, sheepish when they do not. Jev is a small model built for this and costs almost nothing; your LLM works too but adds a second call per reply.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if settings.toneSource == .jev {
                APIKeyRows(title: "Jev", hasKey: settings.hasAPIKey(for: "jev"), save: { settings.setAPIKey($0, for: "jev") }, remove: { settings.setAPIKey(nil, for: "jev") })
            }
        } header: {
            Text("Tone")
        }
    }
}
