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
            if !permissions.allGranted {
                permissionsSetupSection
            }
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
    }

    private var selectedTierStatus: TierInstallStatus? {
        modelManager.tierStatuses.first { $0.tier == selectedTier }
    }

    private var isLoadingSelectedTier: Bool {
        isReloading || modelManager.isDownloading
    }

    private var qualityStatusLabel: String? {
        if isLoadingSelectedTier {
            return "Téléchargement des modèles"
        }
        guard selectedTierStatus?.isFullyInstalled == true else { return nil }
        if selectedTier == settingsStore.settings.tier, modelManager.isReady {
            return "Modèles prêts"
        }
        if selectedTier != settingsStore.settings.tier {
            return "Modèles prêts"
        }
        return nil
    }

    @ViewBuilder
    private var permissionsSetupSection: some View {
        Section {
            Text("Autorisez les permissions ci-dessous pour activer la dictée vocale push-to-talk dans toutes vos apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dictationSection: some View {
        Section("Dictée") {
            LabeledContent("Hotkey") {
                Text("Option + Space")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Qualité") {
                HStack(spacing: 12) {
                    Picker("", selection: $selectedTier) {
                        ForEach(ModelTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    if let qualityStatusLabel {
                        Text(qualityStatusLabel)
                            .font(.caption)
                            .foregroundStyle(isLoadingSelectedTier ? .orange : .green)
                    }
                }
            }
            .onChange(of: selectedTier) { _, newValue in
                reloadModels(for: newValue)
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        Section("Modèles") {
            ForEach(modelManager.tierStatuses) { status in
                tierRow(status)
            }
            if isReloading || modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress) {
                    Text(modelManager.downloadStage)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section("Permissions") {
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
                granted: permissions.inputMonitoringGranted,
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
            Text(status.statusLabel)
                .font(.caption)
                .foregroundStyle(status.isFullyInstalled ? .green : (status.hasAnyInstalled ? .orange : .secondary))
            if status.hasAnyInstalled {
                Button("Supprimer") {
                    tierPendingDeletion = status.tier
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

    private func reloadModels(for tier: ModelTier) {
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
