import Foundation

@MainActor
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var downloadStage: String = ""
    @Published var isDownloading = false
    @Published var isReady = false
    @Published private(set) var tierStatuses: [TierInstallStatus] = []

    private let inferenceClient: InferenceClient
    private let polishService: MLPolishService
    private var loadedTier: ModelTier?

    init(inferenceClient: InferenceClient, polishService: MLPolishService) {
        self.inferenceClient = inferenceClient
        self.polishService = polishService
        refreshModelStatuses()
    }

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouTalkingToMe/models", isDirectory: true)
    }

    func ensureModels(tier: ModelTier) async throws {
        refreshModelStatuses()
        if shouldSkipLoading(tier: tier) {
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadStage = "Préparation..."

        do {
            try await inferenceClient.loadModels(tier: tier) { stage, model, percent in
                Task { @MainActor [weak self] in
                    self?.downloadStage = "\(stage): \(model)"
                    self?.downloadProgress = percent * 0.5
                }
            }

            try await polishService.loadModel(tier: tier) { stage, model, percent in
                Task { @MainActor [weak self] in
                    self?.downloadStage = "\(stage): \(model)"
                    self?.downloadProgress = 0.5 + (percent * 0.5)
                }
            }

            downloadProgress = 1
            downloadStage = "Prêt"
            isDownloading = false
            loadedTier = tier
            isReady = true
            refreshModelStatuses()
        } catch {
            isDownloading = false
            throw error
        }
    }

    func refreshModelStatuses() {
        tierStatuses = ModelTier.allCases.map { tier in
            TierInstallStatus(
                tier: tier,
                sttInstalled: isModelInstalled(repo: tier.sttModel),
                polishInstalled: isModelInstalled(repo: tier.polishModel)
            )
        }
    }

    func isModelInstalled(repo: String) -> Bool {
        isModelInstalled(repo: repo, cacheRoot: modelsDirectory)
    }

    func isModelInstalled(repo: String, cacheRoot: URL) -> Bool {
        let snapshotsDirectory = cacheRoot
            .appendingPathComponent(Self.cacheDirectoryName(for: repo), isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshotFolders = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return snapshotFolders.contains { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return !files.isEmpty
        }
    }

    func deleteTier(_ tier: ModelTier, activeTier: ModelTier) throws {
        for repo in [tier.sttModel, tier.polishModel] {
            let cacheDirectory = cacheDirectory(for: repo)
            guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
                continue
            }
            try FileManager.default.removeItem(at: cacheDirectory)
        }

        if tier == activeTier {
            isReady = false
            loadedTier = nil
            polishService.unload()
        }
        refreshModelStatuses()
    }

    nonisolated static func cacheDirectoryName(for repo: String) -> String {
        "models--" + repo.replacingOccurrences(of: "/", with: "--")
    }

    private func shouldSkipLoading(tier: ModelTier) -> Bool {
        guard let status = tierStatuses.first(where: { $0.tier == tier }) else {
            return false
        }
        return status.isFullyInstalled && isReady && loadedTier == tier
    }

    private func cacheDirectory(for repo: String) -> URL {
        modelsDirectory.appendingPathComponent(Self.cacheDirectoryName(for: repo), isDirectory: true)
    }
}
