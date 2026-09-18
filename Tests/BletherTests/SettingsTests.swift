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
        let voice = KokoroProvider.defaultVoiceID
        XCTAssertEqual(settings.roles[.main]?.voiceID, voice)
        XCTAssertEqual(settings.roles[.monologue]?.voiceID, voice)
        XCTAssertEqual(settings.voiceID(for: .main), voice)
    }

    @MainActor func testStoredAppleVoiceIdFallsBackToKokoroDefault() {
        let settings = settings
        settings.roles = [.main: RoleSettings(personaID: nil, voiceID: "com.apple.voice.compact.en-GB.Daniel")]
        XCTAssertEqual(settings.voiceID(for: .main), KokoroProvider.defaultVoiceID)
        XCTAssertEqual(settings.voiceID(for: .monologue), KokoroProvider.defaultVoiceID, "missing role also falls back")
    }

    @MainActor func testUVPathDefaultsEmptyAndRoundTrips() {
        XCTAssertEqual(settings.uvPath, "")
        settings.uvPath = "/somewhere/uv"
        XCTAssertEqual(settings.uvPath, "/somewhere/uv")
    }

    @MainActor func testListenOnNetworkDefaultsOffAndRoundTrips() {
        XCTAssertFalse(settings.listensOnLAN)
        settings.listensOnLAN = true
        XCTAssertTrue(settings.listensOnLAN)
    }

    @MainActor func testTogglesDefaultToOn() {
        let settings = settings
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.speaksPreamble)
        XCTAssertTrue(settings.speaksMainReply)
        XCTAssertTrue(settings.speaksNotifications)
    }

    @MainActor func testNotificationsToggleRoundTrips() {
        settings.speaksNotifications = false
        XCTAssertFalse(settings.speaksNotifications)
    }

    // MARK: - Notifications

    @MainActor func testFreshDefaultsGiveTheNotificationRoleMarvinAndTheDefaultVoice() {
        let settings = settings
        XCTAssertEqual(settings.roles[.notification], RoleSettings(personaID: "marvin", voiceID: KokoroProvider.defaultVoiceID))
        XCTAssertEqual(settings.persona(for: .notification), Persona.marvin)
        XCTAssertEqual(Role.notification.displayName, "Notification")
        XCTAssertEqual(Role.allCases.last, .notification, "heard on its own, so listed last")
    }

    @MainActor func testProfilesStoredWithoutTheNotificationRoleGetItsDefaultsWithoutWriting() throws {
        let old = Profile(id: "default", name: "Default", roles: [.main: RoleSettings(personaID: nil, voiceID: "v1"), .monologue: RoleSettings(personaID: nil, voiceID: "v2")])
        let stored = try JSONEncoder().encode([old])
        defaults.set(stored, forKey: "profiles")

        let settings = settings
        XCTAssertEqual(settings.roles[.main]?.voiceID, "v1")
        XCTAssertEqual(settings.roles[.notification], RoleSettings(personaID: "marvin", voiceID: KokoroProvider.defaultVoiceID))
        XCTAssertEqual(defaults.data(forKey: "profiles"), stored, "filled in on read only")

        settings.renameProfile(id: "default", name: "Mine")
        XCTAssertNotEqual(defaults.data(forKey: "profiles"), stored)
        XCTAssertEqual(self.settings.roles[.notification]?.personaID, "marvin")
    }

    @MainActor func testNotificationLanguagesDefaultToTheSevenAndRoundTrip() {
        let settings = settings
        let lines = settings.notificationLanguages.split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertEqual(lines, ["English 1", "French 5", "Spanish 5", "Italian 5", "Portuguese 5", "Hindi 5", "Chinese (Simplified) 5"])
        settings.notificationLanguages = "Glaswegian 3\nEnglish"
        XCTAssertEqual(self.settings.notificationLanguages, "Glaswegian 3\nEnglish")
    }

    @MainActor func testRememberQuipKeepsTheLastTenOldestFirst() {
        let settings = settings
        XCTAssertEqual(settings.recentQuips, [])
        for n in 1...12 { settings.rememberQuip("line \(n)") }
        XCTAssertEqual(settings.recentQuips.count, 10)
        XCTAssertEqual(settings.recentQuips.first, "line 3")
        XCTAssertEqual(settings.recentQuips.last, "line 12")
        XCTAssertEqual(self.settings.recentQuips, settings.recentQuips, "a second instance sees the same history")
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

    // MARK: - Profiles

    @MainActor func testFreshDefaultsHaveOneDefaultProfile() {
        let settings = settings
        XCTAssertEqual(settings.profiles.count, 1)
        XCTAssertEqual(settings.profiles[0].name, "Default")
        XCTAssertEqual(settings.defaultProfileID, "default")
        XCTAssertEqual(settings.defaultProfile.roles[.monologue]?.personaID, "marvin")
        XCTAssertEqual(settings.roles, settings.defaultProfile.roles)
    }

    @MainActor func testStoredRolesFromBeforeProfilesSeedTheDefaultProfileWithoutWriting() {
        let legacy = [.main: RoleSettings(personaID: "dame", voiceID: "v1"), .monologue: RoleSettings(personaID: nil, voiceID: "v2")] as [Role: RoleSettings]
        let stored = Dictionary(uniqueKeysWithValues: legacy.map { ($0.key.rawValue, $0.value) })
        defaults.set(try! JSONEncoder().encode(stored), forKey: "roles")

        let settings = settings
        var expected = legacy
        expected[.notification] = RoleSettings(personaID: "marvin", voiceID: KokoroProvider.defaultVoiceID)
        XCTAssertEqual(settings.profiles[0].roles, expected, "the pre-profile roles, plus the role that did not exist then")
        XCTAssertEqual(settings.roles[.main]?.voiceID, "v1")
        XCTAssertNil(defaults.data(forKey: "profiles"), "reading migrates in memory only")

        settings.renameProfile(id: "default", name: "Mine")
        XCTAssertNotNil(defaults.data(forKey: "profiles"), "the first profile write persists")
        XCTAssertEqual(self.settings.profiles[0].roles, expected)
    }

    @MainActor func testProfileRolesEncodeAsAJSONObject() throws {
        let data = try JSONEncoder().encode(settings.defaultProfile)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""main":{"#), json)
        XCTAssertTrue(json.contains(#""monologue":{"#), json)
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: data), settings.defaultProfile)
    }

    @MainActor func testProfileLookupByNameIsTrimmedAndCaseInsensitive() {
        let settings = settings
        let hermes = settings.addProfile(name: "hermes")
        XCTAssertEqual(settings.profile(named: "hermes"), hermes)
        XCTAssertEqual(settings.profile(named: "Hermes"), hermes)
        XCTAssertEqual(settings.profile(named: " hermes "), hermes)
        XCTAssertEqual(settings.profile(named: nil), settings.defaultProfile)
        XCTAssertEqual(settings.profile(named: ""), settings.defaultProfile)
        XCTAssertEqual(settings.profile(named: "nope"), settings.defaultProfile)
    }

    @MainActor func testRolesViewOnlyTouchesTheDefaultProfile() {
        let settings = settings
        let pi = settings.addProfile(name: "pi")
        settings.roles = [.main: RoleSettings(personaID: nil, voiceID: "changed"), .monologue: RoleSettings(personaID: "marvin", voiceID: "changed")]
        XCTAssertEqual(settings.defaultProfile.roles[.main]?.voiceID, "changed")
        XCTAssertEqual(settings.profiles.first { $0.id == pi.id }?.roles, pi.roles)

        settings.updateRoles([.main: RoleSettings(personaID: nil, voiceID: "pi-voice")], in: pi.id)
        XCTAssertEqual(settings.profiles.first { $0.id == pi.id }?.roles[.main]?.voiceID, "pi-voice")
        XCTAssertEqual(settings.roles[.main]?.voiceID, "changed")
        XCTAssertEqual(settings.voiceID(for: .main, in: settings.profile(named: "pi")), "pi-voice")
        XCTAssertEqual(settings.voiceID(for: .main), "changed")
    }

    @MainActor func testAddProfileTrimsAndCopiesTheDefaultRoles() {
        let settings = settings
        let pi = settings.addProfile(name: "  pi ")
        XCTAssertEqual(pi.name, "pi")
        XCTAssertEqual(pi.roles, settings.defaultProfile.roles)
        XCTAssertNotEqual(pi.id, "default")
        XCTAssertEqual(settings.profiles.count, 2)
        XCTAssertEqual(settings.defaultProfileID, "default", "adding does not move the default")
    }

    @MainActor func testDeletingTheDefaultHandsDefaultToTheFirstRemaining() {
        let settings = settings
        let pi = settings.addProfile(name: "pi")
        settings.addProfile(name: "hermes")
        settings.deleteProfile(id: "default")
        XCTAssertEqual(settings.profiles.map(\.name), ["pi", "hermes"])
        XCTAssertEqual(settings.defaultProfileID, pi.id)

        settings.deleteProfile(id: pi.id)
        XCTAssertEqual(settings.profiles.map(\.name), ["hermes"])
        settings.deleteProfile(id: settings.profiles[0].id)
        XCTAssertEqual(settings.profiles.count, 1, "the last profile cannot be deleted")
        settings.deleteProfile(id: "ghost")
        XCTAssertEqual(settings.profiles.count, 1)
    }

    @MainActor func testStaleDefaultProfileIDFallsBackToTheFirstProfile() {
        let settings = settings
        defaults.set("gone", forKey: "defaultProfileID")
        XCTAssertEqual(settings.defaultProfileID, "default")
    }

    @MainActor func testDeletePersonaClearsItFromEveryProfile() {
        let settings = settings
        let pi = settings.addProfile(name: "pi")
        settings.updateRoles([.main: RoleSettings(personaID: "marvin", voiceID: "v")], in: pi.id)
        settings.deletePersona(id: "marvin")
        XCTAssertNil(settings.profile(named: "pi").roles[.main]?.personaID)
        XCTAssertEqual(settings.profile(named: "pi").roles[.main]?.voiceID, "v")
        XCTAssertNil(settings.roles[.monologue]?.personaID)
    }
}
