import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let modelManager: ModelManager
    private let permissions: PermissionsManager

    private var window: NSWindow?
    private(set) var isOpen = false

    init(
        settingsStore: SettingsStore,
        modelManager: ModelManager,
        permissions: PermissionsManager
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.permissions = permissions
        super.init()
    }

    func present() {
        let tierSelection = TierSelectionModel(
            settingsStore: settingsStore,
            modelManager: modelManager
        )
        let view = SettingsView(
            settingsStore: settingsStore,
            modelManager: modelManager,
            permissions: permissions,
            tierSelection: tierSelection
        )
        let hosting = NSHostingController(rootView: view)

        let window: NSWindow
        if let existingWindow = self.window {
            window = existingWindow
            window.contentViewController = hosting
        } else {
            window = NSWindow(contentViewController: hosting)
            window.title = "You Talking To Me"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            self.window = window
        }

        isOpen = true
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreIfOpen() {
        guard isOpen, let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        isOpen = false
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
