import Foundation
import XCTest
@testable import YouTalkingToMe

@MainActor
final class PipelineCoordinatorTests: XCTestCase {
    func testStartDictationSetsListeningWhenAudioStarts() {
        let audio = MockAudioCapture(startShouldThrow: false)
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(),
            polishService: MockPolishService(),
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()
        XCTAssertEqual(pipeline.overlayState, .listening)
        XCTAssertTrue(audio.didStart)
    }

    func testStartDictationIgnoresSecondPressWhileListening() {
        let audio = MockAudioCapture(startShouldThrow: false)
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(),
            polishService: MockPolishService(),
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()
        pipeline.startDictation()

        XCTAssertEqual(pipeline.overlayState, .listening)
        XCTAssertEqual(audio.startCount, 1)
    }

    func testStartDictationShowsErrorWhenAudioFails() {
        struct FakeError: Error {}
        let audio = MockAudioCapture(startShouldThrow: true, startError: FakeError())
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(),
            polishService: MockPolishService(),
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()

        let expectation = expectation(description: "error overlay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if case .error = pipeline.overlayState {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
    }

    func testEndDictationSuccessHidesOverlay() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: tmp.path, contents: Data())
        let audio = MockAudioCapture(stopURL: tmp)
        let stt = MockSTTClient(result: "bonjour")
        let polish = MockPolishService(result: "Bonjour.")
        let injector = MockTextInjector(shouldSucceed: true)
        let pipeline = PipelineCoordinator(
            sttClient: stt,
            polishService: polish,
            audioCapture: audio,
            textInjector: injector
        )

        pipeline.startDictation()
        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(pipeline.overlayState, .hidden)
        XCTAssertTrue(stt.didTranscribe)
        XCTAssertTrue(polish.didPolish)
        XCTAssertTrue(injector.didInject)
    }

    func testEndDictationEmptyAudioShowsError() async {
        let audio = MockAudioCapture(stopURL: nil)
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(),
            polishService: MockPolishService(),
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()
        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        if case .error(let message) = pipeline.overlayState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected error overlay, got \(pipeline.overlayState)")
        }
    }

    func testEndDictationEmptyTranscriptShowsError() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: tmp.path, contents: Data())
        let audio = MockAudioCapture(stopURL: tmp)
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(result: ""),
            polishService: MockPolishService(result: "   "),
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()
        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        if case .error = pipeline.overlayState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected error overlay for empty transcript")
        }
    }

    func testEndDictationInjectionFailureShowsError() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: tmp.path, contents: Data())
        let audio = MockAudioCapture(stopURL: tmp)
        let pipeline = PipelineCoordinator(
            sttClient: MockSTTClient(result: "hi"),
            polishService: MockPolishService(result: "Hi"),
            audioCapture: audio,
            textInjector: MockTextInjector(shouldSucceed: false)
        )

        pipeline.startDictation()
        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        if case .error = pipeline.overlayState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected error overlay for injection failure")
        }
    }
}

private final class MockSTTClient: STTServing, @unchecked Sendable {
    var result = "x"
    var didTranscribe = false
    var error: Error?

    init(result: String = "x") {
        self.result = result
    }

    func transcribe(audioURL: URL) async throws -> String {
        didTranscribe = true
        if let error {
            throw error
        }
        return result
    }
}

@MainActor
private final class MockPolishService: PolishServing {
    var result = "X"
    var didPolish = false
    var error: Error?

    init(result: String = "X") {
        self.result = result
    }

    func polish(_ rawText: String) async throws -> String {
        didPolish = true
        if let error {
            throw error
        }
        return result
    }
}

private final class MockAudioCapture: AudioCapturing {
    var startShouldThrow = false
    var startError: Error = DictationError.emptyAudio
    var stopURL: URL?
    var didStart = false
    var startCount = 0

    init(
        startShouldThrow: Bool = false,
        startError: Error = DictationError.emptyAudio,
        stopURL: URL? = URL(fileURLWithPath: "/tmp/test.wav")
    ) {
        self.startShouldThrow = startShouldThrow
        self.startError = startError
        self.stopURL = stopURL
    }

    func start() throws {
        startCount += 1
        didStart = true
        if startShouldThrow {
            throw startError
        }
    }

    func stop() -> URL? {
        stopURL
    }
}

@MainActor
private final class MockTextInjector: TextInjecting {
    var shouldSucceed = true
    var didInject = false

    init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    func inject(_ text: String) -> (success: Bool, method: TextInjectionMethod?) {
        didInject = true
        return (shouldSucceed, shouldSucceed ? .pasteboard : nil)
    }
}
