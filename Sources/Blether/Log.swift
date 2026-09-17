import Foundation

enum Log {
    /// One line to stderr: ISO 8601 timestamp, space, message.
    static func log(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Whitespace-collapsed head of `text`, cut with an ellipsis, for log lines.
    static func preview(_ text: String, limit: Int = 80) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
