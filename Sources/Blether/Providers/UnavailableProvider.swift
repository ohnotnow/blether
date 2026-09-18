/// Stands in when Kokoro cannot start at all (no uv, no bundled script). Every clip fails, so the
/// pipeline beeps and the menubar line explains why, rather than the app having no provider.
struct UnavailableProvider: Provider {
    let name = "unavailable"
    let maxMainCharacters = 3000
    let reason: String

    func voices() async throws -> [Voice] { throw ProviderError.other(reason) }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip { throw ProviderError.other(reason) }
}
