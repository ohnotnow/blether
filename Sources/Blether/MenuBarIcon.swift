/// The menubar symbol names, in one place so the app and its test read the same strings.
/// A speaker rather than speech bubbles because the bubbles have no slashed variant, and a
/// speaker rather than a waveform because the waveform's slash vanished among its own lines.
enum MenuBarIcon {
    static func name(enabled: Bool) -> String {
        enabled ? "speaker.wave.2" : "speaker.slash"
    }
}
