import Foundation
import Combine

/// Persisted toggles (Android parity: SharedPreferences "knucklegame").
/// All defaults are false, matching Android's Settings + SettingsTest.
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Keys.muted) } }
    @Published var autoRoll: Bool { didSet { defaults.set(autoRoll, forKey: Keys.autoRoll) } }
    @Published var onboardingSeen: Bool { didSet { defaults.set(onboardingSeen, forKey: Keys.onboardingSeen) } }

    private enum Keys {
        static let muted = "knuckled.muted"
        static let autoRoll = "knuckled.autoRoll"
        static let onboardingSeen = "knuckled.onboardingSeen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.muted = defaults.bool(forKey: Keys.muted)
        self.autoRoll = defaults.bool(forKey: Keys.autoRoll)
        self.onboardingSeen = defaults.bool(forKey: Keys.onboardingSeen)
    }
}
