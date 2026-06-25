import Foundation

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let defaults: UserDefaults
    private enum Keys {
        static let tier = "tier"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let tierRaw = defaults.string(forKey: Keys.tier) ?? ModelTier.quality.rawValue
        let tier = ModelTier(rawValue: tierRaw) ?? .quality
        let modifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt ?? AppSettings.default.hotkeyModifiers
        let keyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? UInt16 ?? AppSettings.default.hotkeyKeyCode
        let hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        settings = AppSettings(
            tier: tier,
            hotkeyModifiers: modifiers,
            hotkeyKeyCode: keyCode,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }

    func save() {
        defaults.set(settings.tier.rawValue, forKey: Keys.tier)
        defaults.set(settings.hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        defaults.set(settings.hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        defaults.set(settings.hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
    }
}
