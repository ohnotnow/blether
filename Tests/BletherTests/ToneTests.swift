import XCTest
@testable import Blether

final class ToneTests: XCTestCase {
    func testTheNineInOrderWithCriteria() {
        XCTAssertEqual(Tone.allCases.map(\.rawValue), ["neutral", "sarcasm", "confused", "shameful", "sad", "jealousy", "frustrated", "curious", "confident"])
        for tone in Tone.allCases { XCTAssertFalse(tone.criterion.isEmpty, tone.rawValue) }
    }

    func testClassifierPromptNamesEveryTone() {
        for tone in Tone.allCases { XCTAssertTrue(Prompts.toneClassifier.contains("- \(tone.rawValue): \(tone.criterion)")) }
        XCTAssertTrue(Prompts.toneClassifier.contains(#"{"style": "<one of the above>"}"#))
    }
}
