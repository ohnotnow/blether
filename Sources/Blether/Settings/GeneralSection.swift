import KeyboardShortcuts
import SwiftUI

/// The on/off switches, the background stream, the notification languages, the global hotkeys, and remote mode.
/// Each toggle says what off does, as visible text rather than hover help, so it can be read at any text size.
struct GeneralSection: View {
    @Bindable var settings: AppSettings
    let speaking: Binding<Bool>
    /// Like speaking: switching listening off must also close an open microphone, so the app hands in its binding.
    let listening: Binding<Bool>
    /// Like speaking: switching the stream off must also stop it, so the app hands in its binding.
    let streaming: Binding<Bool>
    let streamStatus: String?
    /// The Original field of a row just added, so Add puts the cursor where the typing goes.
    @FocusState private var editingOriginal: UUID?

    var body: some View {
        Section {
            SettingToggle("Speaking", "Off drops every reply before any LLM or speech work.", isOn: speaking)
            SettingToggle("Preamble", "Off skips the in-character line before the reply.", isOn: $settings.speaksPreamble)
            SettingToggle("Reply", "Off plays only the preamble.", isOn: $settings.speaksMainReply)
            SettingToggle("Notifications", "Off ignores Claude Code's Notification events. On speaks a short in-character line when Claude is waiting for you.", isOn: $settings.speaksNotifications)
            SettingToggle("Listen after Claude replies", "On opens the microphone when a reply finishes and sends what you say to that Claude Code session. Off never opens the microphone.", isOn: listening)
        }
        Section {
            TextField("Stream URL", text: $settings.streamURL)
            SettingToggle("Play background stream", "On plays the stream and quietens it while blether speaks or listens. Off stops it.", isOn: streaming)
            if let streamStatus {
                Label(streamStatus, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Background stream")
        } footer: {
            Text("A radio stream, or a .m3u or .pls link from a station's website. Music fades down while blether speaks; a podcast episode pauses instead. A changed URL is picked up when you switch the stream off and on again.")
        }
        Section {
            TextField("Notification languages", text: $settings.notificationLanguages, axis: .vertical)
                .lineLimit(3...12)
        } footer: {
            Text("One per line, with a weight after a space, such as French 5. Higher weights are picked more often. The name is sent to the LLM as written.")
        }
        Section {
            ForEach($settings.pronunciations) { $pair in
                HStack {
                    TextField("Original", text: $pair.original)
                        .focused($editingOriginal, equals: pair.id)
                    TextField("Replacement", text: $pair.replacement)
                    Button("Delete", role: .destructive) { settings.pronunciations.removeAll { $0.id == pair.id } }
                        .accessibilityLabel("Delete the pronunciation of \(pair.original)")
                }
                .textFieldStyle(.roundedBorder)
            }
            Button("Add pronunciation") {
                let pair = Pronunciation()
                settings.pronunciations.append(pair)
                editingOriginal = pair.id
            }
        } header: {
            Text("Pronunciations")
        } footer: {
            Text("Words the voice says badly, and what to say instead: kubectl as cube-control, .env as dot-env. Whole words only, any case. The LLM still reads the original.")
        }
        Section("Shortcuts") {
            KeyboardShortcuts.Recorder("Toggle speaking:", name: .toggleSpeaking)
            KeyboardShortcuts.Recorder("Stop talking:", name: .stopTalking)
            KeyboardShortcuts.Recorder("Toggle background stream:", name: .toggleStream)
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
            SettingToggle("Log the words too", "Off logs what blether did and how long it took, never what was said. On adds, for debugging, everything that was spoken or heard in full: each preamble, reply and notification, and each transcript. The start of Claude's reply is logged too.", isOn: $settings.logsContent)
            SettingToggle("Keep recent clips", "Off keeps nothing. On keeps the last ten clips blether spoke, as files, for showing someone what it does. Never what the microphone heard.", isOn: $settings.keepsRecentClips)
            LabeledContent("Recent clips") {
                Button("Open in Finder") {
                    try? FileManager.default.createDirectory(at: RecentClips.defaultDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([RecentClips.defaultDirectory])
                }
                .accessibilityLabel("Open the recent clips folder in Finder")
            }
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
