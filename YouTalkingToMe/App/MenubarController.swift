import AppKit
import Combine
import SwiftUI

@MainActor
final class MenubarController: NSObject {
    private let settingsStore: SettingsStore
    private let permissionsManager: PermissionsManager
    private let modelManager: ModelManager
    private let pipeline: PipelineCoordinator

    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let overlayController = OverlayPanelController()
    private let settingsWindowController: SettingsWindowController
    private var cancellables: Set<AnyCancellable> = []

    init(
        settingsStore: SettingsStore,
        permissionsManager: PermissionsManager,
        modelManager: ModelManager,
        pipeline: PipelineCoordinator
    ) {
        self.settingsStore = settingsStore
        self.permissionsManager = permissionsManager
        self.modelManager = modelManager
        self.pipeline = pipeline
        self.settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            modelManager: modelManager,
            permissions: permissionsManager
        )
        super.init()
    }

    func bootstrap() {
        permissionsManager.refresh()

        setupStatusItem()
        setupHotkeyIfNeeded()
        observeOverlay()
        observeAppActivation()
        observeHotkeyRetry()

        if !permissionsManager.allGranted {
            settingsWindowController.present()
        }

        Task(priority: .utility) {
            try? await modelManager.ensureModels(tier: settingsStore.settings.tier)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "You Talking To Me")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Paramètres...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quitter You Talking To Me", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
    }

    private func setupHotkeyIfNeeded() {
        if hotkeyManager?.isOperational == true {
            permissionsManager.setHotkeyOperational(true)
            return
        }

        let manager = hotkeyManager ?? HotkeyManager(
            modifiers: settingsStore.settings.hotkeyModifiers,
            keyCode: settingsStore.settings.hotkeyKeyCode
        )
        manager.onPress = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.modelManager.isDownloading {
                    self.pipeline.showUserMessage(
                        "Téléchargement des modèles en cours, veuillez réessayer dans quelques instants."
                    )
                    return
                }
                self.pipeline.startDictation()
            }
        }
        manager.onRelease = { [weak self] in
            Task { @MainActor in
                self?.pipeline.endDictation()
            }
        }

        let started = manager.start()
        hotkeyManager = manager
        permissionsManager.setHotkeyOperational(started)
    }

    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.hotkeyManager?.isOperational != true {
                self.setupHotkeyIfNeeded()
            }
            self.settingsWindowController.restoreIfOpen()
        }
    }

    private func observeHotkeyRetry() {
        NotificationCenter.default.addObserver(
            forName: .retryHotkeySetup,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupHotkeyIfNeeded()
        }
    }

    private func observeOverlay() {
        pipeline.$overlayState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.overlayController.show(state: state)
            }
            .store(in: &cancellables)
    }

    @objc private func openSettings() {
        settingsWindowController.present()
    }

    @objc private func quit() {
        modelManager.shutdown()
        NSApp.terminate(nil)
    }
}
