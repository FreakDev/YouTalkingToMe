import AppKit
import SwiftUI

struct OnboardingView: View {
  @ObservedObject var permissions: PermissionsManager
  @ObservedObject var modelManager: ModelManager
  @ObservedObject var settingsStore: SettingsStore
    let onComplete: () -> Void

    @State private var selectedTier: ModelTier = .fast
    @State private var isLoadingModels = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bienvenue dans You Talking To Me")
                .font(.title2.bold())

            Text("Dictée vocale locale, push-to-talk dans toutes vos apps.")
                .foregroundStyle(.secondary)

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 10) {
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
                        title: "Surveillance des entrées",
                        granted: permissions.inputMonitoringGranted || permissions.hotkeyOperational,
                        action: permissions.requestInputMonitoring,
                        settingsAction: permissions.openInputMonitoringSettings
                    )

                    HStack {
                        Spacer()
                        Button("Vérifier les permissions") {
                            permissions.refresh()
                        }
                    }

                    if permissions.restartRequired {
                        Text(
                            "Les permissions semblent activées dans les Réglages, mais macOS exige souvent un redémarrage de You Talking To Me après « Surveillance des entrées ». Quittez et relancez l'app."
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }

            GroupBox("Qualité des modèles") {
                Picker("Tier", selection: $selectedTier) {
                    ForEach(ModelTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if isLoadingModels {
                ProgressView(value: modelManager.downloadProgress) {
                    Text(modelManager.downloadStage)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Commencer") {
                    startSetup()
                }
                .disabled(!permissions.allGranted || isLoadingModels)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            permissions.refresh()
            selectedTier = settingsStore.settings.tier
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
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
                Button("Paramètres", action: settingsAction)
            }
        }
    }

    private func startSetup() {
        isLoadingModels = true
        errorMessage = nil
        settingsStore.settings.tier = selectedTier
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.save()

        Task {
            do {
                try await modelManager.ensureModels(tier: selectedTier)
                await MainActor.run {
                    isLoadingModels = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isLoadingModels = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
