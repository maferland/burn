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

    var tabGlyph: TabGlyph { .symbol("chevron.left.forwardslash.chevron.right") }

    var isConfigured: Bool { CodexSessionReader.isConfigured }

    var settingsSubtitle: String? {
        isConfigured ? "~/.codex/sessions" : "Not signed in — run codex once"
    }

    func refresh() {
        service.refresh()
    }

    func statusLine() -> String? {
        guard !service.response.isEmpty || service.response.rateLimits != nil else { return nil }
        if let limits = service.response.rateLimits, let primary = limits.primary {
            let plan = limits.planType.map { $0.capitalized + " · " } ?? ""
            return "\(plan)\(Int(primary.usedPercent.rounded()))% of 5-hour window"
        }
        return "~\(Formatters.costRounded(service.response.todayCost)) today, estimated"
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
        AnyView(CodexDashboardView(service: service, settings: settings))
    }
}

struct CodexDashboardView: View {
    let service: CodexUsageService
    let settings: SettingsStore

    @State private var selectedDayId: String?

    private var response: CodexUsageResponse { service.response }

    private var days: [CodexDailyUsage] { response.last7Days() }

    private var selectedDay: CodexDailyUsage? {
        if let id = selectedDayId, let day = days.first(where: { $0.id == id }) { return day }
        return days.last
    }

    var body: some View {
        VStack(spacing: 0) {
            if !service.isInstalled {
                EmberEmptyState(
                    title: "Codex CLI not found",
                    detail: "Nothing at ~/.codex yet. Install Codex and this tab fills in."
                )
            } else if response.isEmpty && response.rateLimits == nil {
                EmberEmptyState(
                    title: "No Codex sessions yet",
                    detail: "Run Codex once, then refresh. Usage comes from its rollout logs."
                )
            } else {
                hero
                quotaTrack
                quotaSection
                modelSection
                contextStrip
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    private var hero: some View {
        EmberHero(cost: selectedDay?.estimatedCost ?? 0, prefix: "~") {
            let label = selectedDay.map { Formatters.dayLabel($0.date).lowercased() } ?? "today"
            Text("\(label) · estimated at API rates")
        }
    }

    /// The 5-hour rolling window gets Ember's pace track: it's the number that decides whether Codex stops.
    @ViewBuilder
    private var quotaTrack: some View {
        if let primary = response.rateLimits?.primary {
            EmberTrack(
                fill: primary.usedPercent / 100,
                tick: nil,
                leading: "5-hour window \(Int(primary.usedPercent.rounded()))%",
                trailing: primary.resetsAt.map(Formatters.resetLabel) ?? ""
            )
            .padding(.top, 16)
            .padding(.bottom, 18)
        } else {
            EmberNote(text: "No quota snapshot yet. Codex only writes one while it runs.")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var quotaSection: some View {
        if let limits = response.rateLimits {
            EmberSection(title: "Quota") {
                VStack(spacing: 10) {
                    if let weekly = limits.secondary {
                        EmberBarRow(
                            label: "Weekly",
                            fraction: weekly.usedPercent / 100,
                            value: "\(Int(weekly.usedPercent.rounded()))%",
                            emphasis: 0.7
                        )
                    }
                }
                EmberNote(text: quotaNote(limits))
            }
        }
    }

    private func quotaNote(_ limits: CodexRateLimits) -> String {
        var parts = ["as of \(Formatters.ago(limits.capturedAt))"]
        if let weekly = limits.secondary?.resetsAt {
            parts.append(Formatters.resetLabel(weekly))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Models

    @ViewBuilder
    private var modelSection: some View {
        if let day = selectedDay, !day.modelBreakdowns.isEmpty {
            let ranked = day.modelBreakdowns.sorted { $0.estimatedCost > $1.estimatedCost }
            let leader = ranked.first?.estimatedCost ?? 0
            EmberSection(title: "By model", trailing: cacheNote(for: day)) {
                VStack(spacing: 10) {
                    ForEach(Array(ranked.enumerated()), id: \.element.modelName) { index, model in
                        EmberBarRow(
                            label: Formatters.codexModelLabel(model.modelName),
                            fraction: leader > 0 ? model.estimatedCost / leader : 0,
                            value: "~" + Formatters.cost(model.estimatedCost),
                            emphasis: index == 0 ? 1.0 : (index == 1 ? 0.55 : 0.4)
                        )
                    }
                }
            }
        }
    }

    private func cacheNote(for day: CodexDailyUsage) -> String? {
        guard day.tokens.inputTokens > 0 else { return nil }
        let share = Int((Double(day.tokens.cachedInputTokens) / Double(day.tokens.inputTokens) * 100).rounded())
        return "\(share)% cached input"
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        let maxCost = days.map(\.estimatedCost).max() ?? 0
        return VStack(spacing: 0) {
            EmberContextStrip(
                bars: days.map { .init(id: $0.id, fraction: maxCost > 0 ? $0.estimatedCost / maxCost : 0) },
                selectedId: selectedDay?.id,
                leading: .init(label: "Last 7 days", value: "~" + Formatters.costRounded(response.cost(inLast: 7))),
                trailing: .init(label: Formatters.monthLabel(Date()), value: "~" + Formatters.costRounded(response.monthCost())),
                onSelect: { selectedDayId = $0 },
                onOpen: { _ in }
            )
            if response.skippedCompressedFiles > 0 {
                EmberNote(text: "\(response.skippedCompressedFiles) archived sessions are compressed and not counted.")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }
}
