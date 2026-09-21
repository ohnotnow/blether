import Foundation

/// Swaps words the transcriber keeps mishearing for the spelling the user listed. A port of
/// Handy's apply_custom_words (src-tauri/src/audio_toolkit/text.rs): edit distance scored against
/// each listed word, a phonetic bonus when Soundex agrees, over windows of one to three words so
/// "live wire" can become "livewire". Pure; the ears call it on every transcript.
enum WordCorrector {
    /// Handy's default. A score is edit distance over the longer length, so 0.18 lets an 8-letter
    /// word be one letter out, or about four letters out when the two sound alike.
    static let threshold = 0.18

    static func correct(_ text: String, words: [String], threshold: Double = threshold) -> String {
        let listed = words.compactMap { word -> (word: String, key: String)? in
            let key = matchKey(word)
            return isFuzzable(key) ? (word, key) : nil
        }
        guard !listed.isEmpty else { return text }

        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            var best: (count: Int, word: String, score: Double)?
            for n in stride(from: 3, through: 1, by: -1) where i + n <= tokens.count {
                let window = Array(tokens[i..<i + n])
                // A comma or full stop inside the window closes the candidate before it.
                if window.dropLast().contains(where: { !punctuation(of: $0).suffix.isEmpty }) { continue }
                let candidate = window.map(matchKey).joined()
                if let (word, score) = bestMatch(for: candidate, in: listed, threshold: threshold), score < (best?.score ?? .infinity) {
                    best = (n, word, score)
                }
            }
            if let best {
                let window = tokens[i..<i + best.count]
                let (prefix, _) = punctuation(of: window.first!)
                let (_, suffix) = punctuation(of: window.last!)
                result.append(prefix + matchingCase(of: window.first!, word: best.word) + suffix)
                i += best.count
            } else {
                result.append(tokens[i])
                i += 1
            }
        }
        return result.joined(separator: " ")
    }

    /// Lowercase alphanumerics only, so "Charge B," and "ChargeBee" compare as chargeb and chargebee.
    private static func matchKey(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The matcher is ASCII only: whitespace tokens and Soundex make no sense for CJK scripts.
    private static func isFuzzable(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func bestMatch(for candidate: String, in listed: [(word: String, key: String)], threshold: Double) -> (String, Double)? {
        guard isFuzzable(candidate), candidate.count <= 50 else { return nil }
        var best: (String, Double)?
        for (word, key) in listed {
            let longer = Double(max(candidate.count, key.count))
            // A window must not match a much shorter word: "openaigpt" is not "openai".
            guard Double(abs(candidate.count - key.count)) <= max(longer * 0.25, 2) else { continue }
            var score = Double(levenshtein(candidate, key)) / longer
            if candidate.allSatisfy(\.isLetter), key.allSatisfy(\.isLetter), soundex(candidate) == soundex(key) {
                score *= 0.3
            }
            if score < threshold, score < (best?.1 ?? .infinity) { best = (word, score) }
        }
        return best
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// American Soundex: first letter kept, the rest coded by consonant group, padded to four.
    private static func soundex(_ word: String) -> String {
        let codes: [Character: Character] = [
            "b": "1", "f": "1", "p": "1", "v": "1",
            "c": "2", "g": "2", "j": "2", "k": "2", "q": "2", "s": "2", "x": "2", "z": "2",
            "d": "3", "t": "3", "l": "4", "m": "5", "n": "5", "r": "6",
        ]
        guard let first = word.first else { return "" }
        var out = String(first.uppercased())
        var last = codes[first]
        for letter in word.dropFirst() {
            let code = codes[letter]
            if let code, code != last { out.append(code) }
            // h and w do not separate two like codes; vowels do.
            if letter != "h", letter != "w" { last = code }
            if out.count == 4 { break }
        }
        return out.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    private static func punctuation(of token: String) -> (prefix: String, suffix: String) {
        let prefix = token.prefix { !($0.isLetter || $0.isNumber) }
        let suffix = token.reversed().prefix { !($0.isLetter || $0.isNumber) }.reversed()
        return (String(prefix), String(suffix))
    }

    /// ALL CAPS stays capitals and a capital first letter stays capitalised; otherwise as listed.
    private static func matchingCase(of original: String, word: String) -> String {
        let letters = original.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase) { return word.uppercased() }
        if letters.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }
}
