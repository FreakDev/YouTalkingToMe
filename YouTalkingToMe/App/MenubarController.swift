import AppKit
import Combine
import SwiftUI

final class MenubarController: NSObject {
    private let settingsStore: SettingsStore
    private let permissionsManager: PermissionsManager
    private let modelManager: ModelManager
    private let pipeline: PipelineCoordinator
    private let inferenceClient: InferenceClient

    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let overlayController = OverlayPanelController()
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

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
        permissionsManager.requestMicrophone()

        setupStatusItem()
        setupHotkeyIfNeeded()
        observeOverlay()
        observeAppActivation()

        if !settingsStore.settings.hasCompletedOnboarding {
            showOnboarding()
        } else {
            Task(priority: .utility) {
                try? await modelManager.ensureModels(tier: settingsStore.settings.tier)
            }
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
            self?.pipeline.startDictation()
        }
        manager.onRelease = { [weak self] in
            self?.pipeline.endDictation()
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
        if settingsWindow == nil {
            let view = SettingsView(
                settingsStore: settingsStore,
                modelManager: modelManager,
                permissions: permissionsManager
            )
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "You Talking To Me"
            window.styleMask = [.titled, .closable]
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        inferenceClient.stop()
        NSApp.terminate(nil)
    }

    private func showOnboarding() {
        let view = OnboardingView(
            permissions: permissionsManager,
            modelManager: modelManager,
            settingsStore: settingsStore,
            onComplete: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Configuration"
        window.styleMask = [.titled, .closable]
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
