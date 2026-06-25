import AppKit
import SwiftUI
import XCTest
@testable import YouTalkingToMe

@MainActor
final class SettingsViewHarness {
    let settingsStore: SettingsStore
    let modelManager: ModelManager
    let permissions: PermissionsManager
    let tierSelection: TierSelectionModel
    let hostingController: NSHostingController<SettingsView>
    private var window: NSWindow?

    init(
        settingsStore: SettingsStore,
        modelManager: ModelManager,
        permissions: PermissionsManager,
        tierSelection: TierSelectionModel,
        hostingController: NSHostingController<SettingsView>
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.permissions = permissions
        self.tierSelection = tierSelection
        self.hostingController = hostingController
    }

    deinit {
        window?.orderOut(nil)
        window = nil
    }

    func render() {
        if window == nil {
            let window = NSWindow(
                contentRect: hostingController.view.frame,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }

        hostingController.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
    }

    func view(accessibilityIdentifier identifier: String) -> NSView? {
        hostingController.view.findDescendant(accessibilityIdentifier: identifier)
    }

    func click(accessibilityIdentifier identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let view = view(accessibilityIdentifier: identifier) else {
            XCTFail("Missing view with accessibility identifier \(identifier)", file: file, line: line)
            return
        }
        performClick(on: view, file: file, line: line)
    }

    func clickDownload(for tier: ModelTier, file: StaticString = #filePath, line: UInt = #line) {
        let identifier = "settings.models.download-button.\(tier.rawValue)"
        if let view = view(accessibilityIdentifier: identifier) {
            performClick(on: view, file: file, line: line)
            return
        }

        clickButton(titled: "Télécharger", inRowNamed: tier.displayName, file: file, line: line)
    }

    func clickDelete(for tier: ModelTier, file: StaticString = #filePath, line: UInt = #line) {
        let identifier = "settings.models.delete-button.\(tier.rawValue)"
        if let view = view(accessibilityIdentifier: identifier) {
            performClick(on: view, file: file, line: line)
            return
        }

        clickButton(titled: "Supprimer", inRowNamed: tier.displayName, file: file, line: line)
    }

    func clickVerifyPermissions(file: StaticString = #filePath, line: UInt = #line) {
        if let view = view(accessibilityIdentifier: "settings.permissions.verify-button") {
            performClick(on: view, file: file, line: line)
            return
        }

        clickButton(titled: "Vérifier les permissions", file: file, line: line)
    }

    func containsVisibleText(_ text: String) -> Bool {
        hostingController.view.findDescendant { view in
            if view.accessibilityLabel() == text {
                return true
            }
            if let textField = view as? NSTextField, textField.stringValue.contains(text) {
                return true
            }
            if let textView = view as? NSTextView, textView.string.contains(text) {
                return true
            }
            return false
        } != nil
    }

    private func clickButton(
        titled title: String,
        inRowNamed rowName: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let rowName, let row = rowView(named: rowName) {
            if let button = row.findDescendant(where: { ($0 as? NSButton)?.title == title }) as? NSButton {
                button.performClick(nil)
                return
            }
        }

        let buttons = allButtons().filter { $0.title == title }
        guard let button = buttons.first else {
            XCTFail("Missing button titled \(title)", file: file, line: line)
            return
        }
        button.performClick(nil)
    }

    private func rowView(named rowName: String) -> NSView? {
        hostingController.view.findDescendant { view in
            if view.accessibilityLabel()?.contains(rowName) == true {
                return true
            }
            if let textField = view as? NSTextField, textField.stringValue == rowName {
                return true
            }
            return false
        }
    }

    private func allButtons() -> [NSButton] {
        var buttons: [NSButton] = []
        collectButtons(in: hostingController.view, into: &buttons)
        return buttons
    }

    private func collectButtons(in view: NSView, into buttons: inout [NSButton]) {
        if let button = view as? NSButton {
            buttons.append(button)
        }
        for subview in view.subviews {
            collectButtons(in: subview, into: &buttons)
        }
    }

    private func performClick(on view: NSView, file: StaticString, line: UInt) {
        if let button = view as? NSButton {
            button.performClick(nil)
            return
        }

        if let button = view.findDescendant(where: { $0 is NSButton }) as? NSButton {
            button.performClick(nil)
            return
        }

        XCTFail("View is not clickable", file: file, line: line)
    }
}

enum SettingsViewTestSupport {
    static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "YouTalkingToMeTests.Settings.\(UUID().uuidString)")!
    }

    static func absentStatuses() -> [TierInstallStatus] {
        ModelTier.allCases.map { tier in
            TierInstallStatus(tier: tier, sttInstalled: false, polishInstalled: false)
        }
    }

    static func installedStatus(for tier: ModelTier) -> TierInstallStatus {
        TierInstallStatus(tier: tier, sttInstalled: true, polishInstalled: true)
    }

    @MainActor
    static func makeHarness(
        defaults: UserDefaults? = nil,
        tier: ModelTier = .quality,
        tierStatuses: [TierInstallStatus]? = nil,
        permissions: (microphone: Bool, accessibility: Bool, inputMonitoring: Bool, hotkey: Bool)? = nil,
        ensureModelsHandler: ((ModelTier) async throws -> Void)? = nil
    ) -> SettingsViewHarness {
        let defaults = defaults ?? makeDefaults()
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.settings.tier = tier
        settingsStore.save()

        let modelManager = ModelManager(
            inferenceClient: InferenceClient(),
            polishService: MLPolishService()
        )
        modelManager.testingSkipRefreshModelStatuses = true
        modelManager.setTierStatusesForTesting(tierStatuses ?? absentStatuses())
        modelManager.testingEnsureModelsHandler = ensureModelsHandler

        let permissionsManager = PermissionsManager()
        if let permissions {
            permissionsManager.setPermissionsForTesting(
                microphoneGranted: permissions.microphone,
                accessibilityGranted: permissions.accessibility,
                inputMonitoringGranted: permissions.inputMonitoring,
                hotkeyOperational: permissions.hotkey
            )
        }

        let tierSelection = TierSelectionModel(
            settingsStore: settingsStore,
            modelManager: modelManager
        )
        let view = SettingsView(
            settingsStore: settingsStore,
            modelManager: modelManager,
            permissions: permissionsManager,
            tierSelection: tierSelection
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 420, height: 460)

        return SettingsViewHarness(
            settingsStore: settingsStore,
            modelManager: modelManager,
            permissions: permissionsManager,
            tierSelection: tierSelection,
            hostingController: hostingController
        )
    }
}

extension NSView {
    func findDescendant(accessibilityIdentifier identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier {
            return self
        }
        for subview in subviews {
            if let found = subview.findDescendant(accessibilityIdentifier: identifier) {
                return found
            }
        }
        return nil
    }

    func findDescendant(where predicate: (NSView) -> Bool) -> NSView? {
        if predicate(self) {
            return self
        }
        for subview in subviews {
            if let found = subview.findDescendant(where: predicate) {
                return found
            }
        }
        return nil
    }
}
