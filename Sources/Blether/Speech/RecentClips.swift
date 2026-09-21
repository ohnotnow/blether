import Foundation

/// Keeps the last few clips blether spoke, as files, for showing someone what it does. The queue
/// deletes a clip once played, so this copies it first. Replies and quips only, never the microphone.
struct RecentClips: Sendable {
    static let limit = 10
    /// ~/Library/Application Support/blether/recent by default, beside the speech model and the samples.
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("blether/recent", isDirectory: true)

    let directory: URL

    init(directory: URL = RecentClips.defaultDirectory) {
        self.directory = directory
    }

    /// Copies the clip to "<date> <time> <role>.<ext>", then drops the oldest beyond the limit.
    /// The names sort by time, so the oldest is the first by name.
    func keep(_ clip: AudioClip, role: Role, now: Date = Date()) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // A preamble and a reply land in the same second, so a taken name gets a number.
        let base = "\(Self.stamp(now)) \(role.displayName.lowercased())"
        var target = directory.appendingPathComponent(base).appendingPathExtension(clip.url.pathExtension)
        var n = 1
        while manager.fileExists(atPath: target.path) {
            n += 1
            target = directory.appendingPathComponent("\(base) \(n)").appendingPathExtension(clip.url.pathExtension)
        }
        try manager.copyItem(at: clip.url, to: target)
        let kept = try manager.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".") }.sorted()
        for old in kept.dropLast(Self.limit) {
            try? manager.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}
