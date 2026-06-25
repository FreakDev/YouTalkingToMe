import AppKit
import XCTest
@testable import YouTalkingToMe

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "YouTalkingToMeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
    }

    func testDefaultSettings() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.tier, .quality)
        XCTAssertEqual(store.settings.hotkeyModifiers, AppSettings.default.hotkeyModifiers)
        XCTAssertEqual(store.settings.hotkeyKeyCode, AppSettings.default.hotkeyKeyCode)
    }

    func testSaveAndLoadRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        store.settings.tier = .quality
        store.settings.hotkeyModifiers = 999
        store.settings.hotkeyKeyCode = 123
        store.save()

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.tier, .quality)
        XCTAssertEqual(reloaded.settings.hotkeyModifiers, 999)
        XCTAssertEqual(reloaded.settings.hotkeyKeyCode, 123)
    }
}
