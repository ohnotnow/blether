/// Flips the master switch. Off also kills the current clip and drops the queue, because the
/// user's reason for the switch is silence now, not after this clip. Every surface that flips
/// speaking (hotkey, menubar item, settings window) goes through here so they cannot drift apart.
@MainActor
func setSpeaking(_ on: Bool, settings: AppSettings, queue: PlaybackQueue) {
    settings.isEnabled = on
    if !on { queue.stop() }
}

/// Flips listening. Off closes an open microphone at once; on warms the model so the first reply
/// is not kept waiting. The menubar toggle, the settings window and the `handsfree` channel tool all
/// go through here (the 2026-09-20 review found the tool changed the setting and left the mic open).
@MainActor
func setListening(_ on: Bool, settings: AppSettings, ears: Ears) {
    settings.listensAfterReply = on
    if on { Task { await ears.warmUp() } } else { ears.cancel() }
}
