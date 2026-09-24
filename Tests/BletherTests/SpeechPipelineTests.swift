import XCTest
@testable import Blether

/// Records every synthesis request and can be told to fail for texts containing a marker.
private final class RecordingProvider: Provider, @unchecked Sendable {
    struct Call: Equatable { let text: String; let voice: String; let language: String?; let tone: Tone?; let url: URL }
    let name: String
    let maxMainCharacters: Int
    let markupHint: String?
    let speaksInChunks: Bool
    init(name: String = "recording", maxMainCharacters: Int = 800, markupHint: String? = nil, speaksInChunks: Bool = false) {
        self.name = name
        self.maxMainCharacters = maxMainCharacters
        self.markupHint = markupHint
        self.speaksInChunks = speaksInChunks
    }
    private let lock = NSLock()
    private var recorded: [Call] = []
    var failOnTextContaining: String?
    var failAll = false
    var calls: [Call] { lock.withLock { recorded } }

    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        if failAll { throw ProviderError.noAudio }
        if let marker = failOnTextContaining, text.contains(marker) { throw ProviderError.noAudio }
        let clip = makeTestClip()
        lock.withLock { recorded.append(Call(text: text, voice: voice, language: language, tone: tone, url: clip.url)) }
        return clip
    }
}

/// Simulates a reply starting to play while a notification is still being synthesised.
private final class StartsPlaybackMidSynthesisProvider: Provider, @unchecked Sendable {
    let name = "intruding"
    let maxMainCharacters = 800
    let queue: PlaybackQueue
    private let lock = NSLock()
    private var made: [URL] = []
    var urls: [URL] { lock.withLock { made } }
    init(queue: PlaybackQueue) { self.queue = queue }
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        await queue.enqueue(makeTestClip())
        let clip = makeTestClip()
        lock.withLock { made.append(clip.url) }
        return clip
    }
}

/// Simulates the user pressing stop while synthesis is still running.
private struct StopsMidSynthesisProvider: Provider {
    let name = "stopping"
    let maxMainCharacters = 800
    let queue: PlaybackQueue
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        await queue.stop()
        return makeTestClip()
    }
}

/// Simulates the user pressing stop while synthesis is still running, and then synthesis failing.
private struct StopsThenFailsProvider: Provider {
    let name = "stopping-failing"
    let maxMainCharacters = 800
    let queue: PlaybackQueue
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        await queue.stop()
        throw ProviderError.noAudio
    }
}

@MainActor
final class FakeEars: EarsArming {
    private(set) var armed: [SessionKey] = []
    func arm(for session: SessionKey) { armed.append(session) }
}

@MainActor
final class SpeechPipelineTests: XCTestCase {
    private let fakes = FakePlayers()
    private var players: [FakePlayer] { fakes.all }
    private let provider = RecordingProvider()
    private let llm = FakeLLM()
    private let suite = "uk.ohnotnow.blether.tests.\(UUID().uuidString)"
    private lazy var settings: AppSettings = {
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!, keychain: KeychainStore(service: "uk.ohnotnow.blether.tests.pipeline"))
        s.roles = [.main: RoleSettings(personaID: nil, voiceID: "v-main"), .monologue: RoleSettings(personaID: "marvin", voiceID: "v-mono"), .notification: RoleSettings(personaID: "marvin", voiceID: "v-note")]
        s.notificationLanguages = "French"
        return s
    }()
    private lazy var queue = PlaybackQueue(makePlayer: fakes.make)
    private var makeLLMCalls = 0
    private let long = Array(repeating: "word", count: 70).joined(separator: " ")

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: recentDirectory)
    }

    private let ears = FakeEars()
    private let session = SessionKey(id: "s-1", pid: 77)

    private let recentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("blether-pipeline-recent-\(UUID().uuidString)", isDirectory: true)
    private var recentNames: [String] { (try? FileManager.default.contentsOfDirectory(atPath: recentDirectory.path).sorted()) ?? [] }

    private func pipeline(provider: (any Provider)? = nil) -> SpeechPipeline {
        let llm = llm
        return SpeechPipeline(provider: provider ?? self.provider, queue: queue, settings: settings, ears: ears, recent: RecentClips(directory: recentDirectory)) { [weak self] _ in
            MainActor.assumeIsolated { self?.makeLLMCalls += 1 }
            return llm
        }
    }

    // MARK: - Arming the ears (blether-UkLWZ.8.6)

    func testListeningOnArmsTheEarsAfterTheLastClipPlays() async {
        settings.listensAfterReply = true
        await pipeline().speak(long, session: session)
        XCTAssertEqual(ears.armed, [], "not before the reply has been heard")
        drainQueue()
        XCTAssertEqual(ears.armed, [session])
    }

    func testListeningOffNeverArms() async {
        await pipeline().speak(long, session: session)
        drainQueue()
        XCTAssertEqual(ears.armed, [])
    }

    func testPreambleOnlyReplyStillArms() async {
        settings.listensAfterReply = true
        settings.speaksMainReply = false
        // Rule 3 skips the preamble while listening, so turn that rule's input off: nothing would play otherwise.
        await pipeline().speak(long, session: session)
        drainQueue()
        XCTAssertEqual(ears.armed, [], "listening on plus reply off plays nothing, so nothing arms")
    }

    func testFailedLastClipArmsAtOnceRatherThanNever() async {
        settings.listensAfterReply = true
        provider.failAll = true
        await pipeline().speak(long, session: session)
        XCTAssertEqual(ears.armed, [session])
    }

    /// The 2026-09-20 review: a failure after stop used to open the mic for a reply whose audio would have been dropped.
    func testFailureAfterStopDoesNotArm() async {
        settings.listensAfterReply = true
        await pipeline(provider: StopsThenFailsProvider(queue: queue)).speak(long, session: session)
        XCTAssertEqual(ears.armed, [])
    }

    func testNoSessionMeansNoArming() async {
        settings.listensAfterReply = true
        await pipeline().speak(long)
        drainQueue()
        XCTAssertEqual(ears.armed, [])
    }

    func testPronunciationsChangeWhatIsSpokenButNotWhatTheLLMReads() async {
        settings.pronunciations = [Pronunciation(original: "claude", replacement: "clawed")]
        llm.preambleScript = { _ in "Claude again" }
        llm.summaryScript = { _ in "Ask claude, not Claude's kid." }
        await pipeline().speak("Claude says " + long)
        XCTAssertEqual(Set(provider.calls.map(\.text)), ["clawed again ...", "Ask clawed, not clawed's kid."], "possessives count as the word")
        XCTAssertTrue(llm.calls.allSatisfy { $0.user.contains("Claude") && !$0.user.contains("clawed") })
    }

    func testRecentClipsAreKeptOnlyWhenTheToggleIsOn() async {
        await pipeline().speak(long)
        XCTAssertEqual(recentNames, [], "off by default")

        drainQueue()
        settings.keepsRecentClips = true
        await pipeline().speak(long)
        drainQueue()
        await pipeline().quip()
        XCTAssertEqual(Set(recentNames.map { String($0.dropFirst(20)) }), ["preamble.caf", "reply.caf", "notification.caf"])
    }

    func testPronunciationsApplyToTheQuipToo() async {
        settings.pronunciations = [Pronunciation(original: "id", replacement: "I.D")]
        llm.quipScript = { _ in "Your id, please." }
        await pipeline().quip()
        XCTAssertEqual(provider.calls.map(\.text), ["Your I.D, please."])
    }

    func testIdleQueuePlaysPreambleThenMainInTheirOwnVoices() async {
        await pipeline().speak(long)

        let calls = provider.calls
        XCTAssertEqual(calls.count, 2)
        let mono = calls.first { $0.voice == "v-mono" }
        let main = calls.first { $0.voice == "v-main" }
        XCTAssertEqual(mono?.text, "Oh joy, another reply ...")
        XCTAssertEqual(main?.text, "Compressed.")

        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].url, mono?.url)
        players[0].finish()
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].url, main?.url)
    }

    func testNamedProfileSpeaksInItsOwnVoices() async {
        let pi = settings.addProfile(name: "pi")
        settings.updateRoles([.main: RoleSettings(personaID: nil, voiceID: "pi-main"), .monologue: RoleSettings(personaID: "marvin", voiceID: "pi-mono")], in: pi.id)

        await pipeline().speak(long, profile: "Pi")

        XCTAssertEqual(Set(provider.calls.map(\.voice)), ["pi-mono", "pi-main"])
    }

    func testUnknownProfileFallsBackToTheDefault() async {
        settings.addProfile(name: "pi")

        await pipeline().speak(long, profile: "nope")

        XCTAssertEqual(Set(provider.calls.map(\.voice)), ["v-mono", "v-main"])
    }

    func testBusyQueueSkipsThePreamble() async {
        let pipeline = pipeline()
        queue.enqueue(makeTestClip())
        XCTAssertTrue(queue.isPlaying)

        await pipeline.speak(long)

        XCTAssertEqual(llm.preambleCalls, 0)
        XCTAssertEqual(llm.summaryCalls, 1)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-main"])
        players[0].finish()
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].url, provider.calls[0].url)
    }

    func testSpeakingOffDropsTheReplyWithoutSpendingAnything() async {
        settings.isEnabled = false
        await pipeline().speak(long)
        XCTAssertTrue(llm.calls.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertTrue(players.isEmpty)
        XCTAssertEqual(makeLLMCalls, 0, "the snapshot must not be built for a dropped reply")
    }

    /// Playback rule 3 (blether-VYQvH): the preamble is a delay before the mic opens, so listening skips it.
    func testListeningOnSkipsThePreamble() async {
        settings.listensAfterReply = true
        await pipeline().speak(long)
        XCTAssertEqual(llm.preambleCalls, 0)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-main"])
    }

    func testPreambleOffPlaysOnlyTheReply() async {
        settings.speaksPreamble = false
        await pipeline().speak(long)
        XCTAssertEqual(llm.preambleCalls, 0)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-main"])
    }

    func testMainReplyOffPlaysOnlyThePreamble() async {
        settings.speaksMainReply = false
        await pipeline().speak(long)
        XCTAssertEqual(llm.summaryCalls, 0)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-mono"])
        XCTAssertEqual(players.count, 1)
    }

    func testBothOffSpeaksNothingAndCallsNoLLM() async {
        settings.speaksPreamble = false
        settings.speaksMainReply = false
        await pipeline().speak(long)
        XCTAssertTrue(llm.calls.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
    }

    func testPreambleSynthesisFailureStillPlaysTheReply() async {
        provider.failOnTextContaining = "Oh joy"
        await pipeline().speak(long)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-main"])
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].url, provider.calls[0].url)
    }

    func testLLMIsBuiltOncePerReply() async {
        let pipeline = pipeline()
        await pipeline.speak(long)
        await pipeline.speak(long)
        XCTAssertEqual(makeLLMCalls, 2)
    }

    func testAllSynthesisFailingEnqueuesNothing() async {
        provider.failAll = true
        await pipeline().speak(long)
        XCTAssertTrue(players.isEmpty)
        XCTAssertFalse(queue.isPlaying)
    }

    func testClipsFinishedAfterStopAreDiscarded() async {
        let pipeline = pipeline(provider: StopsMidSynthesisProvider(queue: queue))
        await pipeline.speak(long)
        XCTAssertTrue(players.isEmpty)
    }

    // MARK: - Provider per profile

    private lazy var second = RecordingProvider(name: "second", maxMainCharacters: 20, markupHint: "You may use [sigh].")
    private lazy var registry = ProviderRegistry([provider, second])

    /// Finishing a clip starts the next, so finish until the queue is idle.
    private func drainQueue() {
        while queue.isPlaying { players.last?.finish() }
    }

    private func registryPipeline() -> SpeechPipeline {
        let llm = llm
        return SpeechPipeline(registry: registry, queue: queue, settings: settings) { _ in llm }
    }

    func testProfileProviderIsUsedForReplyAndQuipAndDefaultOtherwise() async {
        let pi = settings.addProfile(name: "pi")
        settings.setProvider(id: "second", in: pi.id)
        let pipeline = registryPipeline()

        await pipeline.speak(long, profile: "pi")
        XCTAssertEqual(second.calls.count, 2)
        XCTAssertTrue(provider.calls.isEmpty)
        drainQueue()

        await pipeline.quip(profile: "pi")
        XCTAssertEqual(second.calls.count, 3)
        XCTAssertTrue(provider.calls.isEmpty)
        drainQueue()

        await pipeline.speak(long)
        XCTAssertEqual(provider.calls.count, 2, "the default profile has no provider, so the registry's default")
        XCTAssertEqual(second.calls.count, 3)
    }

    func testProfileProviderSuppliesTheCapAndTheMarkupHint() async {
        settings.setProvider(id: "second", in: "default")
        llm.summaryScript = { _ in "A summary that is longer than twenty characters" }
        await registryPipeline().speak(long)
        let main = second.calls.first { $0.voice == "v-main" }
        XCTAssertLessThanOrEqual(main!.text.count, 21, "capped at the second provider's 20 plus the ellipsis")
        XCTAssertTrue(llm.calls.first { $0.system.contains("Compress") }!.system.hasSuffix("You may use [sigh]."))
    }

    // MARK: - Chunks (blether-vNbF9)

    func testAChunkingProviderSpeaksTheReplyInOrderedChunksAndArmsAfterTheLast() async {
        settings.listensAfterReply = true
        settings.speaksPreamble = false
        let chunking = RecordingProvider(speaksInChunks: true)
        llm.summaryScript = { _ in "First paragraph.\n\nSecond one." }
        await pipeline(provider: chunking).speak(long, session: session)

        XCTAssertEqual(chunking.calls.map(\.text), ["First paragraph.", "Second one."])
        XCTAssertEqual(chunking.calls.map(\.voice), ["v-main", "v-main"])
        XCTAssertEqual(players.map(\.url), [chunking.calls[0].url])
        players[0].finish()
        XCTAssertEqual(ears.armed, [], "not after the first chunk")
        XCTAssertEqual(players.map(\.url), chunking.calls.map(\.url))
        players[1].finish()
        XCTAssertEqual(ears.armed, [session])
    }

    func testOtherProvidersKeepTheReplyWhole() async {
        settings.speaksPreamble = false
        llm.summaryScript = { _ in "First paragraph.\n\nSecond one." }
        await pipeline().speak(long)
        XCTAssertEqual(provider.calls.map(\.text), ["First paragraph.\n\nSecond one."])
    }

    func testChunksKeepTheReplyToneAndThePreambleStaysWhole() {
        let clips = [PlannedClip(text: "Oh. Joy.", role: .monologue), PlannedClip(text: "One.\nTwo.", role: .main, tone: .sarcasm)]
        XCTAssertEqual(SpeechPipeline.chunked(clips), [
            PlannedClip(text: "Oh. Joy.", role: .monologue),
            PlannedClip(text: "One.", role: .main, tone: .sarcasm),
            PlannedClip(text: "Two.", role: .main, tone: .sarcasm),
        ])
    }

    // MARK: - Tone

    func testToneFromTheLLMReachesTheReplyClipOnly() async {
        settings.toneSource = .llm
        llm.toneScript = { _ in #"{"style": "confident"}"# }
        await pipeline().speak(long)
        XCTAssertEqual(llm.toneCalls, 1)
        XCTAssertEqual(provider.calls.first { $0.voice == "v-main" }?.tone, .confident)
        XCTAssertNil(provider.calls.first { $0.voice == "v-mono" }?.tone)
    }

    func testToneOffMakesNoClassifierCallAndTheQuipCarriesNone() async {
        await pipeline().speak(long)
        XCTAssertEqual(llm.toneCalls, 0)
        XCTAssertEqual(Set(provider.calls.map(\.tone)), [nil])
        drainQueue()
        settings.toneSource = .llm
        await pipeline().quip()
        XCTAssertEqual(llm.toneCalls, 0)
        XCTAssertNil(provider.calls.last?.tone)
    }

    // MARK: - Notifications

    func testIdleQueueQuipsInTheNotificationVoiceAndLanguage() async {
        await pipeline().quip()

        XCTAssertEqual(llm.quipCalls, 1)
        XCTAssertEqual(llm.calls.count, 1)
        XCTAssertEqual(provider.calls.map(\.voice), ["v-note"])
        XCTAssertEqual(provider.calls.map(\.text), ["Typical."])
        XCTAssertEqual(provider.calls.map(\.language), ["French"])
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].url, provider.calls[0].url)
        XCTAssertEqual(settings.recentQuips, ["Typical."])
    }

    func testALocalProviderQuipsInEnglishWhateverTheList() async {
        let local = RecordingProvider(name: "pocket")
        await pipeline(provider: local).quip()
        XCTAssertEqual(local.calls.map(\.language), ["English"], "the list says French")
    }

    func testQuipHistoryReachesThePromptAndGrows() async {
        settings.rememberQuip("Oh no.")
        await pipeline().quip()
        XCTAssertTrue(llm.calls[0].system.contains("- Oh no."))
        XCTAssertEqual(settings.recentQuips, ["Oh no.", "Typical."])
    }

    func testSpeakingOffDropsTheQuipWithoutSpendingAnything() async {
        settings.isEnabled = false
        await pipeline().quip()
        XCTAssertTrue(llm.calls.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertEqual(makeLLMCalls, 0)
    }

    func testNotificationsOffDropsTheQuip() async {
        settings.speaksNotifications = false
        await pipeline().quip()
        XCTAssertTrue(llm.calls.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertEqual(makeLLMCalls, 0)
    }

    func testBusyQueueDropsTheQuipBeforeAnyLLMWork() async {
        queue.enqueue(makeTestClip())
        await pipeline().quip()
        XCTAssertTrue(llm.calls.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertEqual(makeLLMCalls, 0)
        XCTAssertEqual(players.count, 1, "only the clip that was already there")
    }

    func testNamedProfileQuipsInItsOwnVoice() async {
        let pi = settings.addProfile(name: "pi")
        settings.updateRoles([.notification: RoleSettings(personaID: nil, voiceID: "pi-note")], in: pi.id)
        await pipeline().quip(profile: "PI")
        XCTAssertEqual(provider.calls.map(\.voice), ["pi-note"])
        XCTAssertTrue(llm.calls[0].system.contains("in the voice of: a coding assistant."), "no persona on that profile")
    }

    func testEmptyLLMReplySynthesisesNothingAndRemembersNothing() async {
        llm.quipScript = { _ in "" }
        await pipeline().quip()
        XCTAssertEqual(llm.quipCalls, 1)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertEqual(settings.recentQuips, [])
        XCTAssertTrue(players.isEmpty)
    }

    func testAudioStartingDuringSynthesisDropsTheQuipAndItsFile() async {
        let intruder = StartsPlaybackMidSynthesisProvider(queue: queue)
        await pipeline(provider: intruder).quip()
        XCTAssertEqual(players.count, 1, "the intruding clip plays, the quip does not")
        XCTAssertEqual(intruder.urls.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: intruder.urls[0].path), "the dropped quip's file is deleted")
        XCTAssertEqual(settings.recentQuips, ["Typical."], "remembered even though dropped, it was generated")
    }
}
