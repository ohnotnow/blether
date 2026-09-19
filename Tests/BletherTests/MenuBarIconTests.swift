import AppKit
import XCTest
@testable import Blether

final class MenuBarIconTests: XCTestCase {
    /// A template image at the menubar's size, so it recolours with the bar and does not get scaled.
    func testIconsAreMenubarTemplates() {
        for enabled in [true, false] {
            let image = MenuBarIcon.image(enabled: enabled)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, MenuBarIcon.size)
            XCTAssertFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
    }

    /// The two states must draw differently, or the switch has no visible effect.
    func testOnAndOffDrawDifferently() throws {
        let on = try XCTUnwrap(MenuBarIcon.image(enabled: true).tiffRepresentation)
        let off = try XCTUnwrap(MenuBarIcon.image(enabled: false).tiffRepresentation)
        XCTAssertNotEqual(on, off)
        XCTAssertNotEqual(MenuBarIcon.image(enabled: true).accessibilityDescription, MenuBarIcon.image(enabled: false).accessibilityDescription)
    }
}
