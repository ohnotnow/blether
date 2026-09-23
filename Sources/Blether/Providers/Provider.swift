import Foundation

struct Voice: Sendable, Hashable {
    let id: String
    let name: String
    let language: String
}

/// A playable file in the temp dir. The player deletes it after playing.
struct AudioClip: Sendable {
    let url: URL
}

/// A speech service. Every provider, built in or external, has exactly this surface.
protocol Provider: Sendable {
    /// Short lowercase identifier: "apple", "elevenlabs", ...
    var name: String { get }
    /// Longest reply clip this provider should be asked for, in characters. Local synthesis is free
    /// so Kokoro allows 3000; API providers that bill per character set less.
    var maxMainCharacters: Int { get }
    func voices() async throws -> [Voice]
    /// `language` is the language of the text as a human name from the notification list ("French",
    /// "Chinese (Simplified)"), or nil for the app's default, British English. It is never derived
    /// from the voice. A provider that detects the language from the text may ignore it.
    /// `tone` is the mood of the text, nil when tone is off or the clip is not the reply. A provider
    /// that cannot express it ignores it.
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip
    /// A paragraph appended to the summary prompt naming the inline tags this provider's synthesis
    /// understands (ElevenLabs audio tags, xAI prosody tags). nil means plain text only.
    var markupHint: String? { get }
    /// True for a provider slower than real time: the reply is split into sentence chunks, made one
    /// at a time in order, so the first plays while the rest are made (blether-vNbF9).
    var speaksInChunks: Bool { get }
}

extension Provider {
    var markupHint: String? { nil }
    var speaksInChunks: Bool { false }
}
