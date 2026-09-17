import XCTest
@testable import Blether

/// Records every synthesis request and can be told to fail for texts containing a marker.
private final class RecordingProvider: Provider, @unchecked Sendable {
    struct Call: Equatable { let text: String; let voice: String; let url: URL }
    let name = "recording"
    let maxMainCharacters = 800
    private let lock = NSLock()
    private var recorded: [Call] = []
    var failOnTextContaining: String?
    var failAll = false
    var calls: [Call] { lock.withLock { recorded } }

    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String) async throws -> AudioClip {
        if failAll { throw ProviderError.noAudio }
        if let marker = failOnTextContaining, text.contains(marker) { throw ProviderError.noAudio }
        let clip = makeTestClip()
        lock.withLock { recorded.append(Call(text: text, voice: voice, url: clip.url)) }
        return clip
    }
}

/// Simulates the user pressing stop while synthesis is still running.
private struct StopsMidSynthesisProvider: Provider {
    let name = "stopping"
    let maxMainCharacters = 800
    let queue: PlaybackQueue
    func voices() async throws -> [Voice] { [] }
    func synthesise(_ text: String, voice: String) async throws -> AudioClip {
        await queue.stop()
        return makeTestClip()
    }
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
        s.roles = [.main: RoleSettings(personaID: nil, voiceID: "v-main"), .monologue: RoleSettings(personaID: "marvin", voiceID: "v-mono")]
        return s
    }()
    private lazy var queue = PlaybackQueue(makePlayer: fakes.make)
    private var makeLLMCalls = 0
    private let long = Array(repeating: "word", count: 70).joined(separator: " ")

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func pipeline(provider: (any Provider)? = nil) -> SpeechPipeline {
        let llm = llm
        return SpeechPipeline(provider: provider ?? self.provider, queue: queue, settings: settings) { [weak self] _ in
            MainActor.assumeIsolated { self?.makeLLMCalls += 1 }
            return llm
        }
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
}
