import Foundation

enum MenuBarDisplay: Int {
    case icon = 0
    case amount = 1
    case both = 2
}

enum DisplayMode: Int {
    case cost = 0
    case tokens = 1
    case both = 2
}

@Observable
final class SettingsStore {
    static let refreshIntervalKey = "refreshIntervalMinutes"
    static let menuBarDisplayKey = "menuBarDisplay"
    static let displayModeKey = "displayMode"
    static let defaultRefreshInterval = 5

    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey) }
    }

    var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Self.menuBarDisplayKey) }
    }

    var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey) }
    }

    static let availableIntervals = [1, 5, 10, 15, 30]

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshIntervalMinutes = Self.availableIntervals.contains(stored) ? stored : Self.defaultRefreshInterval
        let displayRaw = UserDefaults.standard.object(forKey: Self.menuBarDisplayKey) as? Int
        self.menuBarDisplay = displayRaw.flatMap(MenuBarDisplay.init(rawValue:)) ?? .both
        let modeRaw = UserDefaults.standard.object(forKey: Self.displayModeKey) as? Int
        self.displayMode = modeRaw.flatMap(DisplayMode.init(rawValue:)) ?? .cost
    }
}
