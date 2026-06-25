import AppKit
import XCTest
@testable import YouTalkingToMe

@MainActor
final class SettingsViewFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func testSettingsViewHostsWithoutCrashing() {
        let harness = SettingsViewTestSupport.makeHarness()
        harness.render()

        XCTAssertEqual(harness.hostingController.view.frame.size, NSSize(width: 420, height: 460))
    }

    func testSettingsViewReflectsConfiguredHotkey() {
        let harness = SettingsViewTestSupport.makeHarness()
        harness.render()

        let expected = HotkeyDisplay.label(
            modifiers: harness.settingsStore.settings.hotkeyModifiers,
            keyCode: harness.settingsStore.settings.hotkeyKeyCode
        )
        XCTAssertEqual(expected, "Option + Space")
    }

    func testSettingsViewFlowShowsAbsentTierState() {
        let harness = SettingsViewTestSupport.makeHarness(tier: .quality)
        harness.render()

        XCTAssertTrue(harness.tierSelection.selectedTierIsAbsent)
        XCTAssertFalse(harness.tierSelection.showsDownloadProgress)
    }

    func testSettingsViewFlowShowsDownloadProgressState() {
        let harness = SettingsViewTestSupport.makeHarness(tier: .quality)
        harness.modelManager.setDownloadStateForTesting(
            isDownloading: true,
            progress: 0.2,
            stage: "download_stt"
        )
        harness.render()

        XCTAssertTrue(harness.tierSelection.showsDownloadProgress)
        XCTAssertFalse(harness.tierSelection.selectedTierIsAbsent)
        XCTAssertEqual(harness.modelManager.downloadProgress, 0.2, accuracy: 0.001)
    }

    func testSettingsViewFlowPermissionsIncomplete() {
        let harness = SettingsViewTestSupport.makeHarness(
            permissions: (microphone: false, accessibility: false, inputMonitoring: false, hotkey: false)
        )
        harness.render()

        XCTAssertFalse(harness.permissions.allGranted)
    }

    func testSettingsViewFlowPermissionsComplete() {
        let harness = SettingsViewTestSupport.makeHarness(
            permissions: (microphone: true, accessibility: true, inputMonitoring: true, hotkey: true)
        )
        harness.render()

        XCTAssertTrue(harness.permissions.allGranted)
    }

    func testClickVerifyPermissionsTriggersRefresh() {
        let harness = SettingsViewTestSupport.makeHarness(
            permissions: (microphone: false, accessibility: false, inputMonitoring: false, hotkey: false)
        )
        harness.render()

        let initialCount = harness.permissions.refreshCallCount
        harness.permissions.refresh()

        XCTAssertGreaterThan(harness.permissions.refreshCallCount, initialCount)
    }

    func testDownloadActionOnAbsentTierRowStartsReloadFlow() async {
        let expectation = expectation(description: "download started")
        let harness = SettingsViewTestSupport.makeHarness(
            tier: .quality,
            ensureModelsHandler: { tier in
                XCTAssertEqual(tier, .fast)
                expectation.fulfill()
            }
        )
        harness.render()

        harness.tierSelection.reloadModels(for: .fast)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(harness.settingsStore.settings.tier, .fast)
    }

    func testDeleteActionOnInstalledTierRowPromptsDeletion() {
        let harness = SettingsViewTestSupport.makeHarness(
            tierStatuses: [
                TierInstallStatus(tier: .fast, sttInstalled: false, polishInstalled: false),
                SettingsViewTestSupport.installedStatus(for: .quality),
            ]
        )
        harness.render()

        harness.tierSelection.requestDelete(.quality)

        XCTAssertEqual(harness.tierSelection.tierPendingDeletion, .quality)
    }

    func testTierRowStatusesDriveModelActions() {
        let harness = SettingsViewTestSupport.makeHarness(
            tierStatuses: [
                TierInstallStatus(tier: .fast, sttInstalled: false, polishInstalled: false),
                SettingsViewTestSupport.installedStatus(for: .quality),
            ]
        )
        harness.render()

        let quality = harness.modelManager.tierStatuses.first { $0.tier == .quality }
        let fast = harness.modelManager.tierStatuses.first { $0.tier == .fast }

        XCTAssertEqual(quality?.statusLabel, "Téléchargé")
        XCTAssertEqual(fast?.statusLabel, "Absent")
    }

    func testReloadFailureSurfacesErrorInViewModel() async {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "Erreur UI simulée" }
        }

        let harness = SettingsViewTestSupport.makeHarness(
            ensureModelsHandler: { _ in throw FakeError() }
        )

        harness.tierSelection.reloadModels(for: .quality)
        try? await Task.sleep(nanoseconds: 150_000_000)
        harness.render()

        XCTAssertEqual(harness.tierSelection.errorMessage, "Erreur UI simulée")
    }

    func testPickerChangeToAbsentTierPromptsDownloadConfirmation() {
        let harness = SettingsViewTestSupport.makeHarness(tier: .quality)
        harness.render()

        harness.tierSelection.tierSelectionChanged(.fast)

        XCTAssertEqual(harness.tierSelection.tierPendingDownload, .fast)
    }

    func testConfirmDownloadDialogFlowUpdatesPersistedTier() async {
        let expectation = expectation(description: "download confirmed")
        let harness = SettingsViewTestSupport.makeHarness(
            tier: .quality,
            ensureModelsHandler: { tier in
                XCTAssertEqual(tier, .fast)
                expectation.fulfill()
            }
        )
        harness.render()

        harness.tierSelection.tierSelectionChanged(.fast)
        harness.tierSelection.confirmDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(harness.settingsStore.settings.tier, .fast)
        XCTAssertNil(harness.tierSelection.tierPendingDownload)
    }

    func testCancelDownloadDialogFlowRevertsPicker() {
        let harness = SettingsViewTestSupport.makeHarness(tier: .quality)
        harness.render()

        harness.tierSelection.tierSelectionChanged(.fast)
        harness.tierSelection.cancelDownloadConfirmation()

        XCTAssertNil(harness.tierSelection.tierPendingDownload)
        XCTAssertEqual(harness.tierSelection.selectedTier, .quality)
    }
}
