import SwiftUI

/// The settings window: one scrolling grouped form, one section per concern, no tabs.
struct SettingsView: View {
    let settings: AppSettings
    /// Flipping speaking must also silence the current clip, so the app hands in the binding it uses everywhere else.
    let speaking: Binding<Bool>
    let provider: any Provider

    var body: some View {
        Form {
            LLMSection(settings: settings)
            VoicesSection(settings: settings, provider: provider)
            BehaviourSection(settings: settings, speaking: speaking)
            AdvancedSection(settings: settings)
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
    }
}
