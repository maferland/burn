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
    private var forgejoTokenIssue: String?

    var hasForgejoToken: Bool { forgejoToken != nil }

    init(usageService: UsageService) {
        self.usageService = usageService
        self.owners = UserDefaults.standard.array(forKey: Self.ownersKey) as? [String] ?? []
        self.forgejoHost = UserDefaults.standard.string(forKey: Self.forgejoHostKey) ?? ""
        loadForgejoToken()
    }

    func setForgejoToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(service: Self.forgejoTokenService)
        } else {
            KeychainStore.write(trimmed, service: Self.forgejoTokenService)
        }
        loadForgejoToken()
    }

    /// Read back rather than trusting the write, so a keychain that refuses this build says so.
    private func loadForgejoToken() {
        switch KeychainStore.read(service: Self.forgejoTokenService) {
        case .value(let token):
            forgejoToken = token
            forgejoTokenIssue = nil
        case .missing:
            forgejoToken = nil
            forgejoTokenIssue = forgejoHost.isEmpty ? nil : "No token stored for \(forgejoHost). Add one in settings."
        case .refused(let status):
            forgejoToken = nil
            forgejoTokenIssue = forgejoHost.isEmpty
                ? nil
                : "The keychain refused the \(forgejoHost) token (\(status)). Re-enter it in settings."
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
        // Re-read on every refresh: a token added or rebound since launch shouldn't need a restart.
        loadForgejoToken()
        let owners = self.owners
        let config = forgejoConfig
        let tokenIssue = forgejoTokenIssue
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
            let errors = [tokenIssue].compactMap { $0 } + results.compactMap(\.errorMessage)
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

    var tabGlyph: TabGlyph { .symbol("arrow.triangle.branch") }

    var settingsSubtitle: String? {
        forgejoHost.isEmpty ? "GitHub CLI" : "GitHub CLI · \(forgejoHost)"
    }

    func statusLine() -> String? {
        guard lastRefresh != nil else { return nil }
        let merged = mergedPRs(in: todayPRs)
        guard let latest = merged.compactMap(\.mergedAt).max() else {
            let open = todayOpenCount
            return open > 0 ? "\(open) open today" : "Nothing merged today"
        }
        return "\(merged.count) merged, last \(Formatters.ago(latest))"
    }

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

enum PRPeriod: Hashable { case today, week, month }

struct PullRequestTabView: View {
    let ext: PullRequestExtension

    @State private var selectedPeriod: PRPeriod = .week

    var body: some View {
        VStack(spacing: 0) {
            if let error = ext.errorMessage {
                banner(error, symbol: "exclamationmark.triangle", color: Ember.accentDeep)
            }
            if ext.truncated {
                banner("Hit a host's result cap, so counts may be capped.", symbol: "exclamationmark.circle", color: Ember.accent)
            }
            hero
            costTrack
            listSection
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let merged = mergedCount
        if let avg = periodAverage {
            EmberHero(cost: avg) { heroCaption }
        } else {
            EmberHero(primary: "\(merged)", secondary: nil) { heroCaption }
        }
    }

    private var heroCaption: some View {
        Group {
            if periodAverage != nil {
                Text("per shipped PR \(periodLabel) · ")
                    + Text("\(mergedCount)").bold().foregroundColor(Ember.text(0.9))
                    + Text(" merged, ")
                    + Text("\(openCount)").bold().foregroundColor(Ember.text(0.9))
                    + Text(" open")
            } else {
                Text("merged \(periodLabel) · nothing to divide cost into yet")
            }
        }
    }

    /// Period average against the month average, so a hot week reads as hot.
    @ViewBuilder
    private var costTrack: some View {
        let current = periodAverage ?? 0
        let baseline = ext.avgCostPerPRMonth ?? 0
        let scale = max(current, baseline) * 1.25
        EmberTrack(
            fill: scale > 0 ? current / scale : 0,
            tick: scale > 0 && baseline > 0 ? baseline / scale : nil,
            leading: "\(periodLabel) \(Formatters.costRounded(current))",
            trailing: baseline > 0 ? "month average \(Formatters.costRounded(baseline))" : ""
        )
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - List

    private var listSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pull requests")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Ember.label)
                Spacer()
                EmberSegmented(
                    options: [("Today", PRPeriod.today), ("Week", .week), ("Month", .month)],
                    selection: $selectedPeriod
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            prList
        }
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private var prList: some View {
        let prs = filteredPRs
        if prs.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else if prs.count > 4 {
            ScrollView {
                rows(prs)
            }
            .frame(maxHeight: 176)
            .padding(.bottom, 4)
        } else {
            rows(prs)
                .padding(.bottom, 4)
        }
    }

    private func rows(_ prs: [PullRequest]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(prs.enumerated()), id: \.element.id) { idx, pr in
                PRRow(pr: pr)
                if idx < prs.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
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

    // MARK: - Period

    private var filteredPRs: [PullRequest] {
        switch selectedPeriod {
        case .today: return ext.todayPRs
        case .week:  return ext.weekPRs
        case .month: return ext.monthPRs
        }
    }

    private var periodAverage: Double? {
        switch selectedPeriod {
        case .today: return ext.avgCostPerPR
        case .week:  return ext.avgCostPerPRWeek
        case .month: return ext.avgCostPerPRMonth
        }
    }

    private var mergedCount: Int {
        switch selectedPeriod {
        case .today: return ext.todayMergedCount
        case .week:  return ext.weekMergedCount
        case .month: return ext.monthMergedCount
        }
    }

    private var openCount: Int {
        switch selectedPeriod {
        case .today: return ext.todayOpenCount
        case .week:  return ext.weekOpenCount
        case .month: return ext.monthOpenCount
        }
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .today: return "today"
        case .week:  return "this week"
        case .month: return "this month"
        }
    }

    private var emptyMessage: String {
        if ext.lastRefresh == nil && ext.isLoading { return "Loading…" }
        return "No PRs \(periodLabel)"
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
                        .foregroundStyle(.white)
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

private struct PullRequestSettingsView: View {
    let ext: PullRequestExtension
    @State private var input: String = ""
    @State private var hostInput: String = ""
    @State private var tokenInput: String = ""
    @FocusState private var focused: Bool
    @FocusState private var hostFocused: Bool

    var body: some View {
        EmberConfigCard {
            EmberFieldRow(label: "Orgs") {
                TextField("all", text: $input)
                    .focused($focused)
                    .onAppear { input = ext.owners.joined(separator: ", ") }
                    .onSubmit(commitOwners)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commitOwners() }
                    }
            }
            EmberFieldRow(label: "Forgejo") {
                TextField("git.example.com", text: $hostInput)
                    .focused($hostFocused)
                    .onAppear { hostInput = ext.forgejoHost }
                    .onSubmit(commitHost)
                    .onChange(of: hostFocused) { _, isFocused in
                        if !isFocused { commitHost() }
                    }
            }
            if ext.hasForgejoToken, tokenInput.isEmpty {
                HStack(spacing: 8) {
                    Text("Token")
                        .font(.system(size: 11))
                        .foregroundStyle(Ember.caption)
                        .frame(width: 58, alignment: .leading)
                    EmberStoredBadge(text: "In Keychain")
                }
            } else {
                EmberFieldRow(label: "Token") {
                    SecureField("read:issue token", text: $tokenInput)
                        .onSubmit(commitToken)
                }
            }
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
