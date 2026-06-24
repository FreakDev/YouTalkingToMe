import XCTest
@testable import YouTalkingToMe

final class InferenceMessageTests: XCTestCase {
    func testDecodeTranscribeAndPolishResult() throws {
        let json = """
        {"type":"result","command":"transcribe_and_polish","raw_text":"bonjour","text":"Bonjour."}
        """
        let message = try XCTUnwrap(InferenceMessage.decodeLine(json))
        XCTAssertEqual(message.type, "result")
        XCTAssertEqual(message.command, "transcribe_and_polish")
        XCTAssertEqual(message.rawText, "bonjour")
        XCTAssertEqual(message.text, "Bonjour.")
    }

    func testDecodeProgress() throws {
        let json = """
        {"type":"progress","stage":"download_stt","model":"mlx-community/whisper-small-mlx","percent":0.5}
        """
        let message = try XCTUnwrap(InferenceMessage.decodeLine(json))
        XCTAssertEqual(message.type, "progress")
        XCTAssertEqual(message.stage, "download_stt")
        XCTAssertEqual(message.model, "mlx-community/whisper-small-mlx")
        XCTAssertEqual(message.percent, 0.5)
    }

    func testDecodeError() throws {
        let json = """
        {"type":"error","message":"Something went wrong"}
        """
        let message = try XCTUnwrap(InferenceMessage.decodeLine(json))
        XCTAssertEqual(message.type, "error")
        XCTAssertEqual(message.message, "Something went wrong")
    }

    func testDecodePingResult() throws {
        let json = """
        {"type":"result","command":"ping","ok":true}
        """
        let message = try XCTUnwrap(InferenceMessage.decodeLine(json))
        XCTAssertEqual(message.command, "ping")
        XCTAssertEqual(message.ok, true)
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(InferenceMessage.decodeLine("{not valid json"))
        XCTAssertNil(InferenceMessage.decodeLine(""))
    }
}
