import XCTest
@testable import Blether

@MainActor
final class FakePlayer: Player {
    let url: URL
    var onFinish: (() -> Void)?
    var played = false
    var stopped = false
    /// Set before enqueueing to simulate AVAudioPlayer.play() returning false.
    var refusesToPlay = false
    init(url: URL) { self.url = url }
    func play() -> Bool {
        played = true
        return !refusesToPlay
    }
    func stop() { stopped = true }
    func finish() { onFinish?() }
}

/// Hands the queue fake players and remembers them in creation order.
@MainActor
final class FakePlayers {
    private(set) var all: [FakePlayer] = []
    /// URLs whose player should refuse to start.
    var refusing: Set<URL> = []
    func make(_ url: URL) -> any Player {
        let player = FakePlayer(url: url)
        player.refusesToPlay = refusing.contains(url)
        all.append(player)
        return player
    }
}

/// Writes a throwaway clip file so the queue has something real to delete.
func makeTestClip() -> AudioClip {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("blether-test-\(UUID().uuidString).caf")
    FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    return AudioClip(url: url)
}

func fileExists(_ clip: AudioClip) -> Bool {
    FileManager.default.fileExists(atPath: clip.url.path)
}

@MainActor
final class PlaybackQueueTests: XCTestCase {
    private let fakes = FakePlayers()
    private var players: [FakePlayer] { fakes.all }
    private var queue: PlaybackQueue!

    override func setUp() {
        queue = PlaybackQueue(makePlayer: fakes.make)
    }

    func testThreeClipsPlayInOrderOneAtATime() {
        let clips = [makeTestClip(), makeTestClip(), makeTestClip()]
        clips.forEach { queue.enqueue($0) }

        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players[0].url, clips[0].url)
        XCTAssertTrue(queue.isPlaying)

        players[0].finish()
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].url, clips[1].url)
        XCTAssertFalse(fileExists(clips[0]))

        players[1].finish()
        XCTAssertEqual(players.count, 3)
        XCTAssertEqual(players[2].url, clips[2].url)

        players[2].finish()
        XCTAssertFalse(queue.isPlaying)
        XCTAssertTrue(clips.allSatisfy { !fileExists($0) })
    }

    func testOnFinishedFiresAfterThatClipEndsAndOnlyThatClip() {
        var fired: [String] = []
        queue.enqueue(makeTestClip(), onFinished: { fired.append("first") })
        queue.enqueue(makeTestClip())
        queue.enqueue(makeTestClip(), onFinished: { fired.append("third") })
        XCTAssertEqual(fired, [])
        players[0].finish()
        XCTAssertEqual(fired, ["first"])
        players[1].finish()
        XCTAssertEqual(fired, ["first"])
        players[2].finish()
        XCTAssertEqual(fired, ["first", "third"])
        XCTAssertFalse(queue.isPlaying)
    }

    func testOnFinishedDoesNotFireWhenStopKillsTheClip() {
        var fired = 0
        queue.enqueue(makeTestClip(), onFinished: { fired += 1 })
        queue.enqueue(makeTestClip(), onFinished: { fired += 1 })
        queue.stop()
        players[0].finish()
        XCTAssertEqual(fired, 0, "a reply the user killed must not open the ears")
    }

    func testStopKillsCurrentAndDropsTheRest() {
        let clips = [makeTestClip(), makeTestClip(), makeTestClip()]
        clips.forEach { queue.enqueue($0) }

        queue.stop()

        XCTAssertTrue(players[0].stopped)
        XCTAssertEqual(players.count, 1)
        XCTAssertFalse(queue.isPlaying)
        XCTAssertTrue(clips.allSatisfy { !fileExists($0) })
    }

    func testEnqueueAfterStopPlaysAgain() {
        queue.enqueue(makeTestClip())
        queue.stop()

        queue.enqueue(makeTestClip())

        XCTAssertEqual(players.count, 2)
        XCTAssertTrue(players[1].played)
        XCTAssertTrue(queue.isPlaying)
    }

    func testStaleGenerationClipIsDroppedAndDeleted() {
        let generation = queue.generation
        queue.stop()
        let clip = makeTestClip()

        queue.enqueue(clip, generation: generation)

        XCTAssertTrue(players.isEmpty)
        XCTAssertFalse(fileExists(clip))
    }

    func testPlayerThatRefusesToStartIsSkippedNotStuck() {
        let clips = [makeTestClip(), makeTestClip()]
        fakes.refusing = [clips[0].url]

        clips.forEach { queue.enqueue($0) }

        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].url, clips[1].url)
        XCTAssertTrue(queue.isPlaying)
        XCTAssertFalse(fileExists(clips[0]))

        players[1].finish()
        XCTAssertFalse(queue.isPlaying)
    }

    func testLastPlayerRefusingLeavesQueueIdle() {
        let clip = makeTestClip()
        fakes.refusing = [clip.url]

        queue.enqueue(clip)

        XCTAssertFalse(queue.isPlaying)
        XCTAssertFalse(fileExists(clip))
    }

    func testCurrentGenerationClipPlays() {
        let clip = makeTestClip()
        queue.enqueue(clip, generation: queue.generation)
        XCTAssertEqual(players.count, 1)
    }
}
