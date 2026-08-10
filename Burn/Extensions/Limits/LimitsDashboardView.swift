import SwiftUI

/// Everything here is headroom: bars fill with what's left, like a battery.
struct LimitsDashboardView: View {
    let service: LimitsService

    @Environment(\.openBurnSettings) private var openSettings

    private var response: LimitsResponse { service.response }

    var body: some View {
        VStack(spacing: 0) {
            if case .loading = service.state {
                EmberLoadingBody()
            } else if case .failed(let message) = service.state {
                EmberErrorCard(
                    title: "Couldn't read plan limits",
                    message: message,
                    isRetrying: service.isLoading,
                    onSettings: openSettings,
                    onRetry: { service.refresh(force: true) }
                )
            } else if !response.isEmpty {
                hero
                warningRow
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
        parts.append(contentsOf: [staleness(snapshot), snapshot.failure?.message].compactMap { $0 })
        return parts.joined(separator: " · ")
    }

    private func spendCaption(snapshot: AccountSnapshot, spend: SpendSnapshot) -> String {
        var parts = spend.limitDollars
            .map { ["of \(Formatters.costRounded($0)) billed this month"] } ?? ["billed this month"]
        parts.append(contentsOf: [staleness(snapshot), snapshot.failure?.message].compactMap { $0 })
        return parts.joined(separator: " · ")
    }

    /// The big number is worthless if it looks live when it isn't.
    private func staleness(_ snapshot: AccountSnapshot) -> String? {
        guard let capturedAt = snapshot.capturedAt,
              Date().timeIntervalSince(capturedAt) > Self.stalenessThreshold else { return nil }
        return Formatters.ago(capturedAt)
    }

    private static let stalenessThreshold: TimeInterval = 120

    private var firstProblem: String? {
        response.accounts.compactMap(\.failure).first?.message
    }

    /// Only shows once something is genuinely close to stopping work.
    @ViewBuilder
    private var warningRow: some View {
        let strained = response.accountsNearCap
        if !strained.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ember.accentDeep)
                Text(warningText(strained))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ember.text(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Ember.accentDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func warningText(_ strained: [AccountSnapshot]) -> String {
        guard let first = strained.first, let window = first.tightestWindow else { return "" }
        let rest = strained.count - 1
        let subject = rest > 0 ? "\(first.account.label) +\(rest) more" : first.account.label
        return "\(subject) is \(Formatters.percent(window.effectiveUsedPercent)) through its \(window.kind.phrase)"
    }

    /// Same 20%-remaining line the emphasis bump already uses, so a bar's color and weight agree.
    private func nearCapColor(remaining: Double, fallback: Color) -> Color {
        remaining <= 20 ? Ember.danger : fallback
    }

    // MARK: - Per account

    private func section(for snapshot: AccountSnapshot) -> some View {
        EmberSection(title: snapshot.account.label, trailing: snapshot.planLabel) {
            VStack(spacing: 10) {
                // Scarcest window first: that's the one that decides when work stops.
                let windows = snapshot.windows.sorted { $0.remainingPercent < $1.remainingPercent }
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    EmberBarRow(
                        label: window.kind.label,
                        fraction: window.remainingPercent / 100,
                        value: Formatters.percent(window.remainingPercent),
                        emphasis: window.remainingPercent <= 20 ? 0.95 : 0.55,
                        color: nearCapColor(remaining: window.remainingPercent, fallback: snapshot.account.provider.accent),
                        valueColor: nearCapColor(remaining: window.remainingPercent, fallback: Ember.primary),
                        row: index
                    )
                }
                if let spend = snapshot.spend, let fraction = spend.fraction {
                    let remaining = (1 - fraction) * 100
                    EmberBarRow(
                        label: "Credits",
                        fraction: 1 - fraction,
                        value: Formatters.percent(remaining),
                        emphasis: 0.55,
                        color: nearCapColor(remaining: remaining, fallback: snapshot.account.provider.accent),
                        valueColor: nearCapColor(remaining: remaining, fallback: Ember.primary),
                        row: windows.count
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
        if let age = staleness(snapshot) {
            parts.append(age)
        }
        if let failure = snapshot.failure {
            parts.append(failure.message)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
