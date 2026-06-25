import Foundation
import XCTest
@testable import YouTalkingToMe

@MainActor
final class PipelineCoordinatorTests: XCTestCase {
    private var settingsStore: SettingsStore!

    override func setUp() {
        let suiteName = "YouTalkingToMeTests.Pipeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        settingsStore = SettingsStore(defaults: defaults)
    }

    func testStartDictationSetsListeningWhenAudioStarts() {
        let audio = MockAudioCapture(startShouldThrow: false)
        let pipeline = PipelineCoordinator(
            inferenceClient: MockInferenceClient(),
            settingsStore: settingsStore,
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

        pipeline.startDictation()
        XCTAssertEqual(pipeline.overlayState, .listening)
        XCTAssertTrue(audio.didStart)
    }

    func testStartDictationShowsErrorWhenAudioFails() {
        struct FakeError: Error {}
        let audio = MockAudioCapture(startShouldThrow: true, startError: FakeError())
        let pipeline = PipelineCoordinator(
            inferenceClient: MockInferenceClient(),
            settingsStore: settingsStore,
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
        let inference = MockInferenceClient(result: (raw: "bonjour", polished: "Bonjour."))
        let injector = MockTextInjector(shouldSucceed: true)
        let pipeline = PipelineCoordinator(
            inferenceClient: inference,
            settingsStore: settingsStore,
            audioCapture: audio,
            textInjector: injector
        )

        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(pipeline.overlayState, .hidden)
        XCTAssertTrue(inference.didTranscribe)
        XCTAssertTrue(injector.didInject)
    }

    func testEndDictationEmptyAudioShowsError() async {
        let audio = MockAudioCapture(stopURL: nil)
        let pipeline = PipelineCoordinator(
            inferenceClient: MockInferenceClient(),
            settingsStore: settingsStore,
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

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
        let inference = MockInferenceClient(result: (raw: "", polished: "   "))
        let pipeline = PipelineCoordinator(
            inferenceClient: inference,
            settingsStore: settingsStore,
            audioCapture: audio,
            textInjector: MockTextInjector()
        )

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
        let inference = MockInferenceClient(result: (raw: "hi", polished: "Hi"))
        let injector = MockTextInjector(shouldSucceed: false)
        let pipeline = PipelineCoordinator(
            inferenceClient: inference,
            settingsStore: settingsStore,
            audioCapture: audio,
            textInjector: injector
        )

        pipeline.endDictation()
        try? await Task.sleep(nanoseconds: 300_000_000)

        if case .error = pipeline.overlayState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected error overlay for injection failure")
        }
    }
}

private final class MockInferenceClient: InferenceServing, @unchecked Sendable {
    var result: (raw: String, polished: String) = (raw: "x", polished: "X")
    var didTranscribe = false
    var error: Error?

    init(result: (raw: String, polished: String) = (raw: "x", polished: "X")) {
        self.result = result
    }

    func transcribeAndPolish(audioURL: URL) async throws -> (raw: String, polished: String) {
        didTranscribe = true
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
