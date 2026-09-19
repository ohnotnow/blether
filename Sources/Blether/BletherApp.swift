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
    private let registry: ProviderRegistry
    private let ears: Ears

    init() {
        if !AppRuntime.isRunningUnitTests { Log.rotateIfLarge() }
        let state = AppState()
        let settings = AppSettings()
        let queue = PlaybackQueue()
        let registry = Self.makeRegistry(settings: settings, state: state)
        let ears = Self.makeEars(settings: settings, state: state)
        let pipeline = SpeechPipeline(registry: registry, queue: queue, settings: settings, ears: ears) { settings in
            ChatCompletionsClient(baseURL: settings.llmBaseURL, model: settings.llmModel, apiKey: settings.llmAPIKey, extraBody: settings.llmExtraBody)
        }
        var server: HookServer?
        if !AppRuntime.isRunningUnitTests {
            server = HookServer(allInterfaces: settings.listensOnLAN) { event, profile in
                Task {
                    switch event {
                    case .stop(let text, let session): await pipeline.speak(text, profile: profile, session: session)
                    case .notification: await pipeline.quip(profile: profile)
                    }
                }
            }
            do {
                try server?.start()
            } catch {
                Log.log("hook listener failed on port \(HookServer.defaultPort): \(error)")
                state.listenerError = "Listener failed: \(error)"
            }
            KeyboardShortcuts.onKeyUp(for: .stopTalking) {
                queue.stop()
                ears.cancel()
            }
            KeyboardShortcuts.onKeyUp(for: .toggleSpeaking) {
                setSpeaking(!settings.isEnabled, settings: settings, queue: queue)
            }
            if settings.listensAfterReply {
                Task { await ears.warmUp() }
            }
            if let kokoro = registry.provider(id: "kokoro") as? KokoroProvider {
                // Warm at launch (the user's decision, 2026-09-17) and kill on quit so no python outlives us.
                Task { await kokoro.start() }
                NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                    kokoro.stop()
                }
            }
        }
        self.registry = registry
        self.ears = ears
        _settings = State(initialValue: settings)
        self.queue = queue
        self.pipeline = pipeline
        hookServer = server
        _appState = State(initialValue: state)
    }

    /// Kokoro first, then the four API providers. Each reads its key from Keychain at call time, off
    /// the main actor, through `apiKeyReader`.
    @MainActor
    private static func makeRegistry(settings: AppSettings, state: AppState) -> ProviderRegistry {
        ProviderRegistry([
            makeKokoro(settings: settings, state: state),
            ElevenLabsProvider(apiKey: settings.apiKeyReader(for: "elevenlabs")),
            OpenAIProvider(apiKey: settings.apiKeyReader(for: "openai")),
            XAIProvider(apiKey: settings.apiKeyReader(for: "xai")),
            MistralProvider(apiKey: settings.apiKeyReader(for: "mistral")),
        ])
    }

    /// Kokoro through its bundled helper, or a stand-in that fails audibly when uv or the script is missing.
    @MainActor
    private static func makeKokoro(settings: AppSettings, state: AppState) -> any Provider {
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

    /// Off closes an open microphone at once; on warms the model so the first reply is not kept waiting.
    private var listening: Binding<Bool> {
        Binding(get: { settings.listensAfterReply }, set: { on in
            settings.listensAfterReply = on
            if on { Task { await ears.warmUp() } } else { ears.cancel() }
        })
    }

    /// Microphone, transcriber and sounds, with the status line going to the menubar. Transcripts go
    /// nowhere until the channel server (blether-UkLWZ.8.7) provides `deliver`.
    @MainActor
    private static func makeEars(settings: AppSettings, state: AppState) -> Ears {
        let transcriber = Transcriber(store: ModelStore()) { line in
            Task { @MainActor in state.listeningStatus = line }
        }
        return Ears(settings: settings, microphone: Microphone(), transcriber: transcriber, sounds: SystemSounds(),
                    status: { state.listeningStatus = $0 },
                    deliver: { text, session in Log.log("heard for \(session.id ?? "?"): \(Log.preview(text)) (no channel yet)") })
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
            if let status = appState.listeningStatus {
                Button(status) {}.disabled(true)
                Divider()
            }
            Toggle("Speaking", isOn: speaking)
            Toggle("Listening", isOn: listening)
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
            SettingsView(settings: settings, speaking: speaking, listening: listening, registry: registry)
        }
    }
}
