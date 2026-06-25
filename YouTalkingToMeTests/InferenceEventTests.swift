import XCTest
@testable import YouTalkingToMe

final class InferenceEventTests: XCTestCase {
    func testDecodeTranscribeResult() throws {
        let json = """
        {"type":"result","command":"transcribe","text":"Bonjour.","request_id":"abc-123"}
        """
        let event = try XCTUnwrap(InferenceEvent.decodeLine(json))
        XCTAssertEqual(event, .transcribeResult(text: "Bonjour.", requestID: "abc-123"))
    }

    func testDecodeProgress() throws {
        let json = """
        {"type":"progress","stage":"download_stt","model":"mlx-community/whisper-small-mlx","percent":0.5}
        """
        let event = try XCTUnwrap(InferenceEvent.decodeLine(json))
        XCTAssertEqual(
            event,
            .progress(
                stage: "download_stt",
                model: "mlx-community/whisper-small-mlx",
                percent: 0.5,
                requestID: nil
            )
        )
    }

    func testDecodeError() throws {
        let json = """
        {"type":"error","message":"Something went wrong","request_id":"req-1"}
        """
        let event = try XCTUnwrap(InferenceEvent.decodeLine(json))
        XCTAssertEqual(event, .error(message: "Something went wrong", requestID: "req-1"))
    }

    func testDecodePingResult() throws {
        let json = """
        {"type":"result","command":"ping","ok":true,"request_id":"ping-1"}
        """
        let event = try XCTUnwrap(InferenceEvent.decodeLine(json))
        XCTAssertEqual(event, .pingResult(ok: true, requestID: "ping-1"))
    }

    func testDecodeLoadModelsResult() throws {
        let json = """
        {"type":"result","command":"load_models","tier":"fast","request_id":"load-1"}
        """
        let event = try XCTUnwrap(InferenceEvent.decodeLine(json))
        XCTAssertEqual(event, .loadModelsResult(tier: "fast", requestID: "load-1"))
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(InferenceEvent.decodeLine("{not valid json"))
        XCTAssertNil(InferenceEvent.decodeLine(""))
    }
}
