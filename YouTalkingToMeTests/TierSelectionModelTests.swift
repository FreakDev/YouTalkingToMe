import XCTest
@testable import YouTalkingToMe

@MainActor
final class TierSelectionModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = SettingsViewTestSupport.makeDefaults()
    }

    func testSelectingUninstalledTierPromptsDownloadConfirmation() {
        let harness = SettingsViewTestSupport.makeHarness(defaults: defaults, tier: .quality)
        harness.tierSelection.selectedTier = .fast
        harness.tierSelection.tierSelectionChanged(.fast)

        XCTAssertEqual(harness.tierSelection.tierPendingDownload, .fast)
        XCTAssertEqual(harness.settingsStore.settings.tier, .quality)
    }

    func testCancelDownloadConfirmationRevertsPickerSelection() {
        let harness = SettingsViewTestSupport.makeHarness(defaults: defaults, tier: .quality)
        harness.tierSelection.selectedTier = .fast
        harness.tierSelection.tierSelectionChanged(.fast)
        harness.tierSelection.cancelDownloadConfirmation()

        XCTAssertNil(harness.tierSelection.tierPendingDownload)
        XCTAssertEqual(harness.tierSelection.selectedTier, .quality)
    }

    func testConfirmDownloadPersistsTierAndReloads() async {
        let expectation = expectation(description: "ensure models")
        var loadedTier: ModelTier?
        let harness = SettingsViewTestSupport.makeHarness(
            defaults: defaults,
            tier: .quality,
            ensureModelsHandler: { tier in
                loadedTier = tier
                expectation.fulfill()
            }
        )

        harness.tierSelection.selectedTier = .fast
        harness.tierSelection.tierSelectionChanged(.fast)
        harness.tierSelection.confirmDownload()

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(loadedTier, .fast)
        XCTAssertEqual(harness.settingsStore.settings.tier, .fast)
        XCTAssertNil(harness.tierSelection.tierPendingDownload)
    }

    func testSelectingInstalledTierReloadsImmediately() async {
        let expectation = expectation(description: "ensure models")
        var loadedTier: ModelTier?
        let harness = SettingsViewTestSupport.makeHarness(
            defaults: defaults,
            tier: .quality,
            tierStatuses: [
                SettingsViewTestSupport.installedStatus(for: .quality),
                SettingsViewTestSupport.installedStatus(for: .fast),
            ],
            ensureModelsHandler: { tier in
                loadedTier = tier
                expectation.fulfill()
            }
        )

        harness.tierSelection.selectedTier = .fast
        harness.tierSelection.tierSelectionChanged(.fast)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(loadedTier, .fast)
        XCTAssertEqual(harness.settingsStore.settings.tier, .fast)
        XCTAssertNil(harness.tierSelection.tierPendingDownload)
    }

    func testRequestDeleteSetsPendingDeletion() {
        let harness = SettingsViewTestSupport.makeHarness(defaults: defaults)
        harness.tierSelection.requestDelete(.fast)

        XCTAssertEqual(harness.tierSelection.tierPendingDeletion, .fast)
    }

    func testCancelDeleteClearsPendingDeletion() {
        let harness = SettingsViewTestSupport.makeHarness(defaults: defaults)
        harness.tierSelection.requestDelete(.fast)
        harness.tierSelection.cancelDelete()

        XCTAssertNil(harness.tierSelection.tierPendingDeletion)
    }

    func testReloadFailureSurfacesErrorMessage() async {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "Échec simulé" }
        }

        let harness = SettingsViewTestSupport.makeHarness(
            defaults: defaults,
            ensureModelsHandler: { _ in throw FakeError() }
        )

        harness.tierSelection.reloadModels(for: .quality)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(harness.tierSelection.errorMessage, "Échec simulé")
    }

    func testReloadModelsDoesNotReopenDownloadPrompt() async {
        let harness = SettingsViewTestSupport.makeHarness(
            defaults: defaults,
            tier: .quality,
            ensureModelsHandler: { _ in }
        )
        harness.tierSelection.tierSelectionChanged(.fast)
        harness.tierSelection.reloadModels(for: .fast)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(harness.tierSelection.tierPendingDownload)
    }

    func testConfirmDeleteClearsPendingDeletion() {
        let harness = SettingsViewTestSupport.makeHarness(defaults: defaults)
        harness.tierSelection.requestDelete(.fast)
        harness.tierSelection.confirmDelete()

        XCTAssertNil(harness.tierSelection.tierPendingDeletion)
    }
}
