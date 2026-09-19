import Foundation
import Synchronization

enum Log {
    /// Whether log lines may carry what was said, heard or sent (`content(_:)`). Off by default: the
    /// process is logged either way, the words only when the person has switched it on (Settings,
    /// General). Set from AppSettings at launch and whenever the toggle changes.
    static let logsContent = Mutex(false)

    /// ~/Library/Logs/blether.log. macOS rotates nothing under Library/Logs, so `rotateIfLarge()` does.
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/blether.log")
    static let rotateAboveBytes = 5 * 1024 * 1024

    private static let file: FileHandle? = {
        // The test suite logs plenty; none of it belongs in the user's real log.
        if AppRuntime.isRunningUnitTests { return nil }
        let path = fileURL.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: path)
        _ = try? handle?.seekToEnd()
        return handle
    }()

    /// One line to stderr and to the log file: ISO 8601 timestamp, space, message.
    static func log(_ message: String) {
        let data = Data("\(Date.now.ISO8601Format()) \(message)\n".utf8)
        FileHandle.standardError.write(data)
        file?.write(data)
    }

    /// `preview` of user content, or a placeholder when content logging is off. Every log line that
    /// would show a reply, a transcript or a persona line goes through here, not `preview` directly.
    static func content(_ text: String, limit: Int = 80) -> String {
        logsContent.withLock { $0 } ? "\"\(preview(text, limit: limit))\"" : "[\(text.count) chars, content logging off]"
    }

    /// Empties the log file in place, keeping the handle. The Clear button.
    static func clear() {
        _ = try? file?.truncate(atOffset: 0)
        try? FileManager.default.removeItem(at: fileURL.appendingPathExtension("1"))
    }

    /// Whitespace-collapsed head of `text`, cut with an ellipsis, for log lines.
    static func preview(_ text: String, limit: Int = 80) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// Call once at launch, before the first `log`. Over the size limit, the file becomes blether.log.1
    /// (replacing any earlier one) and a fresh file starts. One old generation is enough to see yesterday.
    static func rotateIfLarge() {
        let manager = FileManager.default
        guard let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > rotateAboveBytes else { return }
        let previous = fileURL.appendingPathExtension("1")
        try? manager.removeItem(at: previous)
        try? manager.moveItem(at: fileURL, to: previous)
    }
}
