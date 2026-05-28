import SwiftUI

@MainActor
protocol BurnExtension: AnyObject {
    var id: String { get }
    var displayName: String { get }

    func refresh()

    // MenuBarExtra labels flatten to one image + title slot, so HStack of multiple Images doesn't compose; return a single Text with embedded SF Symbols via `\(Image(systemName:))`.
    func menuBarSegment() -> Text?

    func popoverTab() -> AnyView
}

private struct OpenBurnSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct BurnTabBarVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var openBurnSettings: () -> Void {
        get { self[OpenBurnSettingsKey.self] }
        set { self[OpenBurnSettingsKey.self] = newValue }
    }

    /// True when the chrome owns a shared tab/header bar, so per-tab views should skip their own header.
    var burnTabBarVisible: Bool {
        get { self[BurnTabBarVisibleKey.self] }
        set { self[BurnTabBarVisibleKey.self] = newValue }
    }
}
