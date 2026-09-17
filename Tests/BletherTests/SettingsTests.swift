import XCTest
@testable import Blether

/// Tests are main-actor individually rather than at class level: setUp and tearDown overrides
/// are nonisolated, and a class-level @MainActor makes every fixture hand-off a strict-concurrency error.
final class SettingsTests: XCTestCase {
    private let suite = "uk.ohnotnow.blether.tests.\(UUID().uuidString)"
    private let keychain = KeychainStore(service: "uk.ohnotnow.blether.tests.settings-\(UUID().uuidString)")
    private var defaults: UserDefaults!

    @MainActor private var settings: AppSettings { AppSettings(defaults: defaults, keychain: keychain) }

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try keychain.delete(account: "llm")
    }

    @MainActor func testFreshDefaultsPointAtLocalOllamaWithMarvin() {
        let settings = settings
        XCTAssertEqual(settings.llmBaseURL, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(settings.llmModel, "maternion/minicpm5:2b")
        XCTAssertEqual(settings.llmExtraBody, "{}")
        XCTAssertEqual(settings.personas, [Persona.marvin])
        XCTAssertNil(settings.roles[.main]?.personaID)
        XCTAssertEqual(settings.roles[.monologue]?.personaID, "marvin")
        let voice = AppleVoicesProvider.defaultVoiceID()
        XCTAssertEqual(settings.roles[.main]?.voiceID, voice)
        XCTAssertEqual(settings.roles[.monologue]?.voiceID, voice)
        XCTAssertEqual(settings.voiceID(for: .main), voice)
    }

    @MainActor func testTogglesDefaultToOn() {
        let settings = settings
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.speaksPreamble)
        XCTAssertTrue(settings.speaksMainReply)
    }

    @MainActor func testTogglesRoundTripThroughASecondInstance() {
        let first = settings
        first.isEnabled = false
        first.speaksPreamble = false
        first.speaksMainReply = false
        XCTAssertFalse(first.isEnabled)

        let second = settings
        XCTAssertFalse(second.isEnabled)
        XCTAssertFalse(second.speaksPreamble)
        XCTAssertFalse(second.speaksMainReply)

        second.isEnabled = true
        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.speaksPreamble)
    }

    @MainActor func testAddPersonaTrimsAndAppendsWithoutAssigning() {
        let settings = settings
        settings.addPersona(name: "  Dame \n", description: " a wildly excited pantomime dame ")
        XCTAssertEqual(settings.personas.count, 2)
        let dame = settings.personas[1]
        XCTAssertEqual(dame.name, "Dame")
        XCTAssertEqual(dame.description, "a wildly excited pantomime dame")
        XCTAssertNotEqual(dame.id, "marvin")
        XCTAssertEqual(settings.roles[.monologue]?.personaID, "marvin")
        XCTAssertEqual(self.settings.personas.count, 2, "a second instance sees it")
    }

    @MainActor func testUpdatePersonaReplacesByIdAndIgnoresUnknown() {
        let settings = settings
        settings.updatePersona(Persona(id: "marvin", name: "Marv", description: "cheerier"))
        XCTAssertEqual(settings.personas.map(\.name), ["Marv"])
        settings.updatePersona(Persona(id: "ghost", name: "Ghost", description: "x"))
        XCTAssertEqual(settings.personas.count, 1)
    }

    @MainActor func testDeletePersonaClearsRolesPointingAtItButKeepsTheirVoice() {
        let settings = settings
        let voice = settings.roles[.monologue]!.voiceID
        settings.deletePersona(id: "marvin")
        XCTAssertEqual(settings.personas, [])
        XCTAssertNil(settings.roles[.monologue]?.personaID)
        XCTAssertEqual(settings.roles[.monologue]?.voiceID, voice)
        XCTAssertNil(self.settings.persona(for: .monologue))
    }

    @MainActor func testValuesRoundTripThroughASecondInstance() {
        let settings = settings
        let dame = Persona(id: "dame", name: "Dame", description: "a wildly excited pantomime dame")
        settings.llmModel = "other:7b"
        settings.llmBaseURL = "http://example.test/v1"
        settings.llmExtraBody = #"{"think": false}"#
        settings.personas = [Persona.marvin, dame]
        settings.roles = [.main: RoleSettings(personaID: "dame", voiceID: "v1"), .monologue: RoleSettings(personaID: nil, voiceID: "v2")]

        let again = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(again.llmModel, "other:7b")
        XCTAssertEqual(again.llmBaseURL, "http://example.test/v1")
        XCTAssertEqual(again.llmExtraBody, #"{"think": false}"#)
        XCTAssertEqual(again.personas, [Persona.marvin, dame])
        XCTAssertEqual(again.roles[.main], RoleSettings(personaID: "dame", voiceID: "v1"))
        XCTAssertEqual(again.roles[.monologue], RoleSettings(personaID: nil, voiceID: "v2"))
        XCTAssertEqual(again.voiceID(for: .monologue), "v2")
    }

    @MainActor func testPersonaLookupByRole() {
        let settings = settings
        XCTAssertNil(settings.persona(for: .main))
        XCTAssertEqual(settings.persona(for: .monologue), Persona.marvin)

        settings.roles[.main]?.personaID = "marvin"
        XCTAssertEqual(settings.persona(for: .main), Persona.marvin)

        settings.roles[.main]?.personaID = "nobody"
        XCTAssertNil(settings.persona(for: .main))
    }

    @MainActor func testLLMKeyLivesInKeychain() {
        let settings = settings
        XCTAssertNil(settings.llmAPIKey)
        XCTAssertFalse(settings.hasLLMKey)
        settings.llmAPIKey = "sk-test"
        XCTAssertEqual(settings.llmAPIKey, "sk-test")
        XCTAssertTrue(settings.hasLLMKey)
        XCTAssertEqual(try keychain.secret(account: "llm"), "sk-test")
        settings.llmAPIKey = nil
        XCTAssertNil(settings.llmAPIKey)
        XCTAssertFalse(settings.hasLLMKey)
    }
}
