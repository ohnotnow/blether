import XCTest
@testable import Blether

private struct NamedProvider: Provider {
    let name: String
    let maxMainCharacters = 800
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip { throw ProviderError.noAudio }
}

private struct SharingProvider: Provider {
    let name: String
    let keychainAccount = "openrouter"
    let maxMainCharacters = 800
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip { throw ProviderError.noAudio }
}

final class ProviderRegistryTests: XCTestCase {
    private let registry = ProviderRegistry([NamedProvider(name: "kokoro"), NamedProvider(name: "openai"), NamedProvider(name: "xai")])

    func testLooksUpByNameAndFallsBackToKokoro() {
        XCTAssertEqual(registry.provider(id: "openai").name, "openai")
        XCTAssertEqual(registry.provider(id: nil).name, "kokoro")
        XCTAssertEqual(registry.provider(id: "nope").name, "kokoro")
        XCTAssertEqual(registry.ids, ["kokoro", "openai", "xai"])
    }

    func testWithoutKokoroTheFirstProviderIsTheDefault() {
        let registry = ProviderRegistry([NamedProvider(name: "openai"), NamedProvider(name: "xai")])
        XCTAssertEqual(registry.provider(id: nil).name, "openai")
    }

    func testKeyAccountsSkipLocalProvidersAndListASharedKeyOnce() {
        let registry = ProviderRegistry([NamedProvider(name: "kokoro"), NamedProvider(name: "openai"), GeminiProvider(apiKey: { nil }), NamedProvider(name: "xai"), SharingProvider(name: "another-openrouter-model")])
        XCTAssertEqual(registry.keyAccounts, ["openai", "openrouter", "xai"])
    }

    func testDisplayNames() {
        XCTAssertEqual(ProviderRegistry.displayName(id: "elevenlabs"), "ElevenLabs")
        XCTAssertEqual(ProviderRegistry.displayName(id: "xai"), "xAI")
        XCTAssertEqual(ProviderRegistry.displayName(id: "recording"), "Recording")
        XCTAssertEqual(ProviderRegistry.displayName(id: "openrouter"), "OpenRouter")
    }
}
