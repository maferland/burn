import Foundation

enum MenuBarDisplay: Int {
    case icon = 0
    case amount = 1
    case both = 2
}

@Observable
final class SettingsStore {
    static let refreshIntervalKey = "refreshIntervalMinutes"
    static let menuBarDisplayKey = "menuBarDisplay"
    static let defaultRefreshInterval = 5

    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey) }
    }

    var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Self.menuBarDisplayKey) }
    }

    static let availableIntervals = [1, 5, 10, 15, 30]

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshIntervalMinutes = Self.availableIntervals.contains(stored) ? stored : Self.defaultRefreshInterval
        self.menuBarDisplay = MenuBarDisplay(rawValue: UserDefaults.standard.integer(forKey: Self.menuBarDisplayKey)) ?? .both
    }
}
