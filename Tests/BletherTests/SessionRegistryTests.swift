import XCTest
@testable import Blether

final class SessionRegistryTests: XCTestCase {
    private var registry = SessionRegistry<String>()

    func testExactSessionIDWins() {
        registry.register("a", key: SessionKey(id: "s-1", pid: 1))
        registry.register("b", key: SessionKey(id: "s-2", pid: 2))
        XCTAssertEqual(registry.lookup(SessionKey(id: "s-2", pid: nil)), "b")
        XCTAssertEqual(registry.lookup(SessionKey(id: "s-1", pid: 2)), "a", "the id beats a conflicting pid")
    }

    func testPidIsTheFallbackForAResumedSession() {
        registry.register("a", key: SessionKey(id: "fresh-id", pid: 1))
        registry.register("b", key: SessionKey(id: "other", pid: 2))
        XCTAssertEqual(registry.lookup(SessionKey(id: "old-id", pid: 1)), "a")
    }

    func testASingleConnectionAnswersAnythingAndTwoAnswerNothingUnknown() {
        registry.register("a", key: SessionKey(id: "s-1", pid: 1))
        XCTAssertEqual(registry.lookup(SessionKey(id: "unknown", pid: 99)), "a")
        XCTAssertEqual(registry.lookup(SessionKey(id: nil, pid: nil)), "a")
        registry.register("b", key: SessionKey(id: "s-2", pid: 2))
        XCTAssertNil(registry.lookup(SessionKey(id: "unknown", pid: 99)))
    }

    func testALaterConnectionWithTheSameIDWinsWithoutRemovingTheFirst() {
        registry.register("a", key: SessionKey(id: "s-1", pid: 1))
        registry.register("b", key: SessionKey(id: "s-1", pid: 1))
        XCTAssertEqual(registry.count, 2)
        XCTAssertEqual(registry.lookup(SessionKey(id: "s-1", pid: nil)), "b")
        registry.remove("b")
        XCTAssertEqual(registry.lookup(SessionKey(id: "s-1", pid: nil)), "a", "the first still serves once the second closes")
    }

    func testRemoveForgetsTheConnection() {
        registry.register("a", key: SessionKey(id: "s-1", pid: 1))
        registry.remove("a")
        XCTAssertEqual(registry.count, 0)
        XCTAssertNil(registry.lookup(SessionKey(id: "s-1", pid: 1)))
    }
}
