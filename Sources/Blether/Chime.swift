import AppKit
import UniformTypeIdentifiers

/// The sound played on a hook event while speaking is off (blether-6MDjJ). The setting is a built-in
/// sound's name, or the path of the user's own file or folder; a folder is picked from at random.
protocol Chiming: Sendable {
    @MainActor func play(_ sound: String)
}

@MainActor
final class Chime: Chiming {
    nonisolated static let defaultSound = "Glass"
    nonisolated private static let systemDirectory = URL(filePath: "/System/Library/Sounds", directoryHint: .isDirectory)

    /// Held while it plays: an NSSound made from a file stops when the last reference goes.
    private var playing: NSSound?

    /// The built-in sounds by name, as this macOS ships them.
    nonisolated static func systemSounds() -> [String] {
        clips(at: systemDirectory).map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// A path is the user's own; anything else is a built-in sound's name.
    nonisolated static func isCustom(_ sound: String) -> Bool { sound.hasPrefix("/") }

    /// A file is a list of one; a folder is the audio files directly inside it. Nothing when the path has gone.
    nonisolated static func clips(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey], options: .skipsHiddenFiles)) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .audio) == true }
    }

    func play(_ sound: String) {
        playing?.stop()
        playing = Self.make(sound)
        guard let playing else {
            Log.log("chime: nothing playable at \(sound)")
            NSSound.beep()
            return
        }
        playing.play()
    }

    private static func make(_ sound: String) -> NSSound? {
        guard isCustom(sound) else { return NSSound(named: sound) }
        guard let clip = clips(at: URL(filePath: sound)).randomElement() else { return nil }
        return NSSound(contentsOf: clip, byReference: true)
    }
}
