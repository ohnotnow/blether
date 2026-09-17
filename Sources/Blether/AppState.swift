import Observation

@MainActor @Observable
final class AppState {
    /// Set once at launch if the hook listener could not bind; cleared only by relaunch.
    var listenerError: String?
}
