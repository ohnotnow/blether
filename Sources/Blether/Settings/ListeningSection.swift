import SwiftUI

/// The microphone, and the uv path. The uv path is Kokoro's, but Kokoro has no page of its own and
/// it is a local-machine setting like the microphone, so it lives here.
struct ListeningSection: View {
    @Bindable var settings: AppSettings
    @State private var microphones: [AudioInputDevice] = []

    private var seconds: String { settings.trailingSilence.formatted(.number.precision(.fractionLength(1))) + " seconds" }

    var body: some View {
        Section {
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
        } footer: {
            Text("Used when listening after a reply. If the chosen microphone is not connected, the system default is used.")
        }
        Section {
            LabeledContent("Pause before sending") {
                HStack {
                    Slider(value: $settings.trailingSilence, in: SilenceDetector.trailingSilenceRange, step: 0.5)
                        .accessibilityLabel("Pause before sending")
                        .accessibilityValue(seconds)
                    Text(seconds)
                        .monospacedDigit()
                }
            }
        } footer: {
            Text("How long you can go quiet before blether sends what it heard. Longer if you like to pause while you think, shorter for quick off-the-cuff replies. Arrow keys move it by half a second.")
        }
        Section {
            TextField("Heard words", text: $settings.heardWords)
        } footer: {
            Text("Words the transcriber keeps getting wrong, separated by spaces or commas, such as laravel, livewire, CVE. Anything it hears that is close enough is spelled this way before it is sent. Short words match too easily, so leave them out.")
        }
        Section {
            TextField("uv path", text: $settings.uvPath)
            RestartButton()
        } header: {
            Text("Kokoro")
        } footer: {
            Text("Leave empty to look in the usual places. Takes effect after a restart; use the button above.")
        }
    }
}
