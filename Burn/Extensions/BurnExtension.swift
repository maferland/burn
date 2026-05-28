import SwiftUI

@MainActor
protocol BurnExtension: AnyObject {
    var id: String { get }
    var displayName: String { get }

    func refresh()

    func menuBarSegment() -> AnyView?
    func popoverTab() -> AnyView
}

private struct OpenBurnSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openBurnSettings: () -> Void {
        get { self[OpenBurnSettingsKey.self] }
        set { self[OpenBurnSettingsKey.self] = newValue }
    }
}
