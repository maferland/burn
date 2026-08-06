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

    let providers: ProviderStore?

    var providerUsage: ProviderUsage {
        ProviderUsage(claude: service, codex: codexService, counted: providers?.countedInTotal)
    }

    init(
        service: UsageService,
        codexService: CodexUsageService,
        settings: SettingsStore,
        providers: ProviderStore? = nil
    ) {
        self.service = service
        self.codexService = codexService
        self.settings = settings
        self.providers = providers
        let stored = UserDefaults.standard.string(forKey: Self.scopeKey)
        self.scope = Provider(rawValue: stored ?? "").map(UsageScope.provider)
            ?? (stored == "all" ? .all : .provider(.claude))
    }

    var tabGlyph: TabGlyph { .asset }

    func refresh() {
        service.refresh()
        codexService.refresh()
    }

    /// Loading only counts as loading before the first read; after that a refresh happens under real numbers.
    var state: ExtensionState {
        if let message = service.errorMessage { return .failed(message) }
        if service.lastResponse == nil { return service.isLoading ? .loading : .dormant }
        return providerUsage.usageData(scope: scope).todayCost > 0 ? .live : .dormant
    }

    func statusLine() -> String? {
        let data = service.usageData
        guard data.lastRefreshDate != .distantPast else { return nil }
        if let comparison = Formatters.comparison(value: data.todayCost, baseline: service.typicalDayCost) {
            return comparison
        }
        // Same rule as the hero: a zero reads as broken, so say what actually happened.
        guard data.todayCost > 0 else { return "Nothing burned yet" }
        return "\(Formatters.costRounded(data.todayCost)) today"
    }

    func menuBarSegment() -> Text? {
        guard service.usageData.lastRefreshDate != .distantPast else { return nil }
        return Text("🔥 " + String(format: "$%.0f", service.usageData.todayCost))
    }

    func popoverTab() -> AnyView {
        AnyView(UsageDashboardView(ext: self, service: service, settings: settings))
    }
}
