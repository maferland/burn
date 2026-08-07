import SwiftUI

@Observable
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

    /// Same fallback the status line already has: a usage-based seat reports no windows, only spend.
    func menuBarSegment() -> Text? {
        guard showsInMenuBar else { return nil }
        if let (_, window) = service.response.tightest {
            return Text("◔ \(Formatters.percent(window.remainingPercent))")
        }
        guard let spend = service.response.accounts.compactMap(\.spend).first else { return nil }
        guard let fraction = spend.fraction else {
            return Text("◔ \(Formatters.costRounded(spend.usedDollars))")
        }
        return Text("◔ \(Formatters.percent((1 - fraction) * 100))")
    }

    func popoverTab() -> AnyView {
        AnyView(LimitsDashboardView(service: service))
    }

    func settingsView() -> AnyView? {
        AnyView(LimitsSettingsView(ext: self))
    }
}
