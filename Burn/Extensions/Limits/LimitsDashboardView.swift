import SwiftUI

/// Everything here is headroom: bars fill with what's left, like a battery.
struct LimitsDashboardView: View {
    let service: LimitsService

    @Environment(\.openBurnSettings) private var openSettings

    private var response: LimitsResponse { service.response }

    var body: some View {
        VStack(spacing: 0) {
            if !response.isEmpty {
                hero
                ForEach(response.accounts) { snapshot in
                    section(for: snapshot)
                }
            } else if service.accounts.isEmpty {
                EmberEmptyState(
                    title: "No AI accounts found",
                    detail: "Sign in with Claude Code or Codex, then refresh. Extra logins get added in settings.",
                    action: (label: "Open settings", perform: openSettings)
                )
            } else {
                EmberEmptyState(
                    title: "No quota read yet",
                    detail: "Refresh to ask each account how much of its plan is left."
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let (snapshot, window) = response.tightest {
            EmberHero(primary: Formatters.percent(window.remainingPercent)) {
                Text(heroCaption(snapshot: snapshot, window: window))
            }
            .padding(.bottom, 16)
        } else if let snapshot = response.accounts.first(where: { $0.spend != nil }), let spend = snapshot.spend {
            EmberHero(cost: spend.usedDollars) {
                Text(spendCaption(snapshot: snapshot, spend: spend))
            }
            .padding(.bottom, 16)
        } else {
            EmberNote(text: firstProblem ?? "No plan windows reported for these accounts.")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
    }

    private func heroCaption(snapshot: AccountSnapshot, window: LimitWindow) -> String {
        var parts = ["of \(snapshot.account.label)'s \(window.kind.phrase) left"]
        if let resetsAt = window.resetsAt, !window.hasReset {
            parts.append(Formatters.resetLabel(resetsAt))
        }
        return parts.joined(separator: " · ")
    }

    private func spendCaption(snapshot: AccountSnapshot, spend: SpendSnapshot) -> String {
        guard let limit = spend.limitDollars else { return "used by \(snapshot.account.label)" }
        return "of \(Formatters.costRounded(limit)) used · \(snapshot.planLabel ?? "usage-based") seat"
    }

    private var firstProblem: String? {
        response.accounts.compactMap(\.failure).first?.message
    }

    // MARK: - Per account

    private func section(for snapshot: AccountSnapshot) -> some View {
        EmberSection(title: snapshot.account.label, trailing: snapshot.planLabel) {
            VStack(spacing: 10) {
                // Scarcest window first: that's the one that decides when work stops.
                ForEach(snapshot.windows.sorted { $0.remainingPercent < $1.remainingPercent }) { window in
                    EmberBarRow(
                        label: window.kind.label,
                        fraction: window.remainingPercent / 100,
                        value: Formatters.percent(window.remainingPercent),
                        emphasis: window.remainingPercent <= 20 ? 0.95 : 0.55
                    )
                }
                if let spend = snapshot.spend, let fraction = spend.fraction {
                    EmberBarRow(
                        label: "Credits",
                        fraction: 1 - fraction,
                        value: Formatters.percent((1 - fraction) * 100),
                        emphasis: 0.55
                    )
                }
                if let note = note(for: snapshot) {
                    EmberNote(text: note)
                }
            }
        }
    }

    /// One line: the money, the reset that matters, how stale it is, and whatever went wrong.
    private func note(for snapshot: AccountSnapshot) -> String? {
        var parts: [String] = []
        if let spend = snapshot.spend {
            parts.append(Formatters.spendLine(spend))
        }
        if let window = snapshot.tightestWindow, let resetsAt = window.resetsAt, !window.hasReset {
            parts.append("\(window.kind.label.lowercased()) \(Formatters.resetLabel(resetsAt))")
        }
        if snapshot.source == .rolloutLogs {
            parts.append("from rollout logs")
        }
        if let capturedAt = snapshot.capturedAt, Date().timeIntervalSince(capturedAt) > 120 {
            parts.append(Formatters.ago(capturedAt))
        }
        if let failure = snapshot.failure {
            parts.append(failure.message)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
