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
    private let channelServer: ChannelServer?
    private let registry: ProviderRegistry
    private let ears: Ears
    private let stream: BackgroundStream
    private let ducker: StreamDucker

    init() {
        if !AppRuntime.isRunningUnitTests { Log.rotateIfLarge() }
        let state = AppState()
        let settings = AppSettings()
        Log.logsContent.withLock { $0 = settings.logsContent }
        let queue = PlaybackQueue()
        let registry = Self.makeRegistry(settings: settings, state: state)
        let ears = Self.makeEars(settings: settings, state: state)
        let channel = ChannelServer(handsfree: { action, reply in
            Task { @MainActor in reply(Self.handsfree(action, settings: settings, state: state, ears: ears)) }
        }, heardWords: { action, words, reply in
            Task { @MainActor in reply(HeardWordsTool.run(action, words: words, settings: settings)) }
        })
        ears.deliver = Self.deliverer(channel: channel, state: state)
        let activity = SpeechActivity()
        // A status line means nothing in the list would play, so the switch goes back off to match.
        let stream = BackgroundStream(status: { status in
            state.streamStatus = status
            if status != nil { settings.playsStream = false }
        })
        let ducker = StreamDucker(stream: stream) { activity.inFlight > 0 || queue.isPlaying || ears.isListening }
        let pipeline = SpeechPipeline(registry: registry, queue: queue, settings: settings, ears: ears, activity: activity) { settings in
            let client = ChatCompletionsClient(baseURL: settings.llmBaseURL, model: settings.llmModel, apiKey: settings.llmAPIKey, extraBody: settings.llmExtraBody)
            guard !settings.llmHasAnswered else { return client }
            return FirstAnswerLLM(wrapped: client) { Task { @MainActor in settings.llmHasAnswered = true } }
        }
        var server: HookServer?
        var channelServer: ChannelServer?
        if !AppRuntime.isRunningUnitTests {
            do {
                try channel.start()
                channelServer = channel
            } catch {
                Log.log("channel listener failed on port \(ChannelServer.defaultPort): \(error)")
                state.channelError = "Channel failed: \(error)"
            }
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
            // Stop while listening closes the mic; stop while talking skips to listening (the queue arms).
            KeyboardShortcuts.onKeyUp(for: .stopTalking) {
                if ears.isListening { ears.cancel() } else { queue.stop() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleSpeaking) {
                setSpeaking(!settings.isEnabled, settings: settings, queue: queue)
            }
            KeyboardShortcuts.onKeyUp(for: .toggleStream) {
                setStreaming(!settings.playsStream, settings: settings, stream: stream, state: state)
            }
            ducker.start()
            if settings.playsStream {
                setStreaming(true, settings: settings, stream: stream, state: state)
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
            if let breeze = registry.provider(id: "breeze") as? BreezeProvider {
                // Only warm at launch if a profile speaks with it: the model is 2.3 GB. Otherwise the
                // first Breeze clip starts it (blether-FGSKN).
                if settings.profiles.contains(where: { $0.providerID == "breeze" }) {
                    Task { await breeze.start() }
                }
                NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                    breeze.stop()
                }
            }
            if let pocket = registry.provider(id: "pocket") as? PocketProvider {
                // Like Breeze: warm at launch only if a profile speaks with it, else on first use.
                if settings.profiles.contains(where: { $0.providerID == "pocket" }) {
                    Task { await pocket.start() }
                }
                NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                    pocket.stop()
                }
            }
        }
        self.registry = registry
        self.ears = ears
        self.stream = stream
        self.ducker = ducker
        _settings = State(initialValue: settings)
        self.queue = queue
        self.pipeline = pipeline
        hookServer = server
        self.channelServer = channelServer
        _appState = State(initialValue: state)
    }

    /// The three local providers first, then the five API providers. Each reads its key from Keychain at call time, off
    /// the main actor, through `apiKeyReader`.
    @MainActor
    private static func makeRegistry(settings: AppSettings, state: AppState) -> ProviderRegistry {
        ProviderRegistry([
            makeKokoro(settings: settings, state: state),
            makeBreeze(settings: settings, state: state),
            makePocket(settings: settings, state: state),
            ElevenLabsProvider(apiKey: settings.apiKeyReader(for: "elevenlabs")),
            OpenAIProvider(apiKey: settings.apiKeyReader(for: "openai")),
            XAIProvider(apiKey: settings.apiKeyReader(for: "xai")),
            MistralProvider(apiKey: settings.apiKeyReader(for: "mistral")),
            GeminiProvider(apiKey: settings.apiKeyReader(for: "openrouter")),
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

    /// Breeze through its bundled helper, or a stand-in that fails audibly when uv or the script is missing.
    @MainActor
    private static func makeBreeze(settings: AppSettings, state: AppState) -> any Provider {
        guard let script = Bundle.main.url(forResource: "breeze", withExtension: "py") else {
            state.breezeStatus = "Breeze: helper script missing from the app bundle"
            return UnavailableProvider(name: "breeze", reason: "helper script missing")
        }
        guard let uv = UVLocator.find(override: settings.uvPath) else {
            state.breezeStatus = "Breeze: uv not found, set its path in Settings > Advanced"
            return UnavailableProvider(name: "breeze", reason: "uv not found")
        }
        return BreezeProvider(executable: uv, arguments: ["run", script.path], settings: settings.breezeReader()) { newState in
            Task { @MainActor in
                switch newState {
                case .starting: state.breezeStatus = "Breeze: warming up"
                case .ready: state.breezeStatus = nil
                case .failed(let message): state.breezeStatus = "Breeze: \(message)"
                }
            }
        }
    }

    /// Pocket through its bundled helper, or a stand-in that fails audibly when uv or the script is missing.
    @MainActor
    private static func makePocket(settings: AppSettings, state: AppState) -> any Provider {
        guard let script = Bundle.main.url(forResource: "pocket", withExtension: "py") else {
            state.pocketStatus = "Pocket: helper script missing from the app bundle"
            return UnavailableProvider(name: "pocket", reason: "helper script missing")
        }
        guard let uv = UVLocator.find(override: settings.uvPath) else {
            state.pocketStatus = "Pocket: uv not found, set its path in Settings > Advanced"
            return UnavailableProvider(name: "pocket", reason: "uv not found")
        }
        return PocketProvider(executable: uv, arguments: ["run", script.path, PocketVoices.defaultDirectory.path]) { newState in
            Task { @MainActor in
                switch newState {
                case .starting: state.pocketStatus = "Pocket: warming up"
                case .ready: state.pocketStatus = nil
                case .failed(let message): state.pocketStatus = "Pocket: \(message)"
                }
            }
        }
    }

    /// A plain `$settings.isEnabled` cannot carry the stop side effect, hence the hand-built binding.
    private var speaking: Binding<Bool> {
        Binding(get: { settings.isEnabled }, set: { setSpeaking($0, settings: settings, queue: queue) })
    }

    /// Same switch as the `handsfree` tool: see `setListening`.
    private var listening: Binding<Bool> {
        Binding(get: { settings.listensAfterReply }, set: { setListening($0, settings: settings, ears: ears) })
    }

    /// Off stops the stream at once; on reads the URL afresh. See `setStreaming`.
    private var streaming: Binding<Bool> {
        Binding(get: { settings.playsStream }, set: { setStreaming($0, settings: settings, stream: stream, state: appState) })
    }

    /// Microphone, transcriber and sounds, with the status line going to the menubar. Where a transcript
    /// goes is set afterwards (`deliverer`), once the channel server exists.
    @MainActor
    private static func makeEars(settings: AppSettings, state: AppState) -> Ears {
        let transcriber = Transcriber(store: ModelStore()) { line in
            Task { @MainActor in state.listeningStatus = line }
        }
        return Ears(settings: settings, microphone: Microphone(), transcriber: transcriber, sounds: SystemSounds(),
                    status: { state.listeningStatus = $0 },
                    deliver: { _, _ in })
    }

    /// A transcript goes down the channel to the session that armed the mic; if that session has no
    /// channel, it is said, not lost.
    @MainActor
    private static func deliverer(channel: ChannelServer, state: AppState) -> @MainActor (String, SessionKey) -> Void {
        { text, session in
            if !channel.deliver(text, to: session) {
                Log.log("heard \(Log.content(text)) but session \(session.id ?? "?") has no channel; is it running with the channel flag?")
                state.listeningStatus = "Heard you, but that session has no channel"
                SystemSounds().play(.cancelled)
            }
        }
    }

    /// The `handsfree` tool Claude can call from a session: the same switch as the toggles.
    @MainActor
    private static func handsfree(_ action: String, settings: AppSettings, state: AppState, ears: Ears) -> String {
        switch action {
        case "on": setListening(true, settings: settings, ears: ears)
        case "off": setListening(false, settings: settings, ears: ears)
        default: break
        }
        let ears = settings.listensAfterReply ? "Listening after replies is on." : "Listening after replies is off."
        let model = ModelStore().isPresent ? "" : " The speech model is not downloaded yet; the first listen will fetch it (218 MB)."
        let status = state.listeningStatus.map { " Status: \($0)." } ?? ""
        return ears + model + status
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!AppRuntime.isRunningUnitTests)) {
            // Above the switches, unlike the status lines below Quit: it goes away once, on the first
            // answered reply, never while the menu is open.
            if !settings.llmHasAnswered {
                Button("No LLM has answered yet, so replies are read raw. Pick one in Settings, LLM.") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Divider()
            }
            // Shows the recorded hotkeys beside the items; the hotkeys themselves are the onKeyUp handlers.
            Toggle("Speaking", isOn: speaking)
                .globalKeyboardShortcut(.toggleSpeaking)
            Toggle("Listening", isOn: listening)
            Toggle("Background stream", isOn: streaming)
                .globalKeyboardShortcut(.toggleStream)
            // "Default profile", not "Profile": blether has no current profile. A hook that names one
            // with ?profile= still gets that one; this changes only what an unnamed hook gets
            // (decided with the user 2026-09-19, ant blether-bREz9).
            if settings.profiles.count > 1 {
                Picker("Default profile", selection: Binding(get: { settings.defaultProfileID }, set: { settings.defaultProfileID = $0 })) {
                    ForEach(settings.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
            }
            Button("Stop talking") {
                if ears.isListening { ears.cancel() } else { queue.stop() }
            }
            .globalKeyboardShortcut(.stopTalking)
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
            // Status lines live below Quit, in a dead-end after a divider, so a line vanishing (Kokoro
            // warming up, say) cannot shift the items above it under a moving mouse. The user clicked
            // Quit instead of Settings twice that way (2026-09-19).
            let status = [appState.listenerError, appState.providerStatus, appState.breezeStatus, appState.pocketStatus, appState.listeningStatus, appState.channelError, appState.streamStatus].compactMap { $0 }
            if !status.isEmpty {
                Divider()
                ForEach(status, id: \.self) { line in
                    Button(line) {}.disabled(true)
                }
            }
        } label: {
            Image(nsImage: MenuBarIcon.image(enabled: settings.isEnabled))
        }
        Settings {
            SettingsView(settings: settings, speaking: speaking, listening: listening, streaming: streaming, streamStatus: appState.streamStatus, registry: registry)
        }
    }
}
