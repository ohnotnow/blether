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
    func synthesise(_ text: String, voice: String) async throws -> AudioClip
}
