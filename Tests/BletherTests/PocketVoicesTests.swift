import XCTest
@testable import Blether

final class PocketVoicesTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("blether-pocket-voices-\(UUID().uuidString)", isDirectory: true)
    private lazy var store = PocketVoices(directory: directory)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).safetensors")
        try Data(contents.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The same rule as pocket_clone.py, so a file made there and named here get the same id.
    func testIdIsLowerCaseWithOneHyphenPerRunOfAnythingElse() {
        XCTAssertEqual(PocketVoices.id(for: "Danish Detective"), "danish-detective")
        XCTAssertEqual(PocketVoices.id(for: "  Café -- Noir! 2 "), "caf-noir-2")
        XCTAssertEqual(PocketVoices.id(for: "!!"), "")
    }

    func testDisplayNameMatchesTheHelpers() {
        XCTAssertEqual(PocketVoices.displayName(id: "danish-detective"), "Danish Detective")
    }

    func testNoFolderMeansNoVoices() {
        XCTAssertEqual(store.ids, [])
    }

    func testAddListsRemove() throws {
        XCTAssertEqual(try store.add(try file("b"), name: "Zed Voice"), "zed-voice")
        try store.add(try file("a"), name: "Alpha")
        XCTAssertEqual(store.ids, ["alpha", "zed-voice"])
        try store.remove(id: "alpha")
        XCTAssertEqual(store.ids, ["zed-voice"])
    }

    func testAddingTheSameNameReplacesTheFile() throws {
        try store.add(try file("old"), name: "Servalan")
        try store.add(try file("new"), name: "servalan")
        XCTAssertEqual(store.ids, ["servalan"])
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("servalan.safetensors"), encoding: .utf8), "new")
    }

    func testANameWithNoLettersOrDigitsIsRefused() throws {
        XCTAssertThrowsError(try store.add(try file("x"), name: "--"))
        XCTAssertEqual(store.ids, [])
    }

    func testStampOnlyForAddedVoices() throws {
        try store.add(try file("a"), name: "Alpha")
        XCTAssertNotNil(store.stamp(id: "alpha"))
        XCTAssertNil(store.stamp(id: "alba"))
    }
}
