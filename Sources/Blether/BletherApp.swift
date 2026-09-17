import KeyboardShortcuts
import SwiftUI

@main
struct BletherApp: App {
    @Environment(\.openSettings) private var openSettings
    @State private var appState: AppState
    @State private var settings: AppSettings
    private let queue: PlaybackQueue
    private let pipeline: SpeechPipeline
    private let hookServer: HookServer?

    init() {
        let state = AppState()
        let settings = AppSettings()
        let queue = PlaybackQueue()
        let pipeline = SpeechPipeline(provider: AppleVoicesProvider(), queue: queue, settings: settings) { settings in
            ChatCompletionsClient(baseURL: settings.llmBaseURL, model: settings.llmModel, apiKey: settings.llmAPIKey, extraBody: settings.llmExtraBody)
        }
        var server: HookServer?
        if !AppRuntime.isRunningUnitTests {
            server = HookServer { text in
                Task { await pipeline.speak(text) }
            }
            do {
                try server?.start()
            } catch {
                Log.log("hook listener failed on port \(HookServer.defaultPort): \(error)")
                state.listenerError = "Listener failed: port \(HookServer.defaultPort) in use"
            }
            KeyboardShortcuts.onKeyUp(for: .stopTalking) {
                queue.stop()
            }
            KeyboardShortcuts.onKeyUp(for: .toggleSpeaking) {
                setSpeaking(!settings.isEnabled, settings: settings, queue: queue)
            }
        }
        _settings = State(initialValue: settings)
        self.queue = queue
        self.pipeline = pipeline
        hookServer = server
        _appState = State(initialValue: state)
    }

    /// A plain `$settings.isEnabled` cannot carry the stop side effect, hence the hand-built binding.
    private var speaking: Binding<Bool> {
        Binding(get: { settings.isEnabled }, set: { setSpeaking($0, settings: settings, queue: queue) })
    }

    var body: some Scene {
        MenuBarExtra("blether", systemImage: MenuBarIcon.name(enabled: settings.isEnabled), isInserted: .constant(!AppRuntime.isRunningUnitTests)) {
            if let error = appState.listenerError {
                Button(error) {}.disabled(true)
                Divider()
            }
            Toggle("Speaking", isOn: speaking)
            Button("Stop talking") {
                queue.stop()
            }
            Divider()
            Button("Settings...") {
                // Without activating first, the window opens behind everything under LSUIElement.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Button("Quit blether") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        Settings {
            SettingsView(settings: settings, speaking: speaking)
        }
    }
}
