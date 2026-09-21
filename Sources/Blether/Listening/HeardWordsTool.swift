import Foundation

/// The `heard_words` channel tool: the same list as the Listening page, edited from a session.
enum HeardWordsTool {
    static let minimumLength = 3

    @MainActor
    static func run(_ action: String, words: [String], settings: AppSettings) -> String {
        var lines: [String] = []
        if action == "add" {
            var list = settings.heardWordList
            let cleaned = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let refused = cleaned.filter { $0.count < minimumLength }
            var added: [String] = []
            for word in cleaned where word.count >= minimumLength && !list.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                list.append(word)
                added.append(word)
            }
            if !added.isEmpty { settings.heardWords = list.joined(separator: ", ") }
            lines.append(added.isEmpty ? "Nothing added." : "Added: \(added.joined(separator: ", ")).")
            if !refused.isEmpty { lines.append("Refused as too short to match safely: \(refused.joined(separator: ", ")).") }
        }
        let list = settings.heardWordList
        lines.append(list.isEmpty ? "No heard words yet." : "Heard words: \(list.joined(separator: ", ")).")
        return lines.joined(separator: " ")
    }
}
