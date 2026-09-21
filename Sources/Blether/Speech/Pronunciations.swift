import Foundation

/// One row of the Pronunciations table: what the LLM writes, and what the voice should say instead.
struct Pronunciation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var original = ""
    var replacement = ""
}

/// Swaps words for their phonetic spellings just before synthesis, after the LLM has done its
/// work, so a voice says "cube-control" while the preamble writer still reads "kubectl". A port
/// of apply_word_replacements in claude-speaks' audio.py, with one change: the boundary is
/// whitespace or the edge of the text rather than `\b`, so ".env" and "SKILL.md" match too.
enum Pronunciations {
    static func apply(_ text: String, _ pairs: [Pronunciation]) -> String {
        var text = text
        for pair in pairs {
            let original = pair.original.trimmingCharacters(in: .whitespaces)
            guard !original.isEmpty else { continue }
            let pattern = "(?<=^|\\s)" + NSRegularExpression.escapedPattern(for: original) + "(?=$|\\s|[.,;:!?)\"'])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else { continue }
            let template = NSRegularExpression.escapedTemplate(for: pair.replacement)
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        return text
    }
}
