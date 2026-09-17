/// Flips the master switch. Off also kills the current clip and drops the queue, because the
/// user's reason for the switch is silence now, not after this clip. Every surface that flips
/// speaking (hotkey, menubar item, settings window) goes through here so they cannot drift apart.
@MainActor
func setSpeaking(_ on: Bool, settings: AppSettings, queue: PlaybackQueue) {
    settings.isEnabled = on
    if !on { queue.stop() }
}
