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
    private let provider: any Provider

    init() {
        if !AppRuntime.isRunningUnitTests { Log.rotateIfLarge() }
        let state = AppState()
        let settings = AppSettings()
        let queue = PlaybackQueue()
        let provider = Self.makeProvider(settings: settings, state: state)
        let pipeline = SpeechPipeline(provider: provider, queue: queue, settings: settings) { settings in
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
            if let kokoro = provider as? KokoroProvider {
                // Warm at launch (the user's decision, 2026-09-17) and kill on quit so no python outlives us.
                Task { await kokoro.start() }
                NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                    kokoro.stop()
                }
            }
        }
        self.provider = provider
        _settings = State(initialValue: settings)
        self.queue = queue
        self.pipeline = pipeline
        hookServer = server
        _appState = State(initialValue: state)
    }

    /// Kokoro through its bundled helper, or a stand-in that fails audibly when uv or the script is missing.
    @MainActor
    private static func makeProvider(settings: AppSettings, state: AppState) -> any Provider {
        guard let script = Bundle.main.url(forResource: "kokoro", withExtension: "py") else {
            state.providerStatus = "Kokoro: helper script missing from the app bundle"
            return UnavailableProvider(reason: "helper script missing")
        }
        guard let uv = UVLocator.find(override: settings.uvPath) else {
            state.providerStatus = "Kokoro: uv not found, set its path in Settings > Advanced"
            return UnavailableProvider(reason: "uv not found")
        }
        return KokoroProvider(executable: uv, arguments: ["run", script.path]) { newState in
            Task { @MainActor in
                switch newState {
                case .starting: state.providerStatus = "Kokoro: warming up"
                case .ready: state.providerStatus = nil
                case .failed(let message): state.providerStatus = "Kokoro: \(message)"
                }
            }
        }
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
            if let status = appState.providerStatus {
                Button(status) {}.disabled(true)
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
            SettingsView(settings: settings, speaking: speaking, provider: provider)
        }
    }
}
