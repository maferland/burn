import SwiftUI

@MainActor
final class LimitsExtension: BurnExtension {
    static let menuBarKey = "limits.showsInMenuBar"

    let id = "limits"
    let displayName = "Limits"

    let service: LimitsService

    init(service: LimitsService) {
        self.service = service
        self.showsInMenuBar = UserDefaults.standard.bool(forKey: Self.menuBarKey)
    }

    /// Off by default: the cost segments already own the menu bar.
    var showsInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showsInMenuBar, forKey: Self.menuBarKey) }
    }

    var tabGlyph: TabGlyph { .symbol("gauge.with.needle") }

    var settingsSubtitle: String? { "Plan headroom per account" }

    func refresh() {
        service.refresh()
    }

    var state: ExtensionState { service.state }

    func statusLine() -> String? {
        if let (snapshot, window) = service.response.tightest {
            let prefix = service.response.accounts.count > 1
                ? snapshot.account.label
                : (snapshot.planLabel ?? snapshot.account.provider.displayName)
            return "\(prefix) · \(Formatters.percent(window.remainingPercent)) of \(window.kind.phrase) left"
        }
        guard let spend = service.response.accounts.compactMap(\.spend).first else { return nil }
        return Formatters.spendLine(spend)
    }

    func menuBarSegment() -> Text? {
        guard showsInMenuBar, let (_, window) = service.response.tightest else { return nil }
        return Text("◔ \(Formatters.percent(window.remainingPercent))")
    }

    func popoverTab() -> AnyView {
        AnyView(LimitsDashboardView(service: service))
    }

    func settingsView() -> AnyView? {
        AnyView(LimitsSettingsView(ext: self))
    }
}
