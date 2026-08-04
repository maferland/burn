import SwiftUI

@MainActor
final class UsageExtension: BurnExtension {
    let id = "usage"
    let displayName = "Usage"

    static let scopeKey = "usage.scope"

    let service: UsageService
    let codexService: CodexUsageService
    let settings: SettingsStore

    /// Which provider the tab is scoped to, remembered across launches.
    var scope: UsageScope {
        didSet { UserDefaults.standard.set(scope.id, forKey: Self.scopeKey) }
    }

    var providerUsage: ProviderUsage { ProviderUsage(claude: service, codex: codexService) }

    init(service: UsageService, codexService: CodexUsageService, settings: SettingsStore) {
        self.service = service
        self.codexService = codexService
        self.settings = settings
        let stored = UserDefaults.standard.string(forKey: Self.scopeKey)
        self.scope = Provider(rawValue: stored ?? "").map(UsageScope.provider)
            ?? (stored == "all" ? .all : .provider(.claude))
    }

    var tabGlyph: TabGlyph { .asset }

    func refresh() {
        service.refresh()
        codexService.refresh()
    }

    func statusLine() -> String? {
        let data = service.usageData
        guard data.lastRefreshDate != .distantPast else { return nil }
        if let comparison = Formatters.comparison(value: data.todayCost, baseline: service.typicalDayCost) {
            return comparison
        }
        return "\(Formatters.costRounded(data.todayCost)) today"
    }

    func menuBarSegment() -> Text? {
        guard service.usageData.lastRefreshDate != .distantPast else { return nil }
        let amount = String(format: "$%.0f", service.usageData.todayCost)
        switch settings.menuBarDisplay {
        case .icon:    return Text("🔥")
        case .amount:  return Text(amount)
        case .both:    return Text("🔥 \(amount)")
        }
    }

    func popoverTab() -> AnyView {
        AnyView(UsageDashboardView(ext: self, service: service, settings: settings))
    }
}
