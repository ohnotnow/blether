import SwiftUI

/// The pages down the sidebar, in order. Decided with the user on 2026-09-19 (ant blether-bREz9):
/// one page per concern rather than one long form, so a section fits the window without scrolling.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, profiles, personas, providers, llm, listening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .personas: "Personas"
        case .providers: "TTS Providers"
        case .llm: "LLM"
        case .listening: "Listening"
        }
    }
}

/// The settings window: a sidebar of pages and the chosen page's grouped form.
struct SettingsView: View {
    let settings: AppSettings
    /// Flipping speaking must also silence the current clip, so the app hands in the binding it uses everywhere else.
    let speaking: Binding<Bool>
    let listening: Binding<Bool>
    let registry: ProviderRegistry
    /// Remembered for the window's life only.
    @State private var page: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { page in
                // One unconditional row per page: an if/else here loses the row's selection tag (seen
                // 2026-09-19, the LLM row stopped responding). The badge draws the eye on a fresh
                // install, whose default LLM is a local Ollama most Macs lack.
                Text(page.title)
                    .badge(page == .llm && !settings.llmHasAnswered ? Text("Set up") : nil)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            Form {
                switch page ?? .general {
                case .general: GeneralSection(settings: settings, speaking: speaking, listening: listening)
                case .profiles: VoicesSection(settings: settings, registry: registry)
                case .personas: PersonasSection(settings: settings)
                case .providers:
                    ProvidersSection(settings: settings, registry: registry)
                    BreezeSection(settings: settings)
                case .llm:
                    LLMSection(settings: settings)
                    ToneSection(settings: settings)
                case .listening: ListeningSection(settings: settings)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((page ?? .general).title)
        }
        .frame(minWidth: 640, minHeight: 440)
        .frame(idealWidth: 720, idealHeight: 520)
    }
}
