import SwiftUI

@MainActor
final class UsageExtension: BurnExtension {
    let id = "usage"
    let displayName = "Usage"

    let service: UsageService
    let settings: SettingsStore

    init(service: UsageService, settings: SettingsStore) {
        self.service = service
        self.settings = settings
    }

    func refresh() {
        service.refresh()
    }

    func menuBarSegment() -> Text? {
        guard service.usageData.lastRefreshDate != .distantPast else { return nil }
        let amount = String(format: "$%.2f", service.usageData.todayCost)
        switch settings.menuBarDisplay {
        case .icon:    return Text("🔥")
        case .amount:  return Text(amount)
        case .both:    return Text("🔥 \(amount)")
        }
    }

    func popoverTab() -> AnyView {
        AnyView(UsageDashboardView(service: service, settings: settings))
    }
}
