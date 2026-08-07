import AppKit
import SwiftUI
import ClaudeUsageKit

enum DetailScope: Equatable {
    case day(String)
    case week(Int)
    case month(Int)
}

struct UsageDashboardView: View {
    let ext: UsageExtension
    let service: UsageService
    let settings: SettingsStore

    @Environment(\.openBurnSettings) private var openSettings

    @State private var openScope: DetailScope? = UsageDashboardView.initialOpenScope()

    private static func initialOpenScope() -> DetailScope? {
        switch ProcessInfo.processInfo.environment["BURN_DETAIL"] {
        case "day":   return .day("")
        case "week":  return .week(0)
        case "month": return .month(0)
        default:      return nil
        }
    }

    private var tokens: TokenAggregates {
        TokenAggregates.compute(response: service.lastResponse, weekEnd: ext.displayData.weekEnd)
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

    // MARK: - Nav

    /// One merged row: chip when multi-provider, then chevrons + label, then the period picker.
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsChip {
                HStack { providerChip; Spacer(minLength: 0) }
            }
            HStack(spacing: 8) {
                EmberPeriodNav(
                    label: navLabel,
                    canGoBack: navCanGoBack,
                    canGoForward: navCanGoForward,
                    onBack: { shiftPeriod(-1) },
                    onForward: { shiftPeriod(1) }
                )
                Spacer(minLength: 8)
                EmberSegmented(
                    options: UsagePeriod.allCases.map { (label: $0.label, value: $0) },
                    selection: periodBinding
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .background(alignment: .topLeading) { periodShortcuts }
    }

    private var showsChip: Bool { ext.providerUsage.availableScopes.count > 1 }

    private var periodBinding: Binding<UsagePeriod> {
        Binding(get: { ext.period }, set: { ext.period = $0 })
    }

    private var navLabel: String {
        switch ext.period {
        case .day:   return ext.selectedDay.map { Formatters.dayLabel($0.date) } ?? "Today"
        case .week:  return ext.displayData.isCurrentWeek ? "Last 7 days" : Formatters.weekRange(ext.displayData)
        case .month: return ext.monthData.label
        }
    }

    private var navCanGoBack: Bool {
        switch ext.period {
        case .day:   return canShiftDay(-1)
        case .week:  return ext.displayData.canGoBack
        case .month: return ext.monthData.canGoBack
        }
    }

    private var navCanGoForward: Bool {
        switch ext.period {
        case .day:   return canShiftDay(1)
        case .week:  return ext.weekOffset < 0
        case .month: return ext.monthOffset < 0
        }
    }

    private var currentDetailScope: DetailScope {
        switch ext.period {
        case .day:   return .day(ext.selectedDay?.id ?? "")
        case .week:  return .week(ext.weekOffset)
        case .month: return .month(ext.monthOffset)
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        let totals = periodTotals
        Group {
            if totals.cost <= 0 {
                EmberEmptyHero(title: emptyHeroTitle, footnote: lastKnownLine)
            } else {
                Group {
                    if settings.displayMode == .tokens {
                        EmberHero(primary: Formatters.tokensCompact(totals.tokens)) { heroCaption }
                    } else {
                        EmberHero(cost: totals.cost) { heroCaption }
                    }
                }
                .onTapGesture { toggleDetail(currentDetailScope) }
                .pointingHandCursor()
                // The day's first session landing is the one moment worth a beat.
                .transition(.emberRise)
            }
        }
        .animation(.easeOut(duration: 0.25), value: totals.cost <= 0)
    }

    private var emptyHeroTitle: String {
        switch ext.period {
        case .day:   return ext.isViewingToday || ext.selectedDay == nil ? "Nothing burned yet" : "Nothing burned that day"
        case .week:  return "Nothing burned this week"
        case .month: return "Nothing burned this month"
        }
    }

    /// The empty hero still carries a real number, just an older one — never a bare zero.
    private var lastKnownLine: String? {
        guard let day = ext.providerUsage.lastActiveDay(scope: ext.scope, before: periodAnchorDate) else {
            return nil
        }
        let value = Formatters.formatPrimary(
            cost: day.totalCost,
            tokens: day.inputTokens + day.outputTokens,
            mode: settings.displayMode
        )
        return "Last burn \(value) on \(Formatters.dayLabel(day.date))"
    }

    private var periodAnchorDate: String {
        switch ext.period {
        case .day:   return ext.selectedDay?.date ?? UsageData.dateString(from: Date())
        case .week:  return ext.displayData.last7Days.last?.date ?? UsageData.dateString(from: Date())
        case .month: return ext.monthData.days.last?.date ?? UsageData.dateString(from: Date())
        }
    }

    @ViewBuilder
    private var heroCaption: some View {
        switch ext.period {
        case .day:   dayCaption
        case .week:  weekCaption
        case .month: monthCaption
        }
    }

    @ViewBuilder
    private var dayCaption: some View {
        let label = ext.selectedDay.map { Formatters.dayLabel($0.date).lowercased() } ?? "today"
        if let comparison = closedDayComparison {
            Text(comparison)
        } else if settings.displayMode != .cost, let day = ext.selectedDay {
            Text(Formatters.tokenLine(
                input: day.inputTokens,
                output: day.outputTokens,
                cache: day.cacheCreationTokens + day.cacheReadTokens
            ))
        } else if ext.isViewingToday, let pace = monthPace {
            Text("\(label) · month on pace for ")
                + Text(Formatters.costRounded(pace)).bold().foregroundColor(Ember.text(0.9))
        } else {
            Text(label)
        }
    }

    /// A closed day has nothing left to project, so it reads against the baseline instead.
    private var closedDayComparison: String? {
        guard !ext.isViewingToday, ext.selectedDay != nil else { return nil }
        return Formatters.comparison(value: periodMetricValue, baseline: periodTypicalValue)
    }

    /// Month-to-date spend extrapolated across the whole month, for the day view's own footnote.
    private var monthPace: Double? {
        let calendar = Calendar.current
        let now = Date()
        guard ext.displayData.monthTotal > 0,
              let range = calendar.range(of: .day, in: .month, for: now) else { return nil }
        let elapsed = calendar.component(.day, from: now)
        guard elapsed > 0 else { return nil }
        return ext.displayData.monthTotal / Double(elapsed) * Double(range.count)
    }

    @ViewBuilder
    private var weekCaption: some View {
        if let comparison = Formatters.comparison(value: periodMetricValue, baseline: periodTypicalValue, noun: "a typical week") {
            Text(comparison)
        } else {
            Text("\(periodValueLabel(periodMetricValue)) this week")
        }
    }

    @ViewBuilder
    private var monthCaption: some View {
        if ext.monthData.isCurrent, let pace = monthPeriodPace {
            Text("on pace for ") + Text(periodValueLabel(pace)).bold().foregroundColor(Ember.text(0.9))
        } else if let comparison = Formatters.comparison(value: periodMetricValue, baseline: periodTypicalValue, noun: "a typical month") {
            Text(comparison)
        } else {
            Text("\(periodValueLabel(periodMetricValue)) this month")
        }
    }

    /// A rolling week always ends today; only the calendar month still has days ahead to project.
    private var monthPeriodPace: Double? {
        guard ext.monthData.elapsedFraction > 0, periodMetricValue > 0 else { return nil }
        return periodMetricValue / ext.monthData.elapsedFraction
    }

    // MARK: - Pace

    /// A typical day always sits at `typicalMark`, so the fill means the same thing every day.
    private static let typicalMark = 0.72

    private var paceTrack: some View {
        let value = periodMetricValue
        let typical = periodTypicalValue

        return EmberTrack(
            fill: typical > 0 ? value / typical * Self.typicalMark : (value > 0 ? Self.typicalMark : 0),
            tick: typical > 0 ? Self.typicalMark : nil,
            leading: paceLeading,
            trailing: typical > 0 ? "typical \(typicalNoun) \(periodValueLabel(typical))" : ""
        )
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var paceLeading: String {
        switch ext.period {
        case .day:
            return ext.displayData.isCurrentWeek && ext.selectedDayId == nil
                ? "now \(Formatters.clockTime(Date()))"
                : Formatters.dayLabel(ext.selectedDay?.date ?? "")
        case .week:
            return ext.displayData.isCurrentWeek ? "Last 7 days" : Formatters.weekRange(ext.displayData)
        case .month:
            return ext.monthData.label
        }
    }

    private var typicalNoun: String {
        switch ext.period {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        }
    }

    /// What the hero and pace track both measure — dollars pace dollars, tokens pace tokens.
    private var periodMetricValue: Double {
        settings.displayMode == .tokens ? Double(periodTotals.tokens) : periodTotals.cost
    }

    private var periodTypicalValue: Double {
        switch ext.period {
        case .day:
            return settings.displayMode == .tokens
                ? Double(ext.providerUsage.typicalDayTokens(ext.scope))
                : ext.providerUsage.typicalDayCost(ext.scope)
        case .week:
            return settings.displayMode == .tokens
                ? Double(ext.providerUsage.typicalWeekTokens(ext.scope))
                : ext.providerUsage.typicalWeekCost(ext.scope)
        case .month:
            return settings.displayMode == .tokens
                ? Double(ext.providerUsage.typicalMonthTokens(ext.scope))
                : ext.providerUsage.typicalMonthCost(ext.scope)
        }
    }

    private func periodValueLabel(_ value: Double) -> String {
        settings.displayMode == .tokens ? Formatters.tokensCompact(Int(value)) : Formatters.costRounded(value)
    }

    /// Cost and tokens for whatever grain is selected: day, rolling week, or calendar month.
    private var periodTotals: (cost: Double, tokens: Int) {
        switch ext.period {
        case .day:
            guard let day = ext.selectedDay else { return (0, 0) }
            return (day.totalCost, day.inputTokens + day.outputTokens)
        case .week:
            return (ext.displayData.weekTotal, tokens.weekInput + tokens.weekOutput)
        case .month:
            return (ext.monthData.total, ext.monthData.tokenTotal)
        }
    }

    /// The days behind whatever's on screen, for ranking models or providers across it.
    private var periodDays: [DailyUsage] {
        switch ext.period {
        case .day:   return ext.selectedDay.map { [$0] } ?? []
        case .week:  return ext.displayData.last7Days
        case .month: return ext.monthData.days
        }
    }

    // MARK: - Models

    @ViewBuilder
    private var modelSection: some View {
        let days = periodDays
        let ranked = ProviderUsage.mergedModelBreakdowns(days).sorted { metric($0) > metric($1) }
        if !ranked.isEmpty {
            let leader = ranked.first.map(metric) ?? 0
            EmberSection(title: "By model", trailing: cacheNote(for: days)) {
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
                            emphasis: index == 0 ? 1.0 : (index == 1 ? 0.55 : 0.4),
                            row: index
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
    private func cacheNote(for days: [DailyUsage]) -> String? {
        let breakdown = BreakdownData.compute(title: "", subtitle: "", days: days)
        let cacheCost = breakdown.cacheReadCost + breakdown.cacheWriteCost
        let priced = breakdown.inputCost + breakdown.outputCost + cacheCost
        guard priced > 0, cacheCost > 0 else { return nil }
        let cacheTokens = days.reduce(0) { $0 + $1.cacheCreationTokens + $1.cacheReadTokens }
        let amount = settings.displayMode == .tokens
            ? Formatters.tokensCompact(cacheTokens)
            : Formatters.cost(cacheCost)
        return "\(Int((cacheCost / priced * 100).rounded()))% cache · \(amount)"
    }

    // MARK: - Context strip

    /// Read-only now that paging lives in the nav row above; still tappable to open the detail.
    private var contextStrip: some View {
        let data = ext.displayData
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
            selectedId: ext.period == .day ? ext.selectedDay?.id : nil,
            leading: .init(
                label: data.isCurrentWeek ? "Last 7 days" : Formatters.weekRange(data),
                value: weekValue
            ),
            trailing: .init(label: Formatters.monthName(data), value: monthValue),
            onSelect: { id in
                ext.selectedDayId = id
                ext.period = .day
            },
            onOpen: { toggleDetail($0 == .week ? .week(0) : .month(0)) }
        )
    }

    /// Invisible buttons keep the shortcuts alive now that the visible nav is two inline chevrons.
    private var periodShortcuts: some View {
        ZStack {
            Button("") { shiftPeriod(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { shiftPeriod(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Button("") { resetPeriod() }.keyboardShortcut("0", modifiers: .command)
            Button("") { shiftDay(-1) }.keyboardShortcut(.leftArrow, modifiers: .option)
            Button("") { shiftDay(1) }.keyboardShortcut(.rightArrow, modifiers: .option)
        }
        .frame(width: 1, height: 1)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func shiftPeriod(_ delta: Int) {
        switch ext.period {
        case .day:   shiftDay(delta)
        case .week:  shiftWeek(delta)
        case .month: shiftMonth(delta)
        }
    }

    /// ⌘0 for whichever period is selected: today, this rolling week, or this calendar month.
    private func resetPeriod() {
        switch ext.period {
        case .day, .week:
            shiftWeek(nil)
        case .month:
            ext.monthOffset = 0
            withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
        }
    }

    private func shiftWeek(_ delta: Int?) {
        if let delta {
            let next = ext.weekOffset + delta
            guard next <= 0, delta < 0 ? ext.displayData.canGoBack : true else { return }
            ext.weekOffset = next
        } else {
            ext.weekOffset = 0
        }
        ext.selectedDayId = nil
        withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
    }

    private func shiftMonth(_ delta: Int) {
        let next = ext.monthOffset + delta
        guard next <= 0, delta >= 0 || ext.monthData.canGoBack else { return }
        ext.monthOffset = next
        withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
    }

    private func canShiftDay(_ delta: Int) -> Bool {
        let days = ext.displayData.last7Days
        guard let current = ext.selectedDay,
              let index = days.firstIndex(where: { $0.id == current.id }) else { return false }
        let next = index + delta
        if next >= 0, next < days.count { return true }
        return next < 0 ? ext.displayData.canGoBack : ext.weekOffset < 0
    }

    /// Stepping off either end of the visible week pages it and lands on the adjacent day.
    private func shiftDay(_ delta: Int) {
        let days = ext.displayData.last7Days
        guard let current = ext.selectedDay,
              let index = days.firstIndex(where: { $0.id == current.id }) else { return }
        let next = index + delta
        if next >= 0, next < days.count {
            ext.selectedDayId = days[next].id
        } else if next < 0, ext.displayData.canGoBack {
            ext.weekOffset -= 1
            ext.selectedDayId = ext.displayData.last7Days.last?.id
        } else if next >= days.count, ext.weekOffset < 0 {
            ext.weekOffset += 1
            ext.selectedDayId = ext.displayData.last7Days.first?.id
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
            let day = ext.displayData.last7Days.first(where: { $0.id == id })
                ?? ext.selectedDay
                ?? ext.displayData.last7Days.last
            guard let day else { return BreakdownData.empty(title: "Day", subtitle: "No data") }
            return BreakdownData.compute(
                title: Formatters.dayLabel(day.date),
                subtitle: Formatters.dayFullLabel(day.date),
                days: [day]
            )
        case .week(let offset):
            let data = ext.providerUsage.usageData(scope: ext.scope, weekOffset: offset)
            let title = data.isCurrentWeek ? "Last 7 days" : "Week"
            return BreakdownData.compute(
                title: title,
                subtitle: Formatters.weekRange(data),
                days: data.last7Days
            )
        case .month(let offset):
            let month = ext.providerUsage.monthUsage(scope: ext.scope, monthOffset: offset)
            return BreakdownData.compute(
                title: Formatters.monthLabel(month.date),
                subtitle: Formatters.monthYearLabel(month.date),
                days: month.days
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
                    .foregroundStyle(Ember.primary)
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
        let rows = periodProviderBreakdown
        let leader = rows.map(providerMetric).max() ?? 0
        if !rows.isEmpty {
            let totals = periodTotals
            EmberSection(
                title: "By provider",
                trailing: Formatters.formatPrimary(cost: totals.cost, tokens: totals.tokens, mode: settings.displayMode)
            ) {
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.provider) { index, row in
                        EmberBarRow(
                            label: row.provider.displayName,
                            fraction: leader > 0 ? providerMetric(row) / leader : 0,
                            value: Formatters.formatPrimary(
                                cost: row.cost, tokens: row.tokens, mode: settings.displayMode
                            ),
                            emphasis: providerMetric(row) == leader ? 1.0 : 0.55,
                            color: row.provider.accent,
                            row: index
                        )
                    }
                }
            }
        }
    }

    /// Per-provider totals across whatever grain is on screen, summed one date at a time.
    private var periodProviderBreakdown: [(provider: Provider, cost: Double, tokens: Int)] {
        let rows = periodDays.flatMap { ext.providerUsage.breakdown(on: $0.date) }
        let grouped = Dictionary(grouping: rows, by: \.provider)
        return ext.providerUsage.availableProviders.compactMap { provider in
            guard let matches = grouped[provider] else { return nil }
            let cost = matches.reduce(0) { $0 + $1.cost }
            let tokens = matches.reduce(0) { $0 + $1.tokens }
            return cost > 0 ? (provider, cost, tokens) : nil
        }
    }
}
