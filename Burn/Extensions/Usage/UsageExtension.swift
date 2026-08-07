import SwiftUI
import ClaudeUsageKit

/// Which grain the single nav row pages by. Selecting one reshapes the whole card, not just the
/// chevrons' step size — Week shows the week's total against a typical week, not one day's.
enum UsagePeriod: CaseIterable, Hashable {
    case day, week, month

    var label: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

@Observable
@MainActor
final class UsageExtension: BurnExtension {
    let id = "usage"
    let displayName = "Usage"

    static let scopeKey = "usage.scope"

    let service: UsageService
    let codexService: CodexUsageService
    let settings: SettingsStore

    /// Which provider the tab is scoped to, remembered across launches.
    var scope: UsageScope {
        didSet { UserDefaults.standard.set(scope.id, forKey: Self.scopeKey) }
    }

    let providers: ProviderStore?

    /// Browsing state. Shared with the header so its status line describes whatever's actually
    /// on screen instead of always saying "today" while you're looking at last week.
    var period: UsagePeriod = UsageExtension.initialPeriod()
    var weekOffset = 0
    var monthOffset = 0
    var selectedDayId: String? = UsageExtension.initialSelectedDay()

    /// Screenshot knob, same family as BURN_ACTIVE_TAB and BURN_STATE.
    private static func initialPeriod() -> UsagePeriod {
        switch ProcessInfo.processInfo.environment["BURN_PERIOD"] {
        case "week":  return .week
        case "month": return .month
        default:      return .day
        }
    }

    /// Screenshot knob, same family as BURN_ACTIVE_TAB and BURN_STATE.
    private static func initialSelectedDay() -> String? {
        guard let raw = ProcessInfo.processInfo.environment["BURN_DAY_OFFSET"],
              let offset = Int(raw),
              let date = Calendar.current.date(byAdding: .day, value: -abs(offset), to: Date())
        else { return nil }
        return UsageData.dateString(from: date)
    }

    var providerUsage: ProviderUsage {
        ProviderUsage(claude: service, codex: codexService, counted: providers?.countedInTotal)
    }

    var displayData: UsageData {
        providerUsage.usageData(scope: scope, weekOffset: weekOffset)
    }

    var monthData: MonthUsage {
        providerUsage.monthUsage(scope: scope, monthOffset: monthOffset)
    }

    var selectedDay: DailyUsage? {
        let days = displayData.last7Days
        if let id = selectedDayId, let day = days.first(where: { $0.id == id }) {
            return day
        }
        return days.last
    }

    var isViewingToday: Bool {
        selectedDay?.date == UsageData.dateString(from: Date())
    }

    init(
        service: UsageService,
        codexService: CodexUsageService,
        settings: SettingsStore,
        providers: ProviderStore? = nil
    ) {
        self.service = service
        self.codexService = codexService
        self.settings = settings
        self.providers = providers
        let stored = UserDefaults.standard.string(forKey: Self.scopeKey)
        self.scope = Provider(rawValue: stored ?? "").map(UsageScope.provider)
            ?? (stored == "all" ? .all : .provider(.claude))
    }

    var tabGlyph: TabGlyph { .asset }

    func refresh() {
        service.refresh()
        codexService.refresh()
    }

    /// Live only while looking at the still-open instant of whatever period is selected — a
    /// closed day, week or month reads as settled even when it moved a lot of money.
    var state: ExtensionState {
        if let message = service.errorMessage { return .failed(message) }
        if service.lastResponse == nil { return service.isLoading ? .loading : .dormant }
        guard isViewingCurrentInstant else { return .dormant }
        return currentInstantCost > 0 ? .live : .dormant
    }

    private var isViewingCurrentInstant: Bool {
        switch period {
        case .day:   return isViewingToday
        case .week:  return weekOffset == 0
        case .month: return monthOffset == 0
        }
    }

    private var currentInstantCost: Double {
        switch period {
        case .day:   return displayData.todayCost
        case .week:  return displayData.weekTotal
        case .month: return monthData.total
        }
    }

    func statusLine() -> String? {
        switch period {
        case .day:   return dayStatusLine()
        case .week:  return periodStatusLine(value: displayData.weekTotal, typical: providerUsage.typicalWeekCost(scope), noun: "this week")
        case .month: return periodStatusLine(value: monthData.total, typical: providerUsage.typicalMonthCost(scope), noun: "this month")
        }
    }

    private func dayStatusLine() -> String? {
        guard displayData.lastRefreshDate != .distantPast else { return nil }
        let typical = providerUsage.typicalDayCost(scope)
        if isViewingToday {
            return periodStatusLine(value: displayData.todayCost, typical: typical, noun: "today")
        }
        guard let day = selectedDay else { return nil }
        return periodStatusLine(value: day.totalCost, typical: typical, noun: "that day")
    }

    /// Same shape the hero caption uses for a closed period: a comparison if there's a baseline
    /// to compare against, otherwise the plain total, otherwise say nothing was burned.
    private func periodStatusLine(value: Double, typical: Double, noun: String) -> String? {
        guard displayData.lastRefreshDate != .distantPast else { return nil }
        if let comparison = Formatters.comparison(value: value, baseline: typical) {
            return comparison
        }
        guard value > 0 else { return "Nothing burned \(noun == "today" ? "yet" : noun)" }
        return "\(Formatters.costRounded(value)) \(noun)"
    }

    func menuBarSegment() -> Text? {
        guard service.usageData.lastRefreshDate != .distantPast else { return nil }
        return Text(String(format: "$%.0f", service.usageData.todayCost))
    }

    func popoverTab() -> AnyView {
        AnyView(UsageDashboardView(ext: self, service: service, settings: settings))
    }
}
