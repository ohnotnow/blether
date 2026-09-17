import KeyboardShortcuts
import SwiftUI

@main
struct BletherApp: App {
    @Environment(\.openSettings) private var openSettings
    @State private var appState: AppState
    private let settings: AppSettings
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
        }
        self.settings = settings
        self.queue = queue
        self.pipeline = pipeline
        hookServer = server
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra("blether", systemImage: "bubble.left.and.bubble.right", isInserted: .constant(!AppRuntime.isRunningUnitTests)) {
            if let error = appState.listenerError {
                Button(error) {}.disabled(true)
                Divider()
            }
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
            Form {
                KeyboardShortcuts.Recorder("Stop talking:", name: .stopTalking)
            }
            .padding()
            .frame(width: 360)
        }
    }
}
