import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Kill the current clip and drop the queue. No default; inert until the user records one.
    @MainActor static let stopTalking = Self("stopTalking")
    /// Flip the master switch. No default; inert until the user records one.
    @MainActor static let toggleSpeaking = Self("toggleSpeaking")
    /// Flip the background stream. No default; inert until the user records one.
    @MainActor static let toggleStream = Self("toggleStream")
}
