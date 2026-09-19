import KeyboardShortcuts
import SwiftUI

/// The five toggles that exist today, the notification language list and the two global hotkeys.
/// Each toggle says what off does, as visible text rather than hover help, so it can be read at any text size.
struct BehaviourSection: View {
    @Bindable var settings: AppSettings
    let speaking: Binding<Bool>
    @State private var microphones: [AudioInputDevice] = []

    var body: some View {
        Section("Behaviour") {
            toggle("Speaking", "Off drops every reply before any LLM or speech work.", isOn: speaking)
            toggle("Preamble", "Off skips the in-character line before the reply.", isOn: $settings.speaksPreamble)
            toggle("Reply", "Off plays only the preamble.", isOn: $settings.speaksMainReply)
            toggle("Notifications", "Off ignores Claude Code's Notification events. On speaks a short in-character line when Claude is waiting for you.", isOn: $settings.speaksNotifications)
            toggle("Listen after Claude replies", "On opens the microphone when a reply finishes and sends what you say to that Claude Code session. Off never opens the microphone.", isOn: $settings.listensAfterReply)
            TextField("Notification languages", text: $settings.notificationLanguages, axis: .vertical)
                .lineLimit(3...12)
            Text("One per line, with a weight after a space, such as French 5. Higher weights are picked more often. The name is sent to the LLM as written.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Microphone", selection: $settings.microphoneID) {
                Text("System default").tag(String?.none)
                ForEach(microphones) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
                if let stored = settings.microphoneID, !microphones.contains(where: { $0.id == stored }) {
                    Text("Not connected (\(stored))").tag(String?.some(stored))
                }
            }
            .onAppear { microphones = AudioInputDevice.all() }
            Text("Used when listening after a reply. If the chosen microphone is not connected, the system default is used.")
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
