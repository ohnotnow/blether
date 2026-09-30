import XCTest
@testable import Blether

final class ChimeTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("blether-chime-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) -> URL {
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func testAFileIsAListOfOne() {
        let file = touch("quote.mp3")
        XCTAssertEqual(Chime.clips(at: file), [file])
    }

    func testAFolderIsItsAudioFilesOnly() {
        _ = touch("hey-there-1.mp3")
        _ = touch("hey-there-2.aiff")
        _ = touch("notes.txt")
        XCTAssertEqual(Set(Chime.clips(at: folder).map(\.lastPathComponent)), ["hey-there-1.mp3", "hey-there-2.aiff"])
    }

    func testAMissingPathHasNoClips() {
        XCTAssertEqual(Chime.clips(at: folder.appendingPathComponent("gone")), [])
    }

    func testAPathIsCustomAndANameIsBuiltIn() {
        XCTAssertTrue(Chime.isCustom("/Volumes/Sounds/hey-there"))
        XCTAssertFalse(Chime.isCustom("Glass"))
    }

    func testTheBuiltInSoundsIncludeTheDefault() {
        XCTAssertTrue(Chime.systemSounds().contains(Chime.defaultSound))
    }
}
