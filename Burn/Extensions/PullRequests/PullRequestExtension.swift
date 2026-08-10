import AppKit
import SwiftUI

@Observable
@MainActor
final class PullRequestExtension: BurnExtension {
    static let ownersKey = "github-pr.owners"
    static let forgejoHostKey = "github-pr.forgejoHost"
    static let forgejoTokenService = "burn.forgejo.token"

    let id = "github-pr"
    let displayName = "PRs"

    let usageService: UsageService
    var prs: [PullRequest] = []
    var errorMessage: String?
    var truncated = false
    var isLoading = false
    var lastRefresh: Date?

    let hostStore: GitHostStore

    /// Set by the detail screen so the list can flash the row that just changed.
    var lastSavedHostId: UUID?

    init(usageService: UsageService, hostStore: GitHostStore? = nil) {
        self.usageService = usageService
        self.hostStore = hostStore ?? GitHostStore()
    }

    /// Tokens are read inside the fetch, never here: a keychain prompt on the main actor freezes the UI.
    private func plans() -> [HostFetchPlan] {
        hostStore.hosts.map { host in
            HostFetchPlan(
                host: host,
                legacyService: host.adoptsLegacyToken ? hostStore.legacyTokenService : nil
            )
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        // Re-read on every refresh: a token added or rebound since launch shouldn't need a restart.
        let plans = plans()
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        // The rolling 7-day week window can reach into the previous month, so fetch from
        // whichever start is earlier — otherwise weekPRs undercounts near the start of a month.
        let fetchStart = min(monthStart, usageService.usageData.weekStart)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let results = await withTaskGroup(of: Attempt.self) { group in
                for plan in plans {
                    group.addTask { await Self.fetch(plan, since: fetchStart) }
                }
                var collected: [Attempt] = []
                for await attempt in group { collected.append(attempt) }
                return collected
            }

            // One host failing shouldn't blank out the others' PRs.
            let fetched = results.compactMap(\.result)
            self.prs = fetched.flatMap(\.prs).sorted { $0.effectiveDate > $1.effectiveDate }
            self.truncated = fetched.contains(where: \.truncated)
            let errors = results.compactMap(\.errorMessage)
            self.errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
            for id in results.compactMap(\.adoptedHostId) {
                self.hostStore.clearLegacyAdoption(id)
            }
            self.lastRefresh = Date()
            self.isLoading = false
        }
    }

    private struct HostFetchPlan: Sendable {
        let host: GitHostConfig
        let legacyService: String?
    }

    private nonisolated static func fetch(_ plan: HostFetchPlan, since: Date) async -> Attempt {
        if plan.host.usesGitHubCLI {
            return await attempt {
                try await GitHubPRService.fetchAll(since: since, owners: plan.host.owners)
            }
        }

        let lookup = resolveToken(plan)
        guard let token = lookup.token, let config = ForgejoConfig(host: plan.host.host, token: token) else {
            return Attempt(result: nil, errorMessage: lookup.issue, adoptedHostId: nil)
        }
        var attempt = await attempt {
            try await ForgejoPRService.fetchAll(config: config, since: since, owners: plan.host.owners)
        }
        attempt.adoptedHostId = lookup.adopted ? plan.host.id : nil
        return attempt
    }

    /// Runs off the main actor so the one-time authorization dialog can't block the popover.
    private nonisolated static func resolveToken(
        _ plan: HostFetchPlan
    ) -> (token: String?, issue: String?, adopted: Bool) {
        switch KeychainStore.read(service: plan.host.tokenService) {
        case .value(let token):
            return (token, nil, false)
        case .refused(let status):
            return (nil, "The keychain refused the \(plan.host.label) token (\(status)). Re-enter it in settings.", false)
        case .missing:
            guard let legacyService = plan.legacyService,
                  case .value(let token) = KeychainStore.read(service: legacyService) else {
                return (nil, "No token stored for \(plan.host.label). Add one in settings.", false)
            }
            KeychainStore.write(token, service: plan.host.tokenService)
            return (token, nil, true)
        }
    }

    private struct Attempt: Sendable {
        let result: PRFetchResult?
        let errorMessage: String?
        var adoptedHostId: UUID?
    }

    private nonisolated static func attempt(_ work: () async throws -> PRFetchResult) async -> Attempt {
        do {
            return Attempt(result: try await work(), errorMessage: nil)
        } catch {
            return Attempt(result: nil, errorMessage: error.localizedDescription)
        }
    }

    func settingsView() -> AnyView? {
        AnyView(HostsListView(ext: self))
    }

    var todayPRs: [PullRequest] {
        let cal = Calendar.current
        let today = Date()
        return prs.filter { cal.isDate($0.effectiveDate, inSameDayAs: today) }
    }

    var weekPRs: [PullRequest] {
        let data = usageService.usageData
        guard data.weekStart != data.weekEnd else { return todayPRs }
        let start = Calendar.current.startOfDay(for: data.weekStart)
        return prs.filter { $0.effectiveDate >= start }
    }

    var monthPRs: [PullRequest] {
        let cal = Calendar.current
        let now = Date()
        let monthComps = cal.dateComponents([.year, .month], from: now)
        return prs.filter {
            let prComps = cal.dateComponents([.year, .month], from: $0.effectiveDate)
            return prComps.year == monthComps.year && prComps.month == monthComps.month
        }
    }

    private func openPRs(in list: [PullRequest]) -> [PullRequest] { list.filter { !$0.isMerged } }
    private func mergedPRs(in list: [PullRequest]) -> [PullRequest] { list.filter { $0.isMerged } }

    /// An open PR is open regardless of when it was opened, so unlike the counts above this list
    /// deliberately isn't scoped to a period — that's the whole fix.
    var openPRs: [PullRequest] { openPRs(in: prs) }

    func mergedPRs(for period: PRPeriod) -> [PullRequest] {
        switch period {
        case .today: return mergedPRs(in: todayPRs)
        case .week:  return mergedPRs(in: weekPRs)
        case .month: return mergedPRs(in: monthPRs)
        }
    }

    private func avgCost(total: Double, count: Int) -> Double? {
        count > 0 ? total / Double(count) : nil
    }

    /// `refresh()` only pulls PR history back to the start of the current month, so there's no
    /// cross-month data to average. "Typical" here is a run rate off month-to-date instead —
    /// how many PRs merge per day this month, scaled to the period.
    private var monthToDateMergedRate: Double? {
        let elapsed = Calendar.current.component(.day, from: Date())
        guard elapsed > 0 else { return nil }
        return Double(mergedPRs(for: .month).count) / Double(elapsed)
    }

    /// Every period-scoped number the tab shows, in one place — was five properties times three
    /// periods (today/week/month Count, OpenCount, MergedCount, avgCostPerPR, typicalMergedCount)
    /// before this, each a copy-pasted switch over the same three cases.
    func stats(for period: PRPeriod) -> PRPeriodStats {
        let prs: [PullRequest]
        let total: Double
        let typicalCount: Double?
        switch period {
        case .today:
            prs = todayPRs
            total = usageService.usageData.todayCost
            typicalCount = monthToDateMergedRate
        case .week:
            prs = weekPRs
            total = usageService.usageData.weekTotal
            typicalCount = monthToDateMergedRate.map { $0 * 7 }
        case .month:
            prs = monthPRs
            total = usageService.usageData.monthTotal
            typicalCount = monthToDateMergedRate.flatMap { rate in
                Calendar.current.range(of: .day, in: .month, for: Date()).map { rate * Double($0.count) }
            }
        }
        let merged = mergedPRs(in: prs).count
        return PRPeriodStats(
            mergedCount: merged,
            openCount: openPRs(in: prs).count,
            // Cost per PR divides by merged count only — open PRs haven't shipped yet.
            average: avgCost(total: total, count: merged),
            typicalCount: typicalCount
        )
    }

    var tabGlyph: TabGlyph { .asset("PRIcon") }

    var settingsSubtitle: String? {
        let count = hostStore.hosts.count
        return count == 1 ? "1 host connected" : "\(count) hosts connected"
    }

    var state: ExtensionState {
        if let message = errorMessage, prs.isEmpty { return .failed(message) }
        if lastRefresh == nil { return isLoading ? .loading : .dormant }
        let today = stats(for: .today)
        return today.mergedCount > 0 || today.openCount > 0 ? .live : .dormant
    }

    func statusLine() -> String? {
        guard lastRefresh != nil else { return nil }
        // A total failure has nothing to report; let the error card speak instead of claiming
        // "nothing merged" as if the read actually succeeded.
        if errorMessage != nil, prs.isEmpty { return nil }
        let merged = mergedPRs(in: todayPRs)
        guard let latest = merged.compactMap(\.mergedAt).max() else {
            let open = stats(for: .today).openCount
            return open > 0 ? "\(open) open today" : "Nothing merged today"
        }
        return "\(merged.count) merged, last \(Formatters.ago(latest))"
    }

    // ○ = open (pending circle), ⌥ = merged (two branches converging).
    // Unicode glyphs required; SF Symbols don't render in MenuBarExtra labels.
    func menuBarSegment() -> Text? {
        let today = stats(for: .today)
        if today.mergedCount > 0, let avg = today.average {
            return Text("○ \(today.openCount)  ⌥ \(today.mergedCount) \(String(format: "$%.0f", avg))")
        }
        return Text("○ \(today.openCount)  ⌥ \(today.mergedCount)")
    }

    func popoverTab() -> AnyView {
        AnyView(PullRequestTabView(ext: self))
    }
}

enum PRPeriod: CaseIterable, Hashable {
    case today, week, month

    var label: String {
        switch self {
        case .today: return "today"
        case .week:  return "this week"
        case .month: return "this month"
        }
    }

    var noun: String {
        switch self {
        case .today: return "day"
        case .week:  return "week"
        case .month: return "month"
        }
    }
}

/// One period's worth of numbers for the PR tab: the hero, the scope cards, and the pace track
/// all read from the same snapshot instead of each re-deriving it.
struct PRPeriodStats {
    let mergedCount: Int
    let openCount: Int
    let average: Double?
    let typicalCount: Double?
}

struct PullRequestTabView: View {
    let ext: PullRequestExtension

    @Environment(\.openBurnSettings) private var openSettings

    @State private var selectedPeriod: PRPeriod = PullRequestTabView.initialPeriod()

    /// Screenshot knob, same family as BURN_ACTIVE_TAB and BURN_DAY_OFFSET.
    private static func initialPeriod() -> PRPeriod {
        switch ProcessInfo.processInfo.environment["BURN_PR_PERIOD"] {
        case "today": return .today
        case "month": return .month
        default:      return .week
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch ext.state {
            case .loading:
                EmberLoadingBody()
            case .failed(let message):
                EmberErrorCard(
                    title: "Couldn't reach your hosts",
                    message: message,
                    isRetrying: ext.isLoading,
                    onSettings: openSettings,
                    onRetry: { ext.refresh() }
                )
            default:
                loaded
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Partial failures stay a banner: one dead host shouldn't hide the PRs the others returned.
    private var loaded: some View {
        VStack(spacing: 0) {
            if let error = ext.errorMessage {
                banner(error, symbol: "exclamationmark.triangle", color: Ember.accentDeep)
            }
            if ext.truncated {
                banner("Hit a host's result cap, so counts may be capped.", symbol: "exclamationmark.circle", color: Ember.accent)
            }
            hero
            scopeCards
            paceTrack
            listSection
        }
    }

    // MARK: - Hero

    private var stats: PRPeriodStats { ext.stats(for: selectedPeriod) }

    @ViewBuilder
    private var hero: some View {
        if let avg = stats.average {
            EmberHero(cost: avg) { heroCaption }
        } else {
            EmberHero(primary: "\(stats.mergedCount)", secondary: nil) { heroCaption }
        }
    }

    private var heroCaption: some View {
        Group {
            if stats.average != nil {
                Text("per shipped PR \(selectedPeriod.label) · ")
                    + Text("\(stats.mergedCount)").bold().foregroundColor(Ember.text(0.9))
                    + Text(" merged, ")
                    + Text("\(stats.openCount)").bold().foregroundColor(Ember.text(0.9))
                    + Text(" open")
            } else {
                Text("merged \(selectedPeriod.label) · nothing to divide cost into yet")
            }
        }
    }

    // MARK: - Scope cards

    /// Today/Week/Month tiles, replacing the old segmented pill (Turn 11) so the switcher itself
    /// shows count + cost-per-PR instead of a bare label.
    private var scopeCards: some View {
        HStack(spacing: 8) {
            ForEach(PRPeriod.allCases, id: \.self) { period in
                let periodStats = ext.stats(for: period)
                EmberScopeCard(
                    label: cardTitle(period),
                    count: periodStats.mergedCount,
                    costPerPR: periodStats.average,
                    isSelected: selectedPeriod == period,
                    onSelect: { withAnimation(EmberMotion.pill) { selectedPeriod = period } }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// A short noun for the card face ("Today", "Week"), distinct from .label's sentence form
    /// ("today", "this week") — the month card names the actual month, so it can't be pure either.
    private func cardTitle(_ period: PRPeriod) -> String {
        switch period {
        case .today: return "Today"
        case .week:  return "Week"
        case .month: return Formatters.monthLabel(Date())
        }
    }

    /// Repurposes the pace-bar pattern from the cost track: selected scope's merged count against
    /// its own typical baseline, the same shape Usage's pace track uses for cost.
    @ViewBuilder
    private var paceTrack: some View {
        let current = Double(stats.mergedCount)
        if let typical = stats.typicalCount, typical > 0 {
            let scale = max(current, typical) * 1.25
            EmberTrack(
                fill: scale > 0 ? current / scale : 0,
                tick: scale > 0 ? typical / scale : nil,
                leading: "\(selectedPeriod.label) \(stats.mergedCount)",
                trailing: "typical \(selectedPeriod.noun) \(formatTypicalCount(typical))"
            )
            .padding(.top, 14)
            .padding(.bottom, 16)
        } else {
            Spacer(minLength: 14)
        }
    }

    /// A day's run rate is often well under 1 PR — rounding that to "0" reads as "no baseline"
    /// instead of "a small one", so keep a decimal below 1.
    private func formatTypicalCount(_ value: Double) -> String {
        value < 1 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    // MARK: - List

    private var listSection: some View {
        VStack(spacing: 0) {
            Text("Pull requests")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Ember.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            prList
        }
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }

    /// Open and merged are shown as two labeled groups rather than one flat list — otherwise an
    /// "0 merged today" card sitting right above a list of week-old open PRs reads as a
    /// contradiction, even though open PRs are deliberately never scoped to the period.
    @ViewBuilder
    private var prList: some View {
        let open = ext.openPRs.sorted { $0.effectiveDate > $1.effectiveDate }
        let merged = ext.mergedPRs(for: selectedPeriod).sorted { $0.effectiveDate > $1.effectiveDate }
        if open.isEmpty && merged.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else if open.count + merged.count > 4 {
            ScrollView {
                groupedRows(open: open, merged: merged)
            }
            // Tall enough to show a few rows past the fold, not just a sliver of one.
            .frame(maxHeight: 240)
            .padding(.bottom, 4)
        } else {
            groupedRows(open: open, merged: merged)
                .padding(.bottom, 4)
        }
    }

    private func groupedRows(open: [PullRequest], merged: [PullRequest]) -> some View {
        VStack(spacing: 0) {
            if !open.isEmpty {
                sectionLabel("Open")
                rows(open)
            }
            if !merged.isEmpty {
                sectionLabel("Merged \(selectedPeriod.label)")
                rows(merged)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Ember.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func rows(_ prs: [PullRequest]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                PRRow(pr: pr)
                if idx < prs.count - 1 {
                    Rectangle()
                        .fill(Ember.fill(0.06))
                        .frame(height: 1)
                        .padding(.leading, 33)
                }
            }
        }
    }

    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text).lineLimit(2)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var emptyMessage: String {
        if ext.lastRefresh == nil && ext.isLoading { return "Loading…" }
        return "No PRs \(selectedPeriod.label)"
    }
}

private struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                dot
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ember.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.label)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ember.text(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .emberHoverRow(cornerRadius: 0)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    @ViewBuilder
    private var dot: some View {
        if pr.isMerged {
            Circle().fill(Ember.accent).frame(width: 7, height: 7)
        } else {
            Circle()
                .strokeBorder(Ember.accent.opacity(0.75), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }

    private var subtitle: String {
        var parts = [pr.repository.nameWithOwner]
        if let host = pr.hostLabel { parts.append(host) }
        if let merged = pr.mergedAt {
            parts.append(Formatters.ago(merged))
        } else {
            parts.append("open \(Formatters.ago(pr.createdAt))")
        }
        return parts.joined(separator: " · ")
    }
}
