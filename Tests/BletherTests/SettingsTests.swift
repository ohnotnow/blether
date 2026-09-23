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

    @MainActor func testListenAfterReplyDefaultsOffAndRoundTrips() {
        let settings = settings
        XCTAssertFalse(settings.listensAfterReply, "the privacy gate is closed until opened")
        settings.listensAfterReply = true
        XCTAssertTrue(settings.listensAfterReply)
    }

    @MainActor func testMicrophoneIDDefaultsToSystemDefaultAndRoundTrips() {
        let settings = settings
        XCTAssertNil(settings.microphoneID)
        settings.microphoneID = "USB-1234"
        XCTAssertEqual(settings.microphoneID, "USB-1234")
        settings.microphoneID = nil
        XCTAssertNil(settings.microphoneID)
        settings.microphoneID = ""
        XCTAssertNil(settings.microphoneID, "an empty id is the system default, not a device called nothing")
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

    @MainActor func testWordListsStartEmptyAndRoundTrip() {
        let settings = settings
        XCTAssertEqual(settings.heardWordList, [])
        XCTAssertEqual(settings.pronunciations, [])
        settings.heardWords = " laravel, ,CVE\n"
        let pair = Pronunciation(original: "kubectl", replacement: "cube-control")
        settings.pronunciations = [pair]
        XCTAssertEqual(self.settings.heardWordList, ["laravel", "CVE"])
        XCTAssertEqual(self.settings.pronunciations, [pair])
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

    @MainActor func testVoiceDesignsDefaultToTheFourWithServalanFirstAndQualityBetter() {
        XCTAssertEqual(settings.voiceDesigns.map(\.id), ["servalan", "marvin", "danish-detective", "the-guide"])
        XCTAssertEqual(Set(settings.voiceDesigns.map(\.quality)), [.better])
    }

    @MainActor func testADesignStoredWithoutAQualityReadsAsBetter() throws {
        let old = #"[{"id": "dame", "name": "Dame", "description": "Female, loud."}]"#
        defaults.set(Data(old.utf8), forKey: "voiceDesigns")
        XCTAssertEqual(settings.voiceDesigns, [VoiceDesign(id: "dame", name: "Dame", description: "Female, loud.", quality: .better)])
    }

    @MainActor func testVoiceDesignsAddUpdateAndDeleteLikePersonas() {
        let settings = settings
        settings.addVoiceDesign(name: "  Dame \n", description: " Female, loud. ", quality: .faster)
        let dame = settings.voiceDesigns[4]
        XCTAssertEqual(dame.name, "Dame")
        XCTAssertEqual(dame.description, "Female, loud.")
        XCTAssertEqual(dame.quality, .faster)
        XCTAssertFalse(VoiceDesign.defaults.map(\.id).contains(dame.id))
        settings.updateVoiceDesign(VoiceDesign(id: "marvin", name: "Marv", description: "cheerier", quality: .faster))
        XCTAssertEqual(settings.voiceDesigns[1].name, "Marv")
        XCTAssertEqual(self.settings.voiceDesigns[1].quality, .faster, "a second instance sees the quality")
        settings.updateVoiceDesign(VoiceDesign(id: "ghost", name: "Ghost", description: "x"))
        XCTAssertEqual(settings.voiceDesigns.count, 5)
        settings.deleteVoiceDesign(id: "marvin")
        XCTAssertEqual(self.settings.voiceDesigns.map(\.name), ["Servalan", "Danish Detective", "The Guide", "Dame"], "a second instance sees it")
    }

    @MainActor func testDeletingEveryVoiceDesignLeavesNoneRatherThanTheDefaults() {
        let settings = settings
        for design in settings.voiceDesigns { settings.deleteVoiceDesign(id: design.id) }
        XCTAssertEqual(self.settings.voiceDesigns, [])
    }

    @MainActor func testBreezeReaderSeesTheLatestWriteFromAnotherThread() async {
        let settings = settings
        let read = settings.breezeReader()
        settings.updateVoiceDesign(VoiceDesign(id: "servalan", name: "Servalan", description: "Deeper.", quality: .faster))
        let designs = await Task.detached { read() }.value
        XCTAssertEqual(designs.first?.description, "Deeper.")
        XCTAssertEqual(designs.first?.quality, .faster)
    }

    @MainActor func testValuesRoundTripThroughASecondInstance() {
        let settings = settings
        let dame = Persona(id: "dame", name: "Dame", description: "a wildly excited pantomime dame")
        settings.setLLMModel("other:7b", for: .compatible)
        settings.setLLMBaseURL("http://example.test/v1")
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
        settings.setAPIKey("sk-test", for: "llm")
        XCTAssertEqual(settings.llmAPIKey, "sk-test")
        XCTAssertTrue(settings.hasLLMKey)
        XCTAssertEqual(try keychain.secret(account: "llm"), "sk-test")
        settings.setAPIKey(nil, for: "llm")
        XCTAssertNil(settings.llmAPIKey)
        XCTAssertFalse(settings.hasLLMKey)
    }

    @MainActor func testLLMPresetsOwnTheAddressAndShareSpeechKeys() throws {
        let settings = settings
        XCTAssertEqual(settings.llmProvider, .compatible, "an install from before presets keeps its Ollama")
        settings.setLLMModel("mine:7b", for: .compatible)
        XCTAssertEqual(settings.llmModel(for: .xai), "grok-4.6", "editing one provider leaves the others alone")
        XCTAssertEqual(settings.llmModel, "mine:7b")

        settings.llmProvider = .xai
        XCTAssertEqual(settings.llmBaseURL, "https://api.x.ai/v1")
        XCTAssertEqual(settings.llmModel, "grok-4.6")
        settings.setLLMBaseURL("http://nope")
        XCTAssertEqual(settings.llmBaseURL, "https://api.x.ai/v1", "a preset's address is fixed")
        XCTAssertEqual(settings.llmBaseURL(for: .compatible), "http://nope")
        settings.setAPIKey("xai-key", for: "xai")
        XCTAssertEqual(settings.llmAPIKey, "xai-key", "the speech provider's key, from the same Keychain entry")
        XCTAssertEqual(LLMProvider.anthropic.keychainAccount, "anthropic", "its own account")
        XCTAssertEqual(LLMProvider.compatible.keychainAccount, "llm", "the pre-preset account, so an existing key still works")

        settings.setLLMModel("grok-4.6-mini", for: .xai)
        settings.llmProvider = .compatible
        XCTAssertEqual(settings.llmModel, "mine:7b", "each provider keeps its model")
        XCTAssertEqual(settings.llmProvider, .compatible)
        settings.llmProvider = .xai
        XCTAssertEqual(settings.llmModel, "grok-4.6-mini")
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

    /// The 2026-09-20 review: a copy of an OpenAI default profile was landing on Kokoro with OpenAI voice ids.
    @MainActor func testAddProfileCopiesTheDefaultProviderAndRememberedVoices() {
        let settings = settings
        settings.setProvider(id: "OpenAI", in: settings.defaultProfileID)
        let pi = settings.addProfile(name: "pi")
        XCTAssertEqual(pi.providerID, "OpenAI")
        XCTAssertEqual(pi.roles, settings.defaultProfile.roles)
        XCTAssertEqual(pi.rememberedVoices, settings.defaultProfile.rememberedVoices)
    }

    @MainActor func testTrailingSilenceDefaultsAndClamps() {
        let settings = settings
        XCTAssertEqual(settings.trailingSilence, 2.5)
        settings.trailingSilence = 4
        XCTAssertEqual(self.settings.trailingSilence, 4)
        defaults.set(0.1, forKey: "trailingSilence")
        XCTAssertEqual(self.settings.trailingSilence, 1)
        defaults.set(60, forKey: "trailingSilence")
        XCTAssertEqual(self.settings.trailingSilence, 6)
    }

    @MainActor func testProfileNamesStayUnique() {
        let settings = settings
        XCTAssertEqual(settings.addProfile(name: "New profile").name, "New profile")
        XCTAssertEqual(settings.addProfile(name: "New profile").name, "New profile 2")
        XCTAssertEqual(settings.addProfile(name: "new PROFILE ").name, "new PROFILE 3", "matched the way hooks match: trimmed, any case; your casing is kept")
        let pi = settings.addProfile(name: "pi")

        XCTAssertFalse(settings.renameProfile(id: pi.id, name: "Default"), "the first profile is Default")
        XCTAssertEqual(settings.profile(named: "pi"), settings.profiles.last)
        XCTAssertTrue(settings.renameProfile(id: pi.id, name: "pi"), "keeping your own name is fine")
        XCTAssertTrue(settings.renameProfile(id: pi.id, name: "hermes"))
        XCTAssertTrue(settings.isProfileNameTaken("HERMES", excluding: nil))
        XCTAssertFalse(settings.isProfileNameTaken("hermes", excluding: pi.id))
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

    @MainActor func testProfileProviderDefaultsToNilAndRoundTrips() throws {
        let settings = settings
        XCTAssertNil(settings.defaultProfile.providerID)
        let old = try JSONEncoder().encode([Profile(id: "default", name: "Default", roles: [:])])
        defaults.set(old, forKey: "profiles")
        XCTAssertNil(self.settings.defaultProfile.providerID, "a profile saved before providers decodes")

        settings.setProvider(id: "openai", in: "default")
        XCTAssertEqual(settings.defaultProfile.providerID, "openai")
        XCTAssertEqual(self.settings.defaultProfile.providerID, "openai")
        settings.setProvider(id: nil, in: "default")
        XCTAssertNil(settings.defaultProfile.providerID)
        settings.setProvider(id: "xai", in: "ghost")
        XCTAssertNil(settings.defaultProfile.providerID)
    }

    @MainActor func testSwitchingProviderAndBackRestoresTheVoicesEachProviderHad() throws {
        let settings = settings
        var roles = settings.roles
        roles[.main]?.voiceID = "kokoro-main"
        roles[.monologue]?.voiceID = "kokoro-preamble"
        settings.updateRoles(roles, in: "default")

        settings.setProvider(id: "elevenlabs", in: "default")
        XCTAssertEqual(settings.roles[.main]?.voiceID, "kokoro-main", "nothing remembered for ElevenLabs yet, so the ids are left alone")
        roles = settings.roles
        roles[.main]?.voiceID = "eleven-main"
        settings.updateRoles(roles, in: "default")

        settings.setProvider(id: nil, in: "default")
        XCTAssertEqual(settings.roles[.main]?.voiceID, "kokoro-main")
        XCTAssertEqual(settings.roles[.monologue]?.voiceID, "kokoro-preamble")

        settings.setProvider(id: "elevenlabs", in: "default")
        XCTAssertEqual(settings.roles[.main]?.voiceID, "eleven-main")
        XCTAssertEqual(settings.roles[.monologue]?.voiceID, "kokoro-preamble", "never chosen under ElevenLabs, so it keeps the Kokoro id")
        XCTAssertEqual(settings.roles[.main]?.personaID, roles[.main]?.personaID, "personas are not per provider")

        let old = try JSONEncoder().encode([Profile(id: "default", name: "Default", roles: [:])])
        defaults.set(old, forKey: "profiles")
        XCTAssertEqual(self.settings.defaultProfile.rememberedVoices, [:], "a profile saved before the memory decodes")
    }

    @MainActor func testProviderKeysLiveInKeychainOnePerProvider() throws {
        let settings = settings
        XCTAssertNil(settings.apiKey(for: "elevenlabs"))
        XCTAssertFalse(settings.hasAPIKey(for: "elevenlabs"))
        settings.setAPIKey("el-1", for: "elevenlabs")
        settings.setAPIKey("oa-1", for: "openai")
        XCTAssertEqual(settings.apiKey(for: "elevenlabs"), "el-1")
        XCTAssertEqual(settings.apiKey(for: "openai"), "oa-1")
        XCTAssertTrue(settings.hasAPIKey(for: "openai"))
        XCTAssertNil(settings.apiKey(for: "xai"))
        XCTAssertNil(settings.llmAPIKey, "the LLM key is a separate account")
        settings.setAPIKey(nil, for: "elevenlabs")
        XCTAssertNil(settings.apiKey(for: "elevenlabs"))
        XCTAssertEqual(settings.apiKey(for: "openai"), "oa-1")
        settings.setAPIKey(nil, for: "openai")
    }

    /// Providers call the reader from their own tasks; it must not touch the main actor.
    @MainActor func testAPIKeyReaderWorksOffTheMainActorAndSeesLaterSaves() async {
        let settings = settings
        let read = settings.apiKeyReader(for: "xai")
        settings.setAPIKey("x-1", for: "xai")
        let offMain = await Task.detached { read() }.value
        XCTAssertEqual(offMain, "x-1")
        settings.setAPIKey(nil, for: "xai")
        XCTAssertNil(read())
    }

    @MainActor func testToneSourceDefaultsOffRoundTripsAndIgnoresGarbage() {
        let settings = settings
        XCTAssertEqual(settings.toneSource, .off)
        settings.toneSource = .jev
        XCTAssertEqual(self.settings.toneSource, .jev)
        defaults.set("vibes", forKey: "toneSource")
        XCTAssertEqual(self.settings.toneSource, .off)
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

final class LogContentTests: XCTestCase {
    override func tearDown() { Log.logsContent.withLock { $0 = false } }

    func testContentIsHiddenUnlessSwitchedOn() {
        Log.logsContent.withLock { $0 = false }
        XCTAssertEqual(Log.content("send it to someone at example dot com"), "[37 chars, content logging off]")
        Log.logsContent.withLock { $0 = true }
        XCTAssertEqual(Log.content("send it to  someone"), "\"send it to someone\"")
        let long = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(Log.content(long), "\"\(long)\"", "in full once switched on")
        XCTAssertEqual(Log.content(long, limit: 9), "\"word word…\"")
    }
}

final class FirstAnswerLLMTests: XCTestCase {
    private struct Canned: LLM {
        let result: Result<String, LLMError>
        func complete(system: String, user: String) async throws -> String { try result.get() }
    }

    func testReportsOnlyAnAnswer() async throws {
        let counter = ProviderTestSupport.Counter()
        let ok = FirstAnswerLLM(wrapped: Canned(result: .success("hi"))) { counter.increment() }
        let answer = try await ok.complete(system: "", user: "")
        XCTAssertEqual(answer, "hi")
        XCTAssertEqual(counter.value, 1)

        let bad = FirstAnswerLLM(wrapped: Canned(result: .failure(.emptyResponse))) { counter.increment() }
        do { _ = try await bad.complete(system: "", user: ""); XCTFail("expected a throw") } catch {}
        XCTAssertEqual(counter.value, 1)
    }
}
