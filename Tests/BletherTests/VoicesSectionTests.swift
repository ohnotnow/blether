import XCTest
@testable import Blether

final class VoicesSectionTests: XCTestCase {
    func testQueryValueEscapesSpacesAndTheCharactersThatChangeMeaning() {
        XCTAssertEqual(VoicesSection.queryValue("Serious and stern"), "Serious%20and%20stern")
        XCTAssertEqual(VoicesSection.queryValue("a&b=c+d"), "a%26b%3Dc%2Bd")
        XCTAssertEqual(VoicesSection.queryValue("hermes"), "hermes")
    }
}
