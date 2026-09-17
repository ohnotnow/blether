import Observation

@MainActor @Observable
final class AppState {
    /// Set once at launch if the hook listener could not bind; cleared only by relaunch.
    var listenerError: String?
    /// One line about the speech provider's health, shown in the menubar; nil when all is well.
    var providerStatus: String?
}
