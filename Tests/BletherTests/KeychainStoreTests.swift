import XCTest
@testable import Blether

final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "uk.ohnotnow.blether.tests")
    private let account = "test-\(UUID().uuidString)"

    override func tearDownWithError() throws {
        try store.delete(account: account)
    }

    func testSaveReadOverwriteDelete() throws {
        XCTAssertNil(try store.secret(account: account))
        try store.save("first", account: account)
        XCTAssertEqual(try store.secret(account: account), "first")
        try store.save("second", account: account)
        XCTAssertEqual(try store.secret(account: account), "second")
        try store.delete(account: account)
        XCTAssertNil(try store.secret(account: account))
    }

    func testDeletingAMissingItemDoesNotThrow() {
        XCTAssertNoThrow(try store.delete(account: "never-saved-\(UUID().uuidString)"))
    }
}
