import XCTest
@testable import Blether

final class AppRuntimeTests: XCTestCase {
    func testIsRunningUnitTestsIsTrueUnderXCTest() {
        XCTAssertTrue(AppRuntime.isRunningUnitTests)
    }
}
