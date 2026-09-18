/// The weighted list of languages a notification line may be written in, parsed from the text the
/// user typed in Settings > Behaviour: one language per line, an optional integer weight after the
/// last space. The name goes to the LLM verbatim and to the provider for pronunciation.
struct NotificationLanguages: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let name: String
        let weight: Int
    }

    static let fallback = Entry(name: "English", weight: 1)

    let entries: [Entry]

    /// Blank lines are skipped, as is any entry whose weight is zero or less. No weight means 1.
    /// An empty result becomes "English 1" so the roulette always has a wheel.
    init(parsing text: String) {
        let parsed = text.split(whereSeparator: \.isNewline).compactMap { line -> Entry? in
            var words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { return nil }
            var weight = 1
            if words.count > 1, let trailing = Int(words[words.count - 1]) {
                weight = trailing
                words.removeLast()
            }
            guard weight > 0 else { return nil }
            return Entry(name: words.joined(separator: " "), weight: weight)
        }
        entries = parsed.isEmpty ? [Self.fallback] : parsed
    }

    /// Weighted random pick. `random` is given the total weight and returns a value in 0..<total;
    /// the entries own consecutive ranges in list order, so tests can steer it.
    func pick(random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let total = entries.reduce(0) { $0 + $1.weight }
        var remaining = random(total)
        for entry in entries {
            if remaining < entry.weight { return entry.name }
            remaining -= entry.weight
        }
        return entries[entries.count - 1].name
    }
}
