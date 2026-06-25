import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var tierSelection: TierSelectionModel

    var body: some View {
        Form {
            dictationSection
            permissionsSection
            modelsSection

            if let errorMessage = tierSelection.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                        .accessibilityIdentifier("settings.error-message")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 460)
        .accessibilityIdentifier("settings.form")
        .onAppear {
            modelManager.refreshModelStatuses()
        }
        .confirmationDialog(
            "Supprimer ces modèles ?",
            isPresented: Binding(
                get: { tierSelection.tierPendingDeletion != nil },
                set: { if !$0 { tierSelection.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                tierSelection.confirmDelete()
            }
            Button("Annuler", role: .cancel) {
                tierSelection.cancelDelete()
            }
        } message: {
            if let tier = tierSelection.tierPendingDeletion {
                Text("Les modèles \(tier.bundledModelsDescription) seront retirés de votre Mac.")
            }
        }
        .confirmationDialog(
            "Télécharger les modèles ?",
            isPresented: Binding(
                get: { tierSelection.tierPendingDownload != nil },
                set: { if !$0 { tierSelection.cancelDownloadConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Télécharger") {
                tierSelection.confirmDownload()
            }
            Button("Annuler", role: .cancel) {
                tierSelection.cancelDownloadConfirmation()
            }
        } message: {
            if let tier = tierSelection.tierPendingDownload {
                Text("Les modèles \(tier.bundledModelsDescription) ne sont pas installés sur votre Mac.")
            }
        }
    }

    @ViewBuilder
    private var dictationSection: some View {
        Section("Dictée") {
            LabeledContent("Hotkey") {
                Text(HotkeyDisplay.label(
                    modifiers: settingsStore.settings.hotkeyModifiers,
                    keyCode: settingsStore.settings.hotkeyKeyCode
                ))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.hotkey.label")
            }
            LabeledContent("Qualité optimale") {
                HStack(spacing: 12) {
                    if tierSelection.isDownloadingFromNetwork {
                        Text("Téléchargement des modèles")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("settings.tier.download-badge")
                    } else if tierSelection.selectedTierIsAbsent {
                        Text("Modèle absent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.tier.absent-badge")
                    }

                    Picker("", selection: $tierSelection.selectedTier) {
                        ForEach(ModelTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings.tier.picker")
                }
            }
            .onChange(of: tierSelection.selectedTier) { _, newValue in
                tierSelection.tierSelectionChanged(newValue)
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        Section("Modèles") {
            ForEach(modelManager.tierStatuses) { status in
                tierRow(status)
            }
            if tierSelection.showsDownloadProgress {
                ProgressView(value: modelManager.downloadProgress) {
                    Text(modelManager.downloadStage)
                }
                .accessibilityIdentifier("settings.models.progress")
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
                    .accessibilityIdentifier("settings.permissions.prompt")
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
            .accessibilityIdentifier("settings.permissions.verify-button")
        } header: {
            Text("Permissions")
                .accessibilityIdentifier("settings.section.permissions")
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
            if status.hasAnyInstalled {
                Text(status.statusLabel)
                    .font(.caption)
                    .foregroundStyle(status.isFullyInstalled ? .green : .orange)
            }
            if status.isFullyInstalled {
                Button("Supprimer") {
                    tierSelection.requestDelete(status.tier)
                }
                .accessibilityIdentifier("settings.models.delete-button.\(status.tier.rawValue)")
            } else if status.hasAnyInstalled {
                Button("Télécharger") {
                    tierSelection.reloadModels(for: status.tier)
                }
                .accessibilityIdentifier("settings.models.download-button.\(status.tier.rawValue)")
                Button("Supprimer") {
                    tierSelection.requestDelete(status.tier)
                }
                .accessibilityIdentifier("settings.models.delete-button.\(status.tier.rawValue)")
            } else {
                Button("Télécharger") {
                    tierSelection.reloadModels(for: status.tier)
                }
                .accessibilityIdentifier("settings.models.download-button.\(status.tier.rawValue)")
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
}
