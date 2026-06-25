import Foundation

final class DictationInferenceService: InferenceServing, @unchecked Sendable {
    private let sttClient: InferenceClient
    private let polishService: MLPolishService

    init(sttClient: InferenceClient, polishService: MLPolishService) {
        self.sttClient = sttClient
        self.polishService = polishService
    }

    func transcribeAndPolish(audioURL: URL) async throws -> (raw: String, polished: String) {
        let raw = try await sttClient.transcribe(audioURL: audioURL)
        let polished = try await polishService.polish(raw)
        return (raw, polished)
    }
}
