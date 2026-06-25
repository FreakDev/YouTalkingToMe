import Foundation

@MainActor
final class PipelineCoordinator: ObservableObject {
    private static let errorDisplayDuration: TimeInterval = 8

    private enum Phase {
        case idle
        case listening
        case processing
    }

    @Published var overlayState: OverlayState = .hidden

    private let audioCapture: any AudioCapturing
    private let textInjector: any TextInjecting
    private let sttClient: any STTServing
    private let polishService: any PolishServing
    private var phase: Phase = .idle
    private var errorDismissToken = 0

    init(
        sttClient: any STTServing,
        polishService: any PolishServing,
        audioCapture: any AudioCapturing = AudioCapture(),
        textInjector: any TextInjecting = TextInjector()
    ) {
        self.sttClient = sttClient
        self.polishService = polishService
        self.audioCapture = audioCapture
        self.textInjector = textInjector
    }

    func startDictation() {
        guard phase == .idle else { return }
        phase = .listening
        overlayState = .listening
        do {
            try audioCapture.start()
            AppLogger.info("Dictation started")
        } catch {
            phase = .idle
            showError(error, context: "Audio capture failed")
        }
    }

    func showUserMessage(_ message: String) {
        overlayState = .error(message)
        scheduleErrorDismiss()
    }

    func endDictation() {
        guard phase == .listening else { return }
        phase = .processing
        overlayState = .processing
        AppLogger.info("Dictation ended, processing...")

        Task {
            defer { phase = .idle }
            do {
                guard let audioURL = audioCapture.stop() else {
                    throw DictationError.emptyAudio
                }

                AppLogger.debug("Audio captured at \(audioURL.path)")
                let raw = try await sttClient.transcribe(audioURL: audioURL)
                let polished = try await polishService.polish(raw)
                try FileManager.default.removeItem(at: audioURL)

                AppLogger.debug("Transcription raw length: \(raw.count), polished length: \(polished.count)")

                let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw DictationError.emptyTranscript
                }
                AppLogger.debug("Polished text: \(trimmed)")

                let injection = textInjector.inject(trimmed)
                guard injection.success else {
                    throw DictationError.injectionFailed
                }

                AppLogger.info("Dictation completed via \(injection.method?.rawValue ?? "unknown")")
                overlayState = .hidden
            } catch {
                showError(error, context: "Dictation pipeline failed")
            }
        }
    }

    private func showError(_ error: Error, context: String) {
        let message = error.localizedDescription
        AppLogger.error(context, error: error)
        overlayState = .error(message)
        scheduleErrorDismiss()
    }

    private func scheduleErrorDismiss() {
        errorDismissToken += 1
        let token = errorDismissToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorDisplayDuration) { [weak self] in
            guard let self, self.errorDismissToken == token else { return }
            if case .error = self.overlayState {
                self.overlayState = .hidden
            }
        }
    }
}
