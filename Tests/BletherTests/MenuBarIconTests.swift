import AppKit
import XCTest
@testable import Blether

final class MenuBarIconTests: XCTestCase {
    /// A missing symbol draws a blank menubar item with no error, so pin both names here.
    func testBothMenuBarSymbolsResolve() {
        for enabled in [true, false] {
            let name = MenuBarIcon.name(enabled: enabled)
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testOffIconIsTheSlashedOne() {
        XCTAssertTrue(MenuBarIcon.name(enabled: false).hasSuffix(".slash"))
        XCTAssertFalse(MenuBarIcon.name(enabled: true).hasSuffix(".slash"))
    }
}
