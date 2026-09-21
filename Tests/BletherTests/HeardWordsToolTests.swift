import XCTest
@testable import Blether

@MainActor
final class HeardWordsToolTests: XCTestCase {
    private let suite = "uk.ohnotnow.blether.tests.\(UUID().uuidString)"
    private lazy var settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, keychain: KeychainStore(service: "uk.ohnotnow.blether.tests.heard-words"))

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func testListOnEmptySaysSo() {
        XCTAssertEqual(HeardWordsTool.run("list", words: [], settings: settings), "No heard words yet.")
    }

    func testAddAppendsAndReportsTheWholeList() {
        settings.heardWords = "laravel"
        XCTAssertEqual(HeardWordsTool.run("add", words: [" livewire ", "CVE"], settings: settings), "Added: livewire, CVE. Heard words: laravel, livewire, CVE.")
        XCTAssertEqual(settings.heardWordList, ["laravel", "livewire", "CVE"])
    }

    func testDuplicatesAreIgnoredRegardlessOfCase() {
        settings.heardWords = "laravel"
        XCTAssertEqual(HeardWordsTool.run("add", words: ["Laravel"], settings: settings), "Nothing added. Heard words: laravel.")
    }

    func testShortWordsAreRefusedAndNamed() {
        XCTAssertEqual(HeardWordsTool.run("add", words: ["id", "env", ""], settings: settings), "Added: env. Refused as too short to match safely: id. Heard words: env.")
    }
}
