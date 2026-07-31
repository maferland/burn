import SwiftUI

@MainActor
final class CodexExtension: BurnExtension {
    let id = "codex"
    let displayName = "Codex"

    let service: CodexUsageService
    let settings: SettingsStore

    init(service: CodexUsageService, settings: SettingsStore) {
        self.service = service
        self.settings = settings
    }

    func refresh() {
        service.refresh()
    }

    func menuBarSegment() -> Text? {
        guard !service.response.isEmpty else { return nil }
        let amount = "~" + String(format: "$%.0f", service.response.todayCost)
        switch settings.menuBarDisplay {
        case .icon:    return Text("◇")
        case .amount:  return Text(amount)
        case .both:    return Text("◇ \(amount)")
        }
    }

    func popoverTab() -> AnyView {
        AnyView(CodexDashboardView(service: service))
    }
}

/// Placeholder layout pending the Codex tab design; deliberately plain.
private struct CodexDashboardView: View {
    let service: CodexUsageService

    var body: some View {
        VStack(spacing: 0) {
            if !service.isInstalled {
                message("Codex CLI not found", detail: "Install Codex to track its usage here.")
            } else if service.response.isEmpty {
                message("No Codex sessions yet", detail: "Run Codex once and refresh.")
            } else {
                hero
                Divider()
                quotaSection
                totalsSection
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hero: some View {
        VStack(spacing: 4) {
            Text("~" + Formatters.cost(service.response.todayCost))
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Estimated at API rates")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var quotaSection: some View {
        if let limits = service.response.rateLimits {
            VStack(alignment: .leading, spacing: 6) {
                quotaRow("5-hour window", limits.primary)
                quotaRow("Weekly", limits.secondary)
                Text("As of \(Formatters.relativeTime(limits.capturedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
        }
    }

    @ViewBuilder
    private func quotaRow(_ label: String, _ window: CodexRateLimitWindow?) -> some View {
        if let window {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", window.usedPercent))
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var totalsSection: some View {
        HStack(spacing: 8) {
            StatCard(label: "This Week", value: "~" + Formatters.cost(service.response.cost(inLast: 7)))
            StatCard(label: "This Month", value: "~" + Formatters.cost(service.response.monthCost()))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 14)
    }
}
