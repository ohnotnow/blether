import KeyboardShortcuts
import SwiftUI

/// The five toggles that exist today, the notification language list and the two global hotkeys.
/// Each toggle says what off does, as visible text rather than hover help, so it can be read at any text size.
struct BehaviourSection: View {
    @Bindable var settings: AppSettings
    let speaking: Binding<Bool>

    var body: some View {
        Section("Behaviour") {
            toggle("Speaking", "Off drops every reply before any LLM or speech work.", isOn: speaking)
            toggle("Preamble", "Off skips the in-character line before the reply.", isOn: $settings.speaksPreamble)
            toggle("Reply", "Off plays only the preamble.", isOn: $settings.speaksMainReply)
            toggle("Notifications", "Off ignores Claude Code's Notification events. On speaks a short in-character line when Claude is waiting for you.", isOn: $settings.speaksNotifications)
            TextField("Notification languages", text: $settings.notificationLanguages, axis: .vertical)
                .lineLimit(3...12)
            Text("One per line, with a weight after a space, such as French 5. Higher weights are picked more often. The name is sent to the LLM as written.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
