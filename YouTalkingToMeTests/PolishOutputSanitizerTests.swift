import XCTest
@testable import YouTalkingToMe

final class PolishOutputSanitizerTests: XCTestCase {
    func testStripWrappingQuotesRemovesOuterPairs() {
        XCTAssertEqual(PolishOutputSanitizer.stripWrappingQuotes(#""Bonjour.""#), "Bonjour.")
        XCTAssertEqual(PolishOutputSanitizer.stripWrappingQuotes("«Bonjour.»"), "Bonjour.")
    }

    func testStripThinkingChannelsKeepsContentBlock() {
        let raw = "<|channel>thought\nhmm\n<channel|><|channel>content\nBonjour.\n<channel|>"
        XCTAssertEqual(PolishOutputSanitizer.stripThinkingChannels(raw), "Bonjour.")
    }

    func testSanitizeAppliesBothSteps() {
        let raw = "<|channel>content\n\"Bonjour.\"\n<channel|>"
        XCTAssertEqual(PolishOutputSanitizer.sanitize(raw), "Bonjour.")
    }
}
