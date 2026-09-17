import Foundation

enum SpeechText {
    /// Flatten markdown so a voice does not read asterisks and backticks aloud.
    /// A straight port of strip_markdown in claude-speaks' text_util.py; crude on purpose.
    static func stripMarkdown(_ text: String) -> String {
        var s = text
        s = replace(s, #"```[\s\S]*?```"#, with: "")
        s = replace(s, #"\[([^\]]+)\]\([^)]+\)"#, with: "$1")
        s = replace(s, #"`([^`]+)`"#, with: "$1")
        s = replace(s, #"^#{1,6}\s+"#, with: "", options: .anchorsMatchLines)
        s = replace(s, #"^\s*[-*]\s+"#, with: "", options: .anchorsMatchLines)
        s = replace(s, #"^\s*\d+\.\s+"#, with: "", options: .anchorsMatchLines)
        s = s.replacingOccurrences(of: "*", with: "")
        s = replace(s, #"\n{3,}"#, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Last-resort length bound before synthesis. Cuts at the last space under the limit and
    /// marks the cut with an ellipsis. Port of cap_length in claude-speaks' text_util.py.
    static func cap(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut + "…"
    }

    /// First non-blank line, trimmed. Some models answer the reply instead of writing the
    /// one-line quip asked for; the babble is multi-line and its first line is usually usable.
    static func firstLine(_ text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func replace(_ text: String, _ pattern: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        // Patterns are literals in this file, so a failure to compile is a programming error.
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
