import AppKit
import SwiftUI

@Observable
@MainActor
final class GitHubPRExtension: BurnExtension {
    let id = "github-pr"
    let displayName = "GitHub"
    static let ownersKey = "github-pr.owners"

    let usageService: UsageService
    var prs: [GitHubPR] = []
    var errorMessage: String?
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fetched = try await GitHubPRService.fetchPRsOpened(on: Date(), owners: owners)
                self.prs = fetched.sorted(by: { $0.createdAt > $1.createdAt })
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

    var todayCount: Int { prs.count }

    var avgCostPerPR: Double? {
        guard todayCount > 0 else { return nil }
        return usageService.usageData.todayCost / Double(todayCount)
    }

    // Unicode glyphs render in MenuBarExtra labels; SF Symbols interpolated into Text do not.
    func menuBarSegment() -> Text? {
        if todayCount > 0, let avg = avgCostPerPR {
            return Text("⎇ \(todayCount) · \(String(format: "$%.0f", avg))")
        }
        return Text("⎇ \(todayCount)")
    }

    func popoverTab() -> AnyView {
        AnyView(GitHubPRTabView(ext: self))
    }
}

struct GitHubPRTabView: View {
    let ext: GitHubPRExtension

    @Environment(\.openBurnSettings) private var openSettings
    @Environment(\.burnTabBarVisible) private var tabBarVisible

    var body: some View {
        VStack(spacing: 0) {
            if !tabBarVisible {
                header
                Divider()
            }
            if let error = ext.errorMessage {
                errorBanner(error)
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

    private var cards: some View {
        HStack(spacing: 8) {
            StatCard(label: "Today's PRs", value: "\(ext.todayCount)")
            StatCard(label: "Avg $ / PR", value: ext.avgCostPerPR.map { Formatters.cost($0) } ?? "—")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var prList: some View {
        if ext.prs.isEmpty {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ext.prs.enumerated()), id: \.element.id) { idx, pr in
                        PRRow(pr: pr)
                        if idx < ext.prs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(.vertical, 2)
        }
    }

    private var emptyMessage: String {
        if ext.lastRefresh == nil && ext.isLoading {
            return "Loading…"
        }
        return "No PRs opened today"
    }
}

private struct PRRow: View {
    let pr: GitHubPR

    var body: some View {
        Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(pr.repository.nameWithOwner)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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
    @Bindable var ext: GitHubPRExtension

    private var ownersBinding: Binding<String> {
        Binding(
            get: { ext.owners.joined(separator: ", ") },
            set: { newValue in
                ext.owners = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        HStack {
            Text("Orgs").font(.caption)
            Spacer()
            TextField("all (e.g., carta)", text: ownersBinding)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(width: 130)
                .onSubmit { ext.refresh() }
        }
    }
}
