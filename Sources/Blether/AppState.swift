import Observation

@MainActor @Observable
final class AppState {
    /// Set once at launch if the hook listener could not bind; cleared only by relaunch.
    var listenerError: String?
    /// One line about the speech provider's health, shown in the menubar; nil when all is well.
    var providerStatus: String?
    /// The same for Breeze, which has its own helper; kept apart so neither clobbers the other's line.
    var breezeStatus: String?
    /// The same for Pocket.
    var pocketStatus: String?
    /// One line about the ears (model download, a missing microphone), shown in the menubar; nil when quiet.
    var listeningStatus: String?
    /// Set once at launch if the channel listener could not bind; cleared only by relaunch.
    var channelError: String?
}
