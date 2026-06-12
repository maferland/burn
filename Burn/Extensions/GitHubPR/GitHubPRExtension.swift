import AppKit
import SwiftUI

@Observable
@MainActor
final class GitHubPRExtension: BurnExtension {
    static let ownersKey = "github-pr.owners"

    let id = "github-pr"
    let displayName = "GitHub"

    let usageService: UsageService
    var prs: [GitHubPR] = []
    var errorMessage: String?
    var truncated = false
    var isLoading = false
    var lastRefresh: Date?

    var owners: [String] {
        didSet { UserDefaults.standard.set(owners, forKey: Self.ownersKey) }
    }

    init(usageService: UsageService) {
        self.usageService = usageService
        self.owners = UserDefaults.standard.array(forKey: Self.ownersKey) as? [String] ?? []
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let owners = self.owners
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        // The rolling 7-day week window can reach into the previous month, so fetch from
        // whichever start is earlier — otherwise weekPRs undercounts near the start of a month.
        let fetchStart = min(monthStart, usageService.usageData.weekStart)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fetched = try await GitHubPRService.fetchAll(since: fetchStart, owners: owners)
                self.prs = fetched.prs.sorted { ($0.mergedAt ?? $0.createdAt) > ($1.mergedAt ?? $1.createdAt) }
                self.truncated = fetched.truncated
                self.lastRefresh = Date()
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func settingsView() -> AnyView? {
        AnyView(GitHubPRSettingsView(ext: self))
    }

    // For open PRs: anchor on createdAt. For merged: anchor on mergedAt.
    private func effectiveDate(_ pr: GitHubPR) -> Date {
        pr.mergedAt ?? pr.createdAt
    }

    var todayPRs: [GitHubPR] {
        let cal = Calendar.current
        let today = Date()
        return prs.filter { cal.isDate(effectiveDate($0), inSameDayAs: today) }
    }

    var weekPRs: [GitHubPR] {
        let data = usageService.usageData
        guard data.weekStart != data.weekEnd else { return todayPRs }
        let start = Calendar.current.startOfDay(for: data.weekStart)
        return prs.filter { effectiveDate($0) >= start }
    }

    var monthPRs: [GitHubPR] {
        let cal = Calendar.current
        let now = Date()
        let monthComps = cal.dateComponents([.year, .month], from: now)
        return prs.filter {
            let prComps = cal.dateComponents([.year, .month], from: effectiveDate($0))
            return prComps.year == monthComps.year && prComps.month == monthComps.month
        }
    }

    private func openPRs(in list: [GitHubPR]) -> [GitHubPR] { list.filter { !$0.isMerged } }
    private func mergedPRs(in list: [GitHubPR]) -> [GitHubPR] { list.filter { $0.isMerged } }

    var todayCount: Int { todayPRs.count }
    var weekCount: Int { weekPRs.count }
    var monthCount: Int { monthPRs.count }

    var todayOpenCount: Int { openPRs(in: todayPRs).count }
    var weekOpenCount: Int    { openPRs(in: weekPRs).count }
    var monthOpenCount: Int   { openPRs(in: monthPRs).count }

    var todayMergedCount: Int { mergedPRs(in: todayPRs).count }
    var weekMergedCount: Int  { mergedPRs(in: weekPRs).count }
    var monthMergedCount: Int { mergedPRs(in: monthPRs).count }

    private func avgCost(total: Double, count: Int) -> Double? {
        count > 0 ? total / Double(count) : nil
    }

    // Cost per PR divides by merged count only — open PRs haven't shipped yet.
    var avgCostPerPR: Double? { avgCost(total: usageService.usageData.todayCost, count: todayMergedCount) }
    var avgCostPerPRWeek: Double? { avgCost(total: usageService.usageData.weekTotal, count: mergedPRs(in: weekPRs).count) }
    var avgCostPerPRMonth: Double? { avgCost(total: usageService.usageData.monthTotal, count: mergedPRs(in: monthPRs).count) }

    // ○ = open (pending circle), ⌥ = merged (two branches converging).
    // Unicode glyphs required; SF Symbols don't render in MenuBarExtra labels.
    func menuBarSegment() -> Text? {
        let open = todayOpenCount
        let merged = todayMergedCount
        if merged > 0, let avg = avgCostPerPR {
            return Text("○ \(open)  ⌥ \(merged) \(String(format: "$%.0f", avg))")
        }
        return Text("○ \(open)  ⌥ \(merged)")
    }

    func popoverTab() -> AnyView {
        AnyView(GitHubPRTabView(ext: self))
    }
}

enum PRPeriod { case today, week, month }

struct GitHubPRTabView: View {
    let ext: GitHubPRExtension

    @Environment(\.openBurnSettings) private var openSettings
    @Environment(\.burnTabBarVisible) private var tabBarVisible
    @State private var selectedPeriod: PRPeriod = .today

    var body: some View {
        VStack(spacing: 0) {
            if !tabBarVisible {
                header
                Divider()
            }
            if let error = ext.errorMessage {
                errorBanner(error)
            }
            if ext.truncated {
                warningBanner("Showing first \(GitHubPRService.fetchLimit) PRs — counts may be capped.")
            }
            cards
            Divider()
            prList
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("GitHub").font(.headline)
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warningBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption2)
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cards: some View {
        HStack(spacing: 8) {
            periodCard(.today, label: "Today", open: ext.todayOpenCount, merged: ext.todayMergedCount, avg: ext.avgCostPerPR)
            periodCard(.week,  label: "Week",  open: ext.weekOpenCount,  merged: ext.weekMergedCount,  avg: ext.avgCostPerPRWeek)
            periodCard(.month, label: "Month", open: ext.monthOpenCount, merged: ext.monthMergedCount, avg: ext.avgCostPerPRMonth)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func periodCard(_ period: PRPeriod, label: String, open: Int, merged: Int, avg: Double?) -> some View {
        StatCard(
            label: label,
            value: "○\(open)  ⌥\(merged)",
            subtitle: avg.map { "\(String(format: "$%.0f", $0)) / PR" } ?? "— / PR",
            isSelected: selectedPeriod == period,
            onTap: { selectedPeriod = period }
        )
    }

    private var filteredPRs: [GitHubPR] {
        switch selectedPeriod {
        case .today: return ext.todayPRs
        case .week:  return ext.weekPRs
        case .month: return ext.monthPRs
        }
    }

    private var emptyPeriodLabel: String {
        switch selectedPeriod {
        case .today: return "today"
        case .week:  return "this week"
        case .month: return "this month"
        }
    }

    @ViewBuilder
    private var prList: some View {
        let prs = filteredPRs
        if prs.isEmpty {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        } else {
            let costNote = activeAvg.map { Formatters.cost($0) }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                        PRRow(pr: pr, costNote: costNote)
                        if idx < prs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(.vertical, 2)
        }
    }

    private var activeAvg: Double? {
        switch selectedPeriod {
        case .today: return ext.avgCostPerPR
        case .week:  return ext.avgCostPerPRWeek
        case .month: return ext.avgCostPerPRMonth
        }
    }

    private var emptyMessage: String {
        if ext.lastRefresh == nil && ext.isLoading {
            return "Loading…"
        }
        return "No PRs \(emptyPeriodLabel)"
    }
}

private struct PRRow: View {
    let pr: GitHubPR
    let costNote: String?

    var body: some View {
        Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(pr.isMerged ? Color.purple : Color.green)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(pr.repository.nameWithOwner)
                            .lineLimit(1)
                        if let costNote {
                            Text("· \(costNote)")
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private struct GitHubPRSettingsView: View {
    let ext: GitHubPRExtension
    @State private var input: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text("Orgs").font(.caption)
            Spacer()
            TextField("all", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(width: 130)
                .focused($focused)
                .onAppear { input = ext.owners.joined(separator: ", ") }
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
        }
    }

    private func commit() {
        let parsed = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parsed != ext.owners else { return }
        ext.owners = parsed
        ext.refresh()
    }
}
