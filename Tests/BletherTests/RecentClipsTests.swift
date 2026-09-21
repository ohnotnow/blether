import XCTest
@testable import Blether

final class RecentClipsTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("blether-recent-\(UUID().uuidString)", isDirectory: true)
    private lazy var recent = RecentClips(directory: directory)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func testKeepCopiesWithTimeRoleAndExtensionAndLeavesTheOriginal() throws {
        let clip = makeTestClip()
        try recent.keep(clip, role: .main, now: Date(timeIntervalSince1970: 0))
        let kept = try names()
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].hasSuffix(" reply.caf"), kept[0])
        XCTAssertTrue(kept[0].hasPrefix("1970-01-01 "), "local time of the epoch, whatever the zone: \(kept[0])")
        XCTAssertTrue(fileExists(clip), "the queue deletes the original later, not us")
    }

    func testSameSecondSameRoleGetsANumber() throws {
        let when = Date(timeIntervalSince1970: 0)
        try recent.keep(makeTestClip(), role: .main, now: when)
        try recent.keep(makeTestClip(), role: .main, now: when)
        XCTAssertEqual(try names().map { String($0.dropFirst(20)) }, ["reply 2.caf", "reply.caf"])
    }

    func testTheEleventhClipDropsTheOldest() throws {
        for i in 0..<11 {
            try recent.keep(makeTestClip(), role: i == 0 ? .monologue : .notification, now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        let kept = try names()
        XCTAssertEqual(kept.count, RecentClips.limit)
        XCTAssertFalse(kept.contains { $0.hasSuffix(" preamble.caf") }, "the first one, the oldest, is gone")
    }
}
