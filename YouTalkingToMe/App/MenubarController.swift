import AppKit
import Combine
import SwiftUI

final class MenubarController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let permissionsManager: PermissionsManager
    private let modelManager: ModelManager
    private let pipeline: PipelineCoordinator
    private let inferenceClient: InferenceClient

    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let overlayController = OverlayPanelController()
    private var settingsWindow: NSWindow?
    private var isSettingsPanelOpen = false

    init(
        settingsStore: SettingsStore,
        permissionsManager: PermissionsManager,
        modelManager: ModelManager,
        pipeline: PipelineCoordinator,
        inferenceClient: InferenceClient
    ) {
        self.settingsStore = settingsStore
        self.permissionsManager = permissionsManager
        self.modelManager = modelManager
        self.pipeline = pipeline
        self.inferenceClient = inferenceClient
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
            presentSettings()
        }

        if !settingsStore.settings.hasCompletedOnboarding {
            settingsStore.settings.tier = .quality
            settingsStore.settings.hasCompletedOnboarding = true
            settingsStore.save()
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
            guard let self else { return }
            if self.modelManager.isDownloading {
                self.pipeline.showUserMessage(
                    "Téléchargement des modèles en cours, veuillez réessayer dans quelques instants."
                )
                return
            }
            self.pipeline.startDictation()
        }
        manager.onRelease = { [weak self] in
            guard let self, self.pipeline.overlayState == .listening else { return }
            self.pipeline.endDictation()
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
            self.permissionsManager.refresh()
            if self.hotkeyManager?.isOperational != true {
                self.setupHotkeyIfNeeded()
            }
            if self.isSettingsPanelOpen, let settingsWindow = self.settingsWindow {
                NSApp.setActivationPolicy(.regular)
                settingsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
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

    private var cancellables: Set<AnyCancellable> = []

    @objc private func openSettings() {
        presentSettings()
    }

    private func presentSettings() {
        let view = SettingsView(
            settingsStore: settingsStore,
            modelManager: modelManager,
            permissions: permissionsManager
        )
        let hosting = NSHostingController(rootView: view)

        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
            window.contentViewController = hosting
        } else {
            window = NSWindow(contentViewController: hosting)
            window.title = "You Talking To Me"
            window.styleMask = [.titled, .closable]
            settingsWindow = window
        }

        configureSettingsWindow(window)
        isSettingsPanelOpen = true
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        isSettingsPanelOpen = false
        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        inferenceClient.stop()
        NSApp.terminate(nil)
    }
}
