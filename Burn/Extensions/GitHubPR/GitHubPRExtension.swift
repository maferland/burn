import AppKit
import SwiftUI

@Observable
@MainActor
final class GitHubPRExtension: BurnExtension {
    let id = "github-pr"
    let displayName = "GitHub"

    let usageService: UsageService
    var prs: [GitHubPR] = []
    var errorMessage: String?
    var isLoading = false
    var lastRefresh: Date?

    init(usageService: UsageService) {
        self.usageService = usageService
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fetched = try await GitHubPRService.fetchPRsOpened(on: Date())
                self.prs = fetched.sorted(by: { $0.createdAt > $1.createdAt })
                self.lastRefresh = Date()
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    var todayCount: Int { prs.count }

    var avgCostPerPR: Double? {
        guard todayCount > 0 else { return nil }
        return usageService.usageData.todayCost / Double(todayCount)
    }

    // Unicode glyphs render in MenuBarExtra labels; SF Symbols interpolated into Text do not.
    func menuBarSegment() -> Text? {
        if todayCount > 0, let avg = avgCostPerPR {
            return Text("⎇ \(todayCount) @ \(String(format: "$%.2f", avg))")
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
}
