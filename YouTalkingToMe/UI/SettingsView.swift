import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var settingsStore: SettingsStore
  @ObservedObject var modelManager: ModelManager
  @ObservedObject var permissions: PermissionsManager

    @State private var selectedTier: ModelTier
    @State private var isReloading = false
    @State private var errorMessage: String?
    @State private var tierPendingDeletion: ModelTier?
    @State private var tierPendingDownload: ModelTier?
    @State private var isRevertingTierSelection = false

    init(
        settingsStore: SettingsStore,
        modelManager: ModelManager,
        permissions: PermissionsManager
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.permissions = permissions
        _selectedTier = State(initialValue: settingsStore.settings.tier)
    }

    var body: some View {
        Form {
            dictationSection
            permissionsSection
            modelsSection

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 460)
        .onAppear {
            permissions.refresh()
            modelManager.refreshModelStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            modelManager.refreshModelStatuses()
        }
        .confirmationDialog(
            "Supprimer ces modèles ?",
            isPresented: Binding(
                get: { tierPendingDeletion != nil },
                set: { if !$0 { tierPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let tier = tierPendingDeletion {
                    deleteTier(tier)
                }
                tierPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) {
                tierPendingDeletion = nil
            }
        } message: {
            if let tier = tierPendingDeletion {
                Text("Les modèles \(tier.bundledModelsDescription) seront retirés de votre Mac.")
            }
        }
        .confirmationDialog(
            "Télécharger les modèles ?",
            isPresented: Binding(
                get: { tierPendingDownload != nil },
                set: { if !$0 { tierPendingDownload = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Télécharger") {
                if let tier = tierPendingDownload {
                    reloadModels(for: tier)
                }
                tierPendingDownload = nil
            }
            Button("Annuler", role: .cancel) {
                isRevertingTierSelection = true
                selectedTier = settingsStore.settings.tier
                tierPendingDownload = nil
            }
        } message: {
            if let tier = tierPendingDownload {
                Text("Les modèles \(tier.bundledModelsDescription) ne sont pas installés sur votre Mac.")
            }
        }
    }

    private var selectedTierIsAbsent: Bool {
        selectedTierStatus?.isFullyInstalled != true && !isDownloadingFromNetwork
    }

    private var selectedTierStatus: TierInstallStatus? {
        modelManager.tierStatuses.first { $0.tier == selectedTier }
    }

    private var isLoadingSelectedTier: Bool {
        isReloading || modelManager.isDownloading
    }

    private var isDownloadingFromNetwork: Bool {
        isLoadingSelectedTier && selectedTierStatus?.isFullyInstalled != true
    }

    private var showsDownloadProgress: Bool {
        isDownloadingFromNetwork
    }

    @ViewBuilder
    private var dictationSection: some View {
        Section("Dictée") {
            LabeledContent("Hotkey") {
                Text("Option + Space")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Qualité optimale") {
                HStack(spacing: 12) {
                    if isDownloadingFromNetwork {
                        Text("Téléchargement des modèles")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if selectedTierIsAbsent {
                        Text("Modèle absent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $selectedTier) {
                        ForEach(ModelTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .onChange(of: selectedTier) { _, newValue in
                if isRevertingTierSelection {
                    isRevertingTierSelection = false
                    return
                }
                handleTierSelectionChange(newValue)
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        Section("Modèles") {
            ForEach(modelManager.tierStatuses) { status in
                tierRow(status)
            }
            if showsDownloadProgress {
                ProgressView(value: modelManager.downloadProgress) {
                    Text(modelManager.downloadStage)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section {
            if !permissions.allGranted {
                Text("Autorisez les permissions ci-dessous pour activer la dictée vocale push-to-talk dans toutes vos apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            permissionRow(
                title: "Microphone",
                granted: permissions.microphoneGranted,
                action: permissions.requestMicrophone,
                settingsAction: permissions.openMicrophoneSettings
            )
            permissionRow(
                title: "Accessibilité",
                granted: permissions.accessibilityGranted,
                action: permissions.requestAccessibility,
                settingsAction: permissions.openAccessibilitySettings
            )
            permissionRow(
                title: "Surveillance entrées",
                granted: permissions.inputMonitoringGranted || permissions.hotkeyOperational,
                action: permissions.requestInputMonitoring,
                settingsAction: permissions.openInputMonitoringSettings
            )
            if permissions.restartRequired {
                Text("Redémarrage requis après activation de la surveillance des entrées.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Vérifier les permissions") {
                permissions.refresh()
            }
        } header: {
            Text("Permissions")
        }
    }

    @ViewBuilder
    private func tierRow(_ status: TierInstallStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.tier.displayName)
                Text(status.tier.bundledModelsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status.isFullyInstalled {
                Text("Téléchargé")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Supprimer") {
                    tierPendingDeletion = status.tier
                }
            } else if status.hasAnyInstalled {
                Text("Partiel")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Télécharger") {
                    reloadModels(for: status.tier)
                }
                Button("Supprimer") {
                    tierPendingDeletion = status.tier
                }
            } else {
                Button("Télécharger") {
                    reloadModels(for: status.tier)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        granted: Bool,
        action: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if !granted {
                Button("Autoriser", action: action)
            }
            Button("Paramètres", action: settingsAction)
        }
    }

    private func handleTierSelectionChange(_ tier: ModelTier) {
        let status = modelManager.tierStatuses.first { $0.tier == tier }
        if status?.isFullyInstalled == true {
            reloadModels(for: tier)
        } else {
            tierPendingDownload = tier
        }
    }

    private func reloadModels(for tier: ModelTier) {
        selectedTier = tier
        settingsStore.settings.tier = tier
        settingsStore.save()
        isReloading = true
        errorMessage = nil

        Task {
            do {
                try await modelManager.ensureModels(tier: tier)
                await MainActor.run { isReloading = false }
            } catch {
                await MainActor.run {
                    isReloading = false
                    errorMessage = error.localizedDescription
                }
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
