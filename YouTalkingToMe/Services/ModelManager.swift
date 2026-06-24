import Foundation

final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var downloadStage: String = ""
    @Published var isDownloading = false
    @Published var isReady = false

    private let inferenceClient: InferenceClient

    init(inferenceClient: InferenceClient) {
        self.inferenceClient = inferenceClient
    }

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouTalkingToMe/models", isDirectory: true)
    }

    func ensureModels(tier: ModelTier) async throws {
        isDownloading = true
        downloadProgress = 0
        downloadStage = "Préparation..."

        try await inferenceClient.loadModels(tier: tier) { [weak self] stage, model, percent in
            DispatchQueue.main.async {
                self?.downloadStage = "\(stage): \(model)"
                self?.downloadProgress = percent
            }
        }

        await MainActor.run {
            isDownloading = false
            isReady = true
            downloadProgress = 1
            downloadStage = "Prêt"
        }
    }

    func modelsInstalled(for tier: ModelTier) -> Bool {
        isReady
    }
}
