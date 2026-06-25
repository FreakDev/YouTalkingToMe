import Foundation

@MainActor
final class PipelineCoordinator: ObservableObject {
    private static let errorDisplayDuration: TimeInterval = 8

    @Published var overlayState: OverlayState = .hidden

    private let audioCapture: any AudioCapturing
    private let textInjector: any TextInjecting
    private let inferenceClient: any InferenceServing
    private let settingsStore: SettingsStore

    init(
        inferenceClient: any InferenceServing,
        settingsStore: SettingsStore,
        audioCapture: any AudioCapturing = AudioCapture(),
        textInjector: any TextInjecting = TextInjector()
    ) {
        self.inferenceClient = inferenceClient
        self.settingsStore = settingsStore
        self.audioCapture = audioCapture
        self.textInjector = textInjector
    }

    func startDictation() {
        overlayState = .listening
        do {
            try audioCapture.start()
            AppLogger.info("Dictation started")
        } catch {
            showError(error, context: "Audio capture failed")
        }
    }

    func showUserMessage(_ message: String) {
        Task { @MainActor in
            overlayState = .error(message)
            scheduleErrorDismiss()
        }
    }

    func endDictation() {
        overlayState = .processing
        AppLogger.info("Dictation ended, processing...")

        Task {
            do {
                guard let audioURL = audioCapture.stop() else {
                    throw DictationError.emptyAudio
                }

                AppLogger.debug("Audio captured at \(audioURL.path)")
                let result = try await inferenceClient.transcribeAndPolish(audioURL: audioURL)
                try FileManager.default.removeItem(at: audioURL)

                AppLogger.debug("Transcription raw length: \(result.raw.count), polished length: \(result.polished.count)")

                let polished = result.polished.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !polished.isEmpty else {
                    throw DictationError.emptyTranscript
                }
                AppLogger.debug("Polished text: \(polished)")

                let injection = await MainActor.run {
                    textInjector.inject(polished)
                }
                guard injection.success else {
                    throw DictationError.injectionFailed
                }

                AppLogger.info("Dictation completed via \(injection.method?.rawValue ?? "unknown")")
                await MainActor.run {
                    overlayState = .hidden
                }
            } catch {
                showError(error, context: "Dictation pipeline failed")
            }
        }
    }

    private func showError(_ error: Error, context: String) {
        let message = error.localizedDescription
        AppLogger.error(context, error: error)

        Task { @MainActor in
            overlayState = .error(message)
            scheduleErrorDismiss()
        }
    }

    private func scheduleErrorDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorDisplayDuration) { [weak self] in
            if case .error = self?.overlayState {
                self?.overlayState = .hidden
            }
        }
    }
}
