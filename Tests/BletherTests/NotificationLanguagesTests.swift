import XCTest
@testable import Blether

final class NotificationLanguagesTests: XCTestCase {
    func testParsesNamesWeightsBlanksAndBadWeights() {
        let parsed = NotificationLanguages(parsing: "French 5\n\nSpanish\nbroken -2\n  Chinese (Simplified) 3 \nzero 0")
        XCTAssertEqual(parsed.entries, [
            .init(name: "French", weight: 5),
            .init(name: "Spanish", weight: 1),
            .init(name: "Chinese (Simplified)", weight: 3),
        ])
    }

    func testEmptyOrBlankTextFallsBackToEnglish() {
        XCTAssertEqual(NotificationLanguages(parsing: "").entries, [NotificationLanguages.fallback])
        XCTAssertEqual(NotificationLanguages(parsing: " \n\n  ").entries, [NotificationLanguages.fallback])
        XCTAssertEqual(NotificationLanguages(parsing: "nothing 0").entries, [NotificationLanguages.fallback])
    }

    func testANameThatIsOnlyANumberIsANameNotAWeight() {
        XCTAssertEqual(NotificationLanguages(parsing: "1984").entries, [.init(name: "1984", weight: 1)])
    }

    func testPickMapsTheRandomValueOntoWeightedRanges() {
        let languages = NotificationLanguages(parsing: "A 1\nB 3")
        var totals: [Int] = []
        let picks = (0..<4).map { value in languages.pick { total in totals.append(total); return value } }
        XCTAssertEqual(picks, ["A", "B", "B", "B"])
        XCTAssertEqual(totals, [4, 4, 4, 4])
    }

    @MainActor func testDefaultListParsesToSevenLanguages() {
        let parsed = NotificationLanguages(parsing: AppSettings.defaultNotificationLanguages)
        XCTAssertEqual(parsed.entries.map(\.name), ["English", "French", "Spanish", "Italian", "Portuguese", "Hindi", "Chinese (Simplified)"])
        XCTAssertEqual(parsed.entries.map(\.weight), [1, 5, 5, 5, 5, 5, 5])
    }
}
