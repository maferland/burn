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

    var owners: [String] {
        didSet { UserDefaults.standard.set(owners, forKey: Self.ownersKey) }
    }

    var forgejoHost: String {
        didSet { UserDefaults.standard.set(forgejoHost, forKey: Self.forgejoHostKey) }
    }

    private var forgejoToken: String?

    var hasForgejoToken: Bool { forgejoToken != nil }

    init(usageService: UsageService) {
        self.usageService = usageService
        self.owners = UserDefaults.standard.array(forKey: Self.ownersKey) as? [String] ?? []
        self.forgejoHost = UserDefaults.standard.string(forKey: Self.forgejoHostKey) ?? ""
        self.forgejoToken = KeychainStore.read(service: Self.forgejoTokenService)
    }

    func setForgejoToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(service: Self.forgejoTokenService)
            forgejoToken = nil
        } else {
            KeychainStore.write(trimmed, service: Self.forgejoTokenService)
            forgejoToken = trimmed
        }
    }

    private var forgejoConfig: ForgejoConfig? {
        guard let forgejoToken else { return nil }
        return ForgejoConfig(host: forgejoHost, token: forgejoToken)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let owners = self.owners
        let config = forgejoConfig
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        // The rolling 7-day week window can reach into the previous month, so fetch from
        // whichever start is earlier — otherwise weekPRs undercounts near the start of a month.
        let fetchStart = min(monthStart, usageService.usageData.weekStart)
        Task { @MainActor [weak self] in
            guard let self else { return }
            async let github = Self.attempt { try await GitHubPRService.fetchAll(since: fetchStart, owners: owners) }
            async let forgejo = Self.attempt {
                guard let config else { return .empty }
                return try await ForgejoPRService.fetchAll(config: config, since: fetchStart, owners: owners)
            }
            let (githubResult, forgejoResult) = await (github, forgejo)
            let results = [githubResult, forgejoResult]

            // One host failing shouldn't blank out the other's PRs.
            let fetched = results.compactMap(\.result)
            self.prs = fetched.flatMap(\.prs).sorted { ($0.mergedAt ?? $0.createdAt) > ($1.mergedAt ?? $1.createdAt) }
            self.truncated = fetched.contains(where: \.truncated)
            let errors = results.compactMap(\.errorMessage)
            self.errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
            self.lastRefresh = Date()
            self.isLoading = false
        }
    }

    private struct Attempt {
        let result: PRFetchResult?
        let errorMessage: String?
    }

    private nonisolated static func attempt(_ work: () async throws -> PRFetchResult) async -> Attempt {
        do {
            return Attempt(result: try await work(), errorMessage: nil)
        } catch {
            return Attempt(result: nil, errorMessage: error.localizedDescription)
        }
    }

    func settingsView() -> AnyView? {
        AnyView(PullRequestSettingsView(ext: self))
    }

    // For open PRs: anchor on createdAt. For merged: anchor on mergedAt.
    private func effectiveDate(_ pr: PullRequest) -> Date {
        pr.mergedAt ?? pr.createdAt
    }

    var todayPRs: [PullRequest] {
        let cal = Calendar.current
        let today = Date()
        return prs.filter { cal.isDate(effectiveDate($0), inSameDayAs: today) }
    }

    var weekPRs: [PullRequest] {
        let data = usageService.usageData
        guard data.weekStart != data.weekEnd else { return todayPRs }
        let start = Calendar.current.startOfDay(for: data.weekStart)
        return prs.filter { effectiveDate($0) >= start }
    }

    var monthPRs: [PullRequest] {
        let cal = Calendar.current
        let now = Date()
        let monthComps = cal.dateComponents([.year, .month], from: now)
        return prs.filter {
            let prComps = cal.dateComponents([.year, .month], from: effectiveDate($0))
            return prComps.year == monthComps.year && prComps.month == monthComps.month
        }
    }

    private func openPRs(in list: [PullRequest]) -> [PullRequest] { list.filter { !$0.isMerged } }
    private func mergedPRs(in list: [PullRequest]) -> [PullRequest] { list.filter { $0.isMerged } }

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
        AnyView(PullRequestTabView(ext: self))
    }
}

enum PRPeriod { case today, week, month }

struct PullRequestTabView: View {
    let ext: PullRequestExtension

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
                warningBanner("Hit a host's result cap — counts may be capped.")
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
            Text("PRs").font(.headline)
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

    private var filteredPRs: [PullRequest] {
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
    let pr: PullRequest
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
                        if let hostLabel = pr.hostLabel {
                            Text("· \(hostLabel)")
                                .lineLimit(1)
                        }
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

private struct PullRequestSettingsView: View {
    let ext: PullRequestExtension
    @State private var input: String = ""
    @State private var hostInput: String = ""
    @State private var tokenInput: String = ""
    @FocusState private var focused: Bool
    @FocusState private var hostFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            field(label: "Orgs") {
                TextField("all", text: $input)
                    .focused($focused)
                    .onAppear { input = ext.owners.joined(separator: ", ") }
                    .onSubmit(commitOwners)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commitOwners() }
                    }
            }
            field(label: "Forgejo") {
                TextField("git.example.com", text: $hostInput)
                    .focused($hostFocused)
                    .onAppear { hostInput = ext.forgejoHost }
                    .onSubmit(commitHost)
                    .onChange(of: hostFocused) { _, isFocused in
                        if !isFocused { commitHost() }
                    }
            }
            field(label: "Token") {
                SecureField(ext.hasForgejoToken ? "stored" : "read:issue token", text: $tokenInput)
                    .onSubmit(commitToken)
            }
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            content()
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(width: 130)
        }
    }

    private func commitOwners() {
        let parsed = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parsed != ext.owners else { return }
        ext.owners = parsed
        ext.refresh()
    }

    private func commitHost() {
        let trimmed = hostInput.trimmingCharacters(in: .whitespaces)
        guard trimmed != ext.forgejoHost else { return }
        ext.forgejoHost = trimmed
        ext.refresh()
    }

    private func commitToken() {
        guard !tokenInput.isEmpty else { return }
        ext.setForgejoToken(tokenInput)
        tokenInput = ""
        ext.refresh()
    }
}
