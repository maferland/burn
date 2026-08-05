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
    @State private var selectedDayId: String? = UsageDashboardView.initialSelectedDay()
    @State private var openScope: DetailScope? = UsageDashboardView.initialOpenScope()

    /// Screenshots need a way to land on a closed day; the UI gets there by clicking a bar.
    private static func initialSelectedDay() -> String? {
        guard let raw = ProcessInfo.processInfo.environment["BURN_DAY_OFFSET"],
              let offset = Int(raw),
              let date = Calendar.current.date(byAdding: .day, value: -abs(offset), to: Date())
        else { return nil }
        return UsageData.dateString(from: date)
    }

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
                stateContent
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
    }

    /// A first read still in flight, or one that failed with nothing cached, owns the whole tab.
    @ViewBuilder
    private var stateContent: some View {
        switch ext.state {
        case .loading:
            EmberLoadingBody()
        case .failed(let message) where service.lastResponse == nil:
            EmberErrorCard(
                title: "Couldn't read usage",
                message: message,
                isRetrying: service.isLoading,
                onSettings: openSettings,
                onRetry: { ext.refresh() }
            )
        default:
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            errorBanner
            topBar
            hero
            paceTrack
            breakdownSection
            contextStrip
        }
        .frame(maxWidth: .infinity)
    }

    /// One row above the hero: scope on the left, day paging on the right once a closed day is open.
    @ViewBuilder
    private var topBar: some View {
        let showsChip = ext.providerUsage.availableScopes.count > 1
        let showsNav = selectedDay != nil && !isViewingToday
        if showsChip || showsNav {
            HStack(spacing: 8) {
                if showsChip { providerChip }
                Spacer(minLength: 0)
                if showsNav { dayNav }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private var isViewingToday: Bool {
        selectedDay?.date == UsageData.dateString(from: Date())
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let day = selectedDay
        let cost = day?.totalCost ?? 0
        let totalIO = (day?.inputTokens ?? 0) + (day?.outputTokens ?? 0)

        if cost <= 0 {
            EmberEmptyHero(
                title: isViewingToday || day == nil ? "Nothing burned yet" : "Nothing burned that day",
                footnote: lastKnownLine
            )
        } else {
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
    }

    /// The empty hero still carries a real number, just an older one — never a bare zero.
    private var lastKnownLine: String? {
        let onScreen = selectedDay?.date ?? UsageData.dateString(from: Date())
        guard let day = ext.providerUsage.lastActiveDay(scope: ext.scope, before: onScreen) else {
            return nil
        }
        let value = Formatters.formatPrimary(
            cost: day.totalCost,
            tokens: day.inputTokens + day.outputTokens,
            mode: settings.displayMode
        )
        return "Last burn \(value) on \(Formatters.dayLabel(day.date))"
    }

    @ViewBuilder
    private var heroCaption: some View {
        let label = selectedDay.map { Formatters.dayLabel($0.date).lowercased() } ?? "today"
        if let comparison = closedDayComparison {
            Text(comparison)
        } else if settings.displayMode != .cost, let day = selectedDay {
            Text(Formatters.tokenLine(
                input: day.inputTokens,
                output: day.outputTokens,
                cache: day.cacheCreationTokens + day.cacheReadTokens
            ))
        } else if isViewingToday, let pace = monthPace {
            Text("\(label) · month on pace for ")
                + Text(Formatters.costRounded(pace)).bold().foregroundColor(Ember.text(0.9))
        } else {
            Text(label)
        }
    }

    /// A closed day has nothing left to project, so it reads against the baseline instead.
    private var closedDayComparison: String? {
        guard !isViewingToday, selectedDay != nil else { return nil }
        return Formatters.comparison(value: dayMetric(selectedDay), baseline: typicalMetric)
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
        let value = dayMetric(selectedDay)
        let typical = typicalMetric
        let leading = displayData.isCurrentWeek && selectedDayId == nil
            ? "now \(Formatters.clockTime(Date()))"
            : Formatters.dayLabel(selectedDay?.date ?? "")

        EmberTrack(
            fill: typical > 0 ? value / typical * Self.typicalMark : (value > 0 ? Self.typicalMark : 0),
            tick: typical > 0 ? Self.typicalMark : nil,
            leading: leading,
            trailing: typical > 0 ? "typical day \(typicalLabel)" : ""
        )
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var typicalDay: Double { ext.providerUsage.typicalDayCost(ext.scope) }

    /// Everything on this row measures whatever the hero measures: dollars pace dollars, tokens pace tokens.
    private var typicalMetric: Double {
        settings.displayMode == .tokens
            ? Double(ext.providerUsage.typicalDayTokens(ext.scope))
            : typicalDay
    }

    private var typicalLabel: String {
        settings.displayMode == .tokens
            ? Formatters.tokensCompact(ext.providerUsage.typicalDayTokens(ext.scope))
            : Formatters.costRounded(typicalDay)
    }

    private func dayMetric(_ day: DailyUsage?) -> Double {
        guard let day else { return 0 }
        return settings.displayMode == .tokens
            ? Double(day.inputTokens + day.outputTokens)
            : day.totalCost
    }

    // MARK: - Models

    @ViewBuilder
    private var modelSection: some View {
        if let day = selectedDay, !day.modelBreakdowns.isEmpty {
            let ranked = day.modelBreakdowns.sorted { metric($0) > metric($1) }
            let leader = ranked.first.map(metric) ?? 0
            EmberSection(title: "By model", trailing: cacheNote(for: day)) {
                VStack(spacing: 10) {
                    ForEach(Array(ranked.prefix(4).enumerated()), id: \.element.modelName) { index, model in
                        EmberBarRow(
                            label: Formatters.modelLabel(model.modelName),
                            fraction: leader > 0 ? metric(model) / leader : 0,
                            value: Formatters.formatPrimary(
                                cost: model.cost,
                                tokens: model.inputTokens + model.outputTokens,
                                mode: settings.displayMode
                            ),
                            emphasis: index == 0 ? 1.0 : (index == 1 ? 0.55 : 0.4)
                        )
                    }
                }
            }
        }
    }

    /// Bars rank by whatever the tab is measuring, so widths never disagree with the numbers beside them.
    private func metric(_ model: ModelBreakdown) -> Double {
        settings.displayMode == .tokens
            ? Double(model.inputTokens + model.outputTokens)
            : model.cost
    }

    /// Share of the priced components, not of totalCost, so the two always agree.
    private func cacheNote(for day: DailyUsage) -> String? {
        let breakdown = BreakdownData.compute(title: "", subtitle: "", days: [day])
        let cacheCost = breakdown.cacheReadCost + breakdown.cacheWriteCost
        let priced = breakdown.inputCost + breakdown.outputCost + cacheCost
        guard priced > 0, cacheCost > 0 else { return nil }
        let amount = settings.displayMode == .tokens
            ? Formatters.tokensCompact(day.cacheCreationTokens + day.cacheReadTokens)
            : Formatters.cost(cacheCost)
        return "\(Int((cacheCost / priced * 100).rounded()))% cache · \(amount)"
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
            Button("") { shiftDay(-1) }.keyboardShortcut(.leftArrow, modifiers: .option)
            Button("") { shiftDay(1) }.keyboardShortcut(.rightArrow, modifiers: .option)
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
    private var dayNav: some View {
        if let day = selectedDay {
            EmberDayNav(
                label: Formatters.dayLabel(day.date),
                canGoBack: canShiftDay(-1),
                canGoForward: canShiftDay(1),
                onBack: { shiftDay(-1) },
                onForward: { shiftDay(1) },
                onToday: { shiftWeek(nil) }
            )
        }
    }

    private func canShiftDay(_ delta: Int) -> Bool {
        let days = displayData.last7Days
        guard let current = selectedDay,
              let index = days.firstIndex(where: { $0.id == current.id }) else { return false }
        let next = index + delta
        if next >= 0, next < days.count { return true }
        return next < 0 ? displayData.canGoBack : weekOffset < 0
    }

    /// Stepping off either end of the visible week pages it and lands on the adjacent day.
    private func shiftDay(_ delta: Int) {
        let days = displayData.last7Days
        guard let current = selectedDay,
              let index = days.firstIndex(where: { $0.id == current.id }) else { return }
        let next = index + delta
        if next >= 0, next < days.count {
            selectedDayId = days[next].id
        } else if next < 0, displayData.canGoBack {
            weekOffset -= 1
            selectedDayId = displayData.last7Days.last?.id
        } else if next >= days.count, weekOffset < 0 {
            weekOffset += 1
            selectedDayId = displayData.last7Days.first?.id
        } else {
            return
        }
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
    /// Scope picker. `topBar` only places it once there is a second provider to switch to.
    var providerChip: some View {
        Menu {
            ForEach(ext.providerUsage.availableScopes) { scope in
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

    func providerMetric(_ row: (provider: Provider, cost: Double, tokens: Int)) -> Double {
        settings.displayMode == .tokens ? Double(row.tokens) : row.cost
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
            let leader = rows.map(providerMetric).max() ?? 0
            if !rows.isEmpty {
                EmberSection(
                    title: "By provider",
                    trailing: Formatters.formatPrimary(
                        cost: day.totalCost,
                        tokens: day.inputTokens + day.outputTokens,
                        mode: settings.displayMode
                    )
                ) {
                    VStack(spacing: 10) {
                        ForEach(rows, id: \.provider) { row in
                            EmberBarRow(
                                label: row.provider.displayName,
                                fraction: leader > 0 ? providerMetric(row) / leader : 0,
                                value: Formatters.formatPrimary(
                                    cost: row.cost, tokens: row.tokens, mode: settings.displayMode
                                ),
                                emphasis: providerMetric(row) == leader ? 1.0 : 0.55,
                                color: row.provider.accent
                            )
                        }
                    }
                }
            }
        }
    }
}
