import Foundation

@MainActor
final class TierSelectionModel: ObservableObject {
    @Published var selectedTier: ModelTier
    @Published var errorMessage: String?
    @Published private(set) var tierPendingDeletion: ModelTier?
    @Published private(set) var tierPendingDownload: ModelTier?

    private let settingsStore: SettingsStore
    private let modelManager: ModelManager
    private var isReloading = false
    private var isRevertingTierSelection = false

    init(settingsStore: SettingsStore, modelManager: ModelManager) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        selectedTier = settingsStore.settings.tier
    }

    var selectedTierStatus: TierInstallStatus? {
        modelManager.tierStatuses.first { $0.tier == selectedTier }
    }

    var isDownloadingFromNetwork: Bool {
        (isReloading || modelManager.isDownloading) && selectedTierStatus?.isFullyInstalled != true
    }

    var selectedTierIsAbsent: Bool {
        selectedTierStatus?.isFullyInstalled != true && !isDownloadingFromNetwork
    }

    var showsDownloadProgress: Bool {
        isDownloadingFromNetwork
    }

    func tierSelectionChanged(_ tier: ModelTier) {
        if isRevertingTierSelection {
            isRevertingTierSelection = false
            return
        }

        let status = modelManager.tierStatuses.first { $0.tier == tier }
        if status?.isFullyInstalled == true {
            reloadModels(for: tier)
        } else {
            tierPendingDownload = tier
        }
    }

    func confirmDownload() {
        guard let tier = tierPendingDownload else { return }
        reloadModels(for: tier)
        tierPendingDownload = nil
    }

    func cancelDownloadConfirmation() {
        guard tierPendingDownload != nil else { return }
        isRevertingTierSelection = true
        selectedTier = settingsStore.settings.tier
        tierPendingDownload = nil
    }

    func requestDelete(_ tier: ModelTier) {
        tierPendingDeletion = tier
    }

    func confirmDelete() {
        guard let tier = tierPendingDeletion else { return }
        deleteTier(tier)
        tierPendingDeletion = nil
    }

    func cancelDelete() {
        tierPendingDeletion = nil
    }

    func reloadModels(for tier: ModelTier) {
        isRevertingTierSelection = true
        selectedTier = tier
        tierPendingDownload = nil
        settingsStore.settings.tier = tier
        settingsStore.save()
        isReloading = true
        errorMessage = nil

        Task {
            do {
                try await modelManager.ensureModels(tier: tier)
                isReloading = false
            } catch {
                isReloading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteTier(_ tier: ModelTier) {
        do {
            try modelManager.deleteTier(tier, activeTier: settingsStore.settings.tier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
