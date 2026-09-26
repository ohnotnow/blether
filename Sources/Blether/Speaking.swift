import Foundation

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

/// Flips the background stream. On reads the URL now, follows a .m3u or .pls, and plays; off stops.
/// The menubar item, the hotkey, the settings window and launch all go through here. Returns the
/// resolving task so tests can wait for it.
@MainActor @discardableResult
func setStreaming(_ on: Bool, settings: AppSettings, stream: BackgroundStream, state: AppState,
                  fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) -> Task<Void, Never>? {
    state.streamStatus = nil
    guard on else {
        settings.playsStream = false
        stream.stop()
        return nil
    }
    let text = settings.streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else {
        settings.playsStream = false
        state.streamStatus = text.isEmpty ? "Stream: add a stream URL in Settings, General" : "Stream: the URL must start with http:// or https://"
        return nil
    }
    settings.playsStream = true
    return Task {
        do {
            let urls = try await StreamPlaylist.resolve(url, fetch: fetch)
            // Switched off while the playlist was being fetched: off wins.
            guard settings.playsStream else { return }
            stream.start(urls: urls)
        } catch {
            Log.log("stream: could not read \(url.absoluteString): \(error)")
            settings.playsStream = false
            state.streamStatus = "Stream: could not reach \(url.host() ?? "the playlist"): \(error.localizedDescription)"
        }
    }
}
