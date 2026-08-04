import SwiftUI

@MainActor
protocol BurnExtension: AnyObject {
    var id: String { get }
    var displayName: String { get }

    func refresh()

    // MenuBarExtra labels flatten to one image + title slot, so HStack of multiple Images doesn't compose; return a single Text with embedded SF Symbols via `\(Image(systemName:))`.
    func menuBarSegment() -> Text?

    func popoverTab() -> AnyView

    func settingsView() -> AnyView?

    /// Icon shown in the popover tab strip.
    var tabGlyph: TabGlyph { get }

    /// One sentence of live state for the popover header, next to the pulse dot.
    func statusLine() -> String?

    /// Second line under the extension's name in settings.
    var settingsSubtitle: String? { get }

    /// False when there is nothing on this machine to report yet, which keeps the tab out of the way.
    var isConfigured: Bool { get }
}

extension BurnExtension {
    func settingsView() -> AnyView? { nil }
    var tabGlyph: TabGlyph { .text(displayName) }
    func statusLine() -> String? { nil }
    var settingsSubtitle: String? { nil }
    var isConfigured: Bool { true }
}

private struct OpenBurnSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct BurnTabBarVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct BurnPushDetailKey: EnvironmentKey {
    static let defaultValue: (AnyView) -> Void = { _ in }
}

private struct BurnPopDetailKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
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

    /// Pushes a full-width detail screen over the popover body, keeping the utility bar in place.
    var burnPushDetail: (AnyView) -> Void {
        get { self[BurnPushDetailKey.self] }
        set { self[BurnPushDetailKey.self] = newValue }
    }

    var burnPopDetail: () -> Void {
        get { self[BurnPopDetailKey.self] }
        set { self[BurnPopDetailKey.self] = newValue }
    }
}
