import Foundation
import XCTest
@testable import YouTalkingToMe

final class AppModelsTests: XCTestCase {
    func testModelTierMatchesModelsJSON() throws {
        let jsonURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("inference/models.json")

        let data = try Data(contentsOf: jsonURL)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tiers = try XCTUnwrap(payload?["tiers"] as? [String: [String: String]])

        for tier in ModelTier.allCases {
            let config = try XCTUnwrap(tiers[tier.rawValue])
            XCTAssertEqual(tier.sttModel, config["stt"])
            XCTAssertEqual(tier.polishModel, config["polish"])
        }
    }

    func testDictationErrorDescriptionsAreNonEmpty() {
        let errors: [DictationError] = [
            .inferenceNotReady,
            .emptyAudio,
            .emptyTranscript,
            .injectionFailed,
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
