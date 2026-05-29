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

    func menuBarSegment() -> AnyView? {
        AnyView(UsageMenuBarSegment(service: service, settings: settings))
    }

    func popoverTab() -> AnyView {
        AnyView(UsageDashboardView(service: service, settings: settings))
    }
}

struct UsageMenuBarSegment: View {
    let service: UsageService
    let settings: SettingsStore

    private var hasData: Bool {
        service.usageData.lastRefreshDate != .distantPast
    }

    var body: some View {
        if !hasData {
            Image(nsImage: MenuBarLabel.loadMenuBarIcon())
        } else {
            let amount = String(format: "$%.2f", service.usageData.todayCost)
            switch settings.menuBarDisplay {
            case .icon:
                Image(nsImage: MenuBarLabel.loadMenuBarIcon())
            case .amount:
                Text(amount)
            case .both:
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarLabel.loadMenuBarIcon())
                    Text(amount)
                }
            }
        }
    }
}
