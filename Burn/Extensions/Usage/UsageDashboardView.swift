import AppKit
import SwiftUI
import ClaudeUsageKit

enum DetailScope: Equatable {
    case day(String)
    case week
    case month
}

struct UsageDashboardView: View {
    let ext: UsageExtension
    let service: UsageService
    let settings: SettingsStore

    @Environment(\.openBurnSettings) private var openSettings

    @State private var weekOffset = 0
    @State private var selectedDayId: String?
    @State private var openScope: DetailScope? = UsageDashboardView.initialOpenScope()

    private static func initialOpenScope() -> DetailScope? {
        switch ProcessInfo.processInfo.environment["BURN_DETAIL"] {
        case "day":   return .day("")
        case "week":  return .week
        case "month": return .month
        default:      return nil
        }
    }

    private var displayData: UsageData {
        ext.providerUsage.usageData(scope: ext.scope, weekOffset: weekOffset)
    }

    private var tokens: TokenAggregates {
        TokenAggregates.compute(response: service.lastResponse, weekEnd: displayData.weekEnd)
    }

    var selectedDay: DailyUsage? {
        let days = displayData.last7Days
        if let id = selectedDayId, let day = days.first(where: { $0.id == id }) {
            return day
        }
        return days.last
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let scope = openScope {
                BreakdownDetailView(
                    data: breakdownData(for: scope),
                    onBack: { toggleDetail(scope) },
                    onSettings: openSettings
                )
                .transition(.move(edge: .trailing))
            } else {
                mainContent
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            errorBanner
            providerChip
            hero
            paceTrack
            breakdownSection
            contextStrip
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let day = selectedDay
        let cost = day?.totalCost ?? 0
        let totalIO = (day?.inputTokens ?? 0) + (day?.outputTokens ?? 0)

        Group {
            if settings.displayMode == .tokens {
                EmberHero(primary: Formatters.tokensCompact(totalIO)) { heroCaption }
            } else {
                EmberHero(cost: cost) { heroCaption }
            }
        }
        .onTapGesture { if let day { toggleDetail(.day(day.id)) } }
        .pointingHandCursor()
    }

    @ViewBuilder
    private var heroCaption: some View {
        let label = selectedDay.map { Formatters.dayLabel($0.date).lowercased() } ?? "today"
        if displayData.isCurrentWeek, let pace = monthPace {
            Text("\(label) · month on pace for ")
                + Text(Formatters.costRounded(pace)).bold().foregroundColor(Ember.text(0.9))
        } else if settings.displayMode != .cost, let day = selectedDay {
            Text(Formatters.tokenLine(
                input: day.inputTokens,
                output: day.outputTokens,
                cache: day.cacheCreationTokens + day.cacheReadTokens
            ))
        } else {
            Text(label)
        }
    }

    /// Month-to-date spend extrapolated across the whole month.
    private var monthPace: Double? {
        let calendar = Calendar.current
        let now = Date()
        guard displayData.monthTotal > 0,
              let range = calendar.range(of: .day, in: .month, for: now) else { return nil }
        let elapsed = calendar.component(.day, from: now)
        guard elapsed > 0 else { return nil }
        return displayData.monthTotal / Double(elapsed) * Double(range.count)
    }

    // MARK: - Pace

    /// A typical day always sits at `typicalMark`, so the fill means the same thing every day.
    private static let typicalMark = 0.72

    @ViewBuilder
    private var paceTrack: some View {
        let cost = selectedDay?.totalCost ?? 0
        let typical = typicalDay
        let leading = displayData.isCurrentWeek && selectedDayId == nil
            ? "now \(Formatters.clockTime(Date()))"
            : Formatters.dayLabel(selectedDay?.date ?? "")

        EmberTrack(
            fill: typical > 0 ? cost / typical * Self.typicalMark : (cost > 0 ? Self.typicalMark : 0),
            tick: typical > 0 ? Self.typicalMark : nil,
            leading: leading,
            trailing: typical > 0 ? "typical day \(Formatters.costRounded(typical))" : ""
        )
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var typicalDay: Double { service.typicalDayCost }

    // MARK: - Models

    @ViewBuilder
    private var modelSection: some View {
        if let day = selectedDay, !day.modelBreakdowns.isEmpty {
            let ranked = day.modelBreakdowns.sorted { $0.cost > $1.cost }
            let leader = ranked.first?.cost ?? 0
            EmberSection(title: "By model", trailing: cacheNote(for: day)) {
                VStack(spacing: 10) {
                    ForEach(Array(ranked.prefix(4).enumerated()), id: \.element.modelName) { index, model in
                        EmberBarRow(
                            label: Formatters.modelLabel(model.modelName),
                            fraction: leader > 0 ? model.cost / leader : 0,
                            value: Formatters.cost(model.cost),
                            emphasis: index == 0 ? 1.0 : (index == 1 ? 0.55 : 0.4)
                        )
                    }
                }
            }
        }
    }

    /// Share of the priced components, not of totalCost, so the two always agree.
    private func cacheNote(for day: DailyUsage) -> String? {
        let breakdown = BreakdownData.compute(title: "", subtitle: "", days: [day])
        let cacheCost = breakdown.cacheReadCost + breakdown.cacheWriteCost
        let priced = breakdown.inputCost + breakdown.outputCost + cacheCost
        guard priced > 0, cacheCost > 0 else { return nil }
        return "\(Int((cacheCost / priced * 100).rounded()))% cache · \(Formatters.cost(cacheCost))"
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        let data = displayData
        let maxCost = data.last7Days.map(\.totalCost).max() ?? 0
        let weekValue = settings.displayMode == .tokens
            ? Formatters.tokensCompact(tokens.weekInput + tokens.weekOutput)
            : Formatters.costRounded(data.weekTotal)
        let monthValue = settings.displayMode == .tokens
            ? Formatters.tokensCompact(tokens.monthInput + tokens.monthOutput)
            : Formatters.costRounded(data.monthTotal)

        return EmberContextStrip(
            bars: data.last7Days.map {
                .init(id: $0.id, fraction: maxCost > 0 ? $0.totalCost / maxCost : 0)
            },
            selectedId: selectedDay?.id,
            leading: .init(
                label: data.isCurrentWeek ? "Last 7 days" : Formatters.weekRange(data),
                value: weekValue
            ),
            trailing: .init(label: Formatters.monthName(data), value: monthValue),
            onSelect: { selectedDayId = $0 },
            onOpen: { toggleDetail($0 == .week ? .week : .month) },
            nav: .init(
                canGoBack: data.canGoBack,
                canGoForward: weekOffset < 0,
                onBack: { shiftWeek(-1) },
                onForward: { shiftWeek(1) }
            )
        )
        .background(alignment: .topLeading) { weekShortcuts }
    }

    /// Keyboard paging kept alive now that the visible nav is two inline chevrons.
    private var weekShortcuts: some View {
        ZStack {
            Button("") { shiftWeek(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { shiftWeek(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Button("") { shiftWeek(nil) }.keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 1, height: 1)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func shiftWeek(_ delta: Int?) {
        if let delta {
            let next = weekOffset + delta
            guard next <= 0, delta < 0 ? displayData.canGoBack : true else { return }
            weekOffset = next
        } else {
            weekOffset = 0
        }
        selectedDayId = nil
        withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = service.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(error).lineLimit(2)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Ember.accentDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: - Detail wiring

    private func toggleDetail(_ scope: DetailScope) {
        withAnimation(.easeInOut(duration: 0.25)) {
            openScope = (openScope == scope) ? nil : scope
        }
    }

    private func breakdownData(for scope: DetailScope) -> BreakdownData {
        switch scope {
        case .day(let id):
            let day = displayData.last7Days.first(where: { $0.id == id })
                ?? selectedDay
                ?? displayData.last7Days.last
            guard let day else { return BreakdownData.empty(title: "Day", subtitle: "No data") }
            return BreakdownData.compute(
                title: Formatters.dayLabel(day.date),
                subtitle: Formatters.dayLabel(day.date),
                days: [day]
            )
        case .week:
            let title = displayData.isCurrentWeek ? "Last 7 days" : "Week"
            return BreakdownData.compute(
                title: title,
                subtitle: Formatters.weekRange(displayData),
                days: displayData.last7Days
            )
        case .month:
            let monthPrefix = String(UsageData.dateString(from: displayData.weekEnd).prefix(7))
            let days = (service.lastResponse?.daily ?? []).filter { $0.date.hasPrefix(monthPrefix) }
            return BreakdownData.compute(
                title: Formatters.monthName(displayData),
                subtitle: Formatters.monthName(displayData),
                days: days
            )
        }
    }
}

extension UsageDashboardView {
    /// Scope picker. Only appears once there is a second provider to switch to.
    @ViewBuilder
    var providerChip: some View {
        let scopes = ext.providerUsage.availableScopes
        if scopes.count > 1 {
            HStack(spacing: 6) {
                Menu {
                    ForEach(scopes) { scope in
                        Button {
                            ext.scope = scope
                        } label: {
                            Text(menuLabel(for: scope))
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accent(for: ext.scope))
                            .frame(width: 6, height: 6)
                        Text(ext.scope.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Ember.label)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Ember.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    func menuLabel(for scope: UsageScope) -> String {
        switch scope {
        case .all:
            let total = ext.providerUsage.availableProviders
                .reduce(0) { $0 + ext.providerUsage.todayCost(for: $1) }
            return "\(scope.label)  \(Formatters.costRounded(total))"
        case .provider(let provider):
            return "\(provider.displayName)  \(Formatters.costRounded(ext.providerUsage.todayCost(for: provider)))"
        }
    }

    func accent(for scope: UsageScope) -> Color {
        switch scope {
        case .all: return Ember.accent
        case .provider(let provider): return provider.accent
        }
    }
}

extension UsageDashboardView {
    /// Scoped to one provider the question is "which model", across all of them it is "which provider".
    @ViewBuilder
    var breakdownSection: some View {
        if ext.scope == .all {
            providerSection
        } else {
            modelSection
        }
    }

    @ViewBuilder
    var providerSection: some View {
        if let day = selectedDay {
            let rows = ext.providerUsage.breakdown(on: day.date)
            let leader = rows.map(\.cost).max() ?? 0
            if !rows.isEmpty {
                EmberSection(title: "By provider", trailing: Formatters.cost(day.totalCost)) {
                    VStack(spacing: 10) {
                        ForEach(rows, id: \.provider) { row in
                            EmberBarRow(
                                label: row.provider.displayName,
                                fraction: leader > 0 ? row.cost / leader : 0,
                                value: Formatters.cost(row.cost),
                                emphasis: row.cost == leader ? 1.0 : 0.55,
                                color: row.provider.accent
                            )
                        }
                    }
                }
            }
        }
    }
}
