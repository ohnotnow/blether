/// The nine styles Mistral's voices take as a suffix: the shared vocabulary every classifier
/// produces and every provider may express. Order is the old classifier prompt's.
enum Tone: String, CaseIterable, Sendable {
    case neutral, sarcasm, confused, shameful, sad, jealousy, frustrated, curious, confident

    /// One line for a classifier to judge by, from claude-speaks' prompts/mistral/classifier.md.
    var criterion: String {
        switch self {
        case .neutral: "informational, calm; the default for most responses"
        case .sarcasm: "dry, deliberately sarcastic"
        case .confused: "uncertain, puzzled, asking for clarification"
        case .shameful: "apologetic about a mistake the assistant made"
        case .sad: "disappointed or resigned"
        case .jealousy: "envious (rare)"
        case .frustrated: "genuinely frustrated with something not working"
        case .curious: "exploratory, wondering, poking at something to see what happens"
        case .confident: "clearly asserting a solution or conclusion"
        }
    }
}
