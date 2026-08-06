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
    static let defaultRefreshInterval = 5

    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey) }
    }

    var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey) }
    }

    static let availableIntervals = [1, 5, 10, 15, 30]

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshIntervalMinutes = Self.availableIntervals.contains(stored) ? stored : Self.defaultRefreshInterval
        let modeRaw = UserDefaults.standard.object(forKey: Self.displayModeKey) as? Int
        self.displayMode = modeRaw.flatMap(DisplayMode.init(rawValue:)) ?? .cost
    }
}
