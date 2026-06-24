import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var settingsStore: SettingsStore
  @ObservedObject var modelManager: ModelManager
  @ObservedObject var permissions: PermissionsManager

    @State private var selectedTier: ModelTier
    @State private var isReloading = false
    @State private var errorMessage: String?

    init(settingsStore: SettingsStore, modelManager: ModelManager, permissions: PermissionsManager) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.permissions = permissions
        _selectedTier = State(initialValue: settingsStore.settings.tier)
    }

    var body: some View {
        Form {
            Section("Dictée") {
                LabeledContent("Hotkey") {
                    Text("Option + Space")
                        .foregroundStyle(.secondary)
                }
                Picker("Qualité", selection: $selectedTier) {
                    ForEach(ModelTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .onChange(of: selectedTier) { _, newValue in
                    reloadModels(for: newValue)
                }
            }

            Section("Modèles") {
                LabeledContent("Statut") {
                    Text(modelManager.isReady ? "Prêt" : "Non chargé")
                }
                if isReloading {
                    ProgressView(value: modelManager.downloadProgress) {
                        Text(modelManager.downloadStage)
                    }
                }
            }

            Section("Permissions") {
                LabeledContent("Microphone", value: permissions.microphoneGranted ? "OK" : "Requis")
                LabeledContent("Accessibilité", value: permissions.accessibilityGranted ? "OK" : "Requis")
                LabeledContent(
                    "Surveillance entrées",
                    value: (permissions.inputMonitoringGranted || permissions.hotkeyOperational) ? "OK" : "Requis"
                )
                if permissions.restartRequired {
                    Text("Redémarrage requis après activation de la surveillance des entrées.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Vérifier les permissions") {
                    permissions.refresh()
                }
                Button("Ouvrir les paramètres de confidentialité") {
                    permissions.openAccessibilitySettings()
                }
            }

            Section("Diagnostic") {
                LabeledContent("Logs") {
                    Text(AppLogger.logFileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Ouvrir le dossier de logs") {
                    AppLogger.revealInFinder()
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
        .onAppear {
            permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
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
}
