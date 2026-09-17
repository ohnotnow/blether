import KeyboardShortcuts
import SwiftUI

/// The four toggles that exist today and the two global hotkeys. Each toggle says what off does,
/// as visible text rather than hover help, so it can be read at any text size.
struct BehaviourSection: View {
    @Bindable var settings: AppSettings
    let speaking: Binding<Bool>

    var body: some View {
        Section("Behaviour") {
            toggle("Speaking", "Off drops every reply before any LLM or speech work.", isOn: speaking)
            toggle("Preamble", "Off skips the in-character line before the reply.", isOn: $settings.speaksPreamble)
            toggle("Reply", "Off plays only the preamble.", isOn: $settings.speaksMainReply)
            toggle("Listen on the network", "On lets other machines on your network post replies here. Anyone on that network can make this Mac speak. Takes effect at the next launch.", isOn: $settings.listensOnLAN)
            KeyboardShortcuts.Recorder("Toggle speaking:", name: .toggleSpeaking)
            KeyboardShortcuts.Recorder("Stop talking:", name: .stopTalking)
        }
    }

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
