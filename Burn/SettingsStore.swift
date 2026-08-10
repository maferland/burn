import Foundation

enum DisplayMode: Int {
    case cost = 0
    case tokens = 1
    case both = 2
}

@Observable
final class SettingsStore {
    static let refreshIntervalKey = "refreshIntervalMinutes"
    static let displayModeKey = "displayMode"
    static let appearanceKey = "appearance"
    static let defaultRefreshInterval = 5

    var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Self.displayModeKey) }
    }

    /// Tokens cover the colours; this is the state half, and it has to reach NSApp to take effect.
    var appearance: AppearanceChoice {
        didSet {
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            appearance.apply()
        }
    }

    static let availableIntervals = [1, 5, 10, 15, 30]

    private let defaults: UserDefaults

    /// Injectable so a screenshot run can't write its BURN_DISPLAY_MODE override into the real app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.refreshIntervalKey)
        self.refreshIntervalMinutes = Self.availableIntervals.contains(stored) ? stored : Self.defaultRefreshInterval
        let modeRaw = defaults.object(forKey: Self.displayModeKey) as? Int
        self.displayMode = modeRaw.flatMap(DisplayMode.init(rawValue:)) ?? .cost
        let appearanceRaw = defaults.object(forKey: Self.appearanceKey) as? Int
        self.appearance = appearanceRaw.flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }
}
