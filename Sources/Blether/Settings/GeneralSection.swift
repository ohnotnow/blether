import KeyboardShortcuts
import SwiftUI

/// The on/off switches, the notification languages, the two global hotkeys, and remote mode.
/// Each toggle says what off does, as visible text rather than hover help, so it can be read at any text size.
struct GeneralSection: View {
    @Bindable var settings: AppSettings
    let speaking: Binding<Bool>
    /// Like speaking: switching listening off must also close an open microphone, so the app hands in its binding.
    let listening: Binding<Bool>

    var body: some View {
        Section {
            SettingToggle("Speaking", "Off drops every reply before any LLM or speech work.", isOn: speaking)
            SettingToggle("Preamble", "Off skips the in-character line before the reply.", isOn: $settings.speaksPreamble)
            SettingToggle("Reply", "Off plays only the preamble.", isOn: $settings.speaksMainReply)
            SettingToggle("Notifications", "Off ignores Claude Code's Notification events. On speaks a short in-character line when Claude is waiting for you.", isOn: $settings.speaksNotifications)
            SettingToggle("Listen after Claude replies", "On opens the microphone when a reply finishes and sends what you say to that Claude Code session. Off never opens the microphone.", isOn: listening)
        }
        Section {
            TextField("Notification languages", text: $settings.notificationLanguages, axis: .vertical)
                .lineLimit(3...12)
        } footer: {
            Text("One per line, with a weight after a space, such as French 5. Higher weights are picked more often. The name is sent to the LLM as written.")
        }
        Section("Shortcuts") {
            KeyboardShortcuts.Recorder("Toggle speaking:", name: .toggleSpeaking)
            KeyboardShortcuts.Recorder("Stop talking:", name: .stopTalking)
        }
        Section("Remote") {
            SettingToggle("Listen on the network", "On lets other machines on your network post replies here. Anyone on that network can make this Mac speak. Takes effect after a restart; use the button below.", isOn: $settings.listensOnLAN)
            RestartButton()
        }
        Section {
            LabeledContent("Log file") {
                HStack {
                    Text(Log.fileURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .textSelection(.enabled)
                    Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                    Button("Clear") { Log.clear() }
                        .accessibilityLabel("Clear the log")
                }
            }
            SettingToggle("Log the words too", "Off logs what blether did and how long it took, never what was said. On adds the first line of each reply, preamble and transcript, for debugging.", isOn: $settings.logsContent)
        } header: {
            Text("Log")
        } footer: {
            Text("blether logs its internal processes here.")
        }
    }
}

/// A toggle whose title carries a one-line explanation of what off does.
struct SettingToggle: View {
    let title: String
    let detail: String
    let isOn: Binding<Bool>

    init(_ title: String, _ detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
    }

    var body: some View {
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
