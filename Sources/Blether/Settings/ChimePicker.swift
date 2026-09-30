import SwiftUI
import UniformTypeIdentifiers

/// The sound played while speaking is off: a built-in sound, or the user's own file or folder (blether-6MDjJ).
struct ChimePicker: View {
    @Bindable var settings: AppSettings
    @State private var chime = Chime()
    private let systemSounds = Chime.systemSounds()

    /// A folder says so, since it plays a different clip each time.
    private var customLabel: String {
        let url = URL(filePath: settings.chimeSound)
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? "\(url.lastPathComponent) (folder, at random)"
            : url.lastPathComponent
    }

    var body: some View {
        LabeledContent("Sound") {
            HStack {
                Picker("Sound", selection: $settings.chimeSound) {
                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                    if Chime.isCustom(settings.chimeSound) {
                        Divider()
                        Text(customLabel).tag(settings.chimeSound)
                    }
                }
                .labelsHidden()
                Button("Choose file or folder…", action: choose)
                Button("Play") { chime.play(settings.chimeSound) }
                    .accessibilityLabel("Play the sound")
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        // .folder too: with .audio alone the panel greys out folders even though canChooseDirectories is on.
        panel.allowedContentTypes = [.audio, .folder]
        panel.message = "Choose one sound, or a folder of sounds to pick from at random."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.chimeSound = url.path
    }
}
