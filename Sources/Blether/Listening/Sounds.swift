import AppKit

/// The three cues the old loop had: a tick when the mic opens, a pop when it sends, a thud when it gives up.
enum SoundCue: String, Sendable {
    case armed = "Tink"
    case sent = "Pop"
    case cancelled = "Basso"
}

protocol Sounds: Sendable {
    @MainActor func play(_ cue: SoundCue)
}

struct SystemSounds: Sounds {
    @MainActor func play(_ cue: SoundCue) {
        guard let sound = NSSound(named: cue.rawValue) else {
            NSSound.beep()
            return
        }
        sound.play()
    }
}
