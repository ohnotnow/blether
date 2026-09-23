import NaturalLanguage

/// Splits a reply into chunks of whole sentences, so a provider slower than real time can start
/// speaking the first while the rest are made (blether-vNbF9). A paragraph break always ends a chunk;
/// within a paragraph, sentences are joined up to `limit` characters. A longer sentence stands alone.
enum ReplyChunker {
    static let limit = 200

    static func split(_ text: String, limit: Int = limit) -> [String] {
        var chunks: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            var current = ""
            for sentence in sentences(in: paragraph) {
                if !current.isEmpty, current.count + 1 + sentence.count > limit {
                    chunks.append(current)
                    current = ""
                }
                current += current.isEmpty ? sentence : " " + sentence
            }
            if !current.isEmpty { chunks.append(current) }
        }
        return chunks
    }

    private static func sentences(in paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        return tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex)
            .map { paragraph[$0].trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
