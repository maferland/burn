import Foundation
import ClaudeUsageKit

/// Which provider the Usage tab is currently talking about.
enum UsageScope: Hashable, Identifiable {
    case all
    case provider(Provider)

    var id: String {
        switch self {
        case .all: return "all"
        case .provider(let provider): return provider.rawValue
        }
    }

    var label: String {
        switch self {
        case .all: return "All providers"
        case .provider(let provider): return provider.displayName
        }
    }

    func includes(_ provider: Provider) -> Bool {
        switch self {
        case .all: return true
        case .provider(let scoped): return scoped == provider
        }
    }
}

/// Feeds the Usage tab one `UsageData` whatever the scope, so the dashboard never learns about
/// providers: Codex days are converted into the same shape Claude days already arrive in.
@MainActor
struct ProviderUsage {
    let claude: UsageService
    let codex: CodexUsageService
    /// nil keeps the pre-Providers behaviour, which the tests and the screenshot mocks rely on.
    var counted: [Provider]?

    /// A provider has to be both counted and actually reporting before it earns a row.
    var availableProviders: [Provider] {
        let allowed = counted ?? Provider.allCases
        return Provider.allCases.filter { provider in
            guard allowed.contains(provider) else { return false }
            switch provider {
            case .claude: return true
            case .codex:  return !codex.response.isEmpty
            }
        }
    }

    var availableScopes: [UsageScope] {
        let providers = availableProviders
        guard providers.count > 1 else { return providers.map(UsageScope.provider) }
        return [.all] + providers.map(UsageScope.provider)
    }

    func todayCost(for provider: Provider) -> Double {
        switch provider {
        case .claude: return claude.usageData.todayCost
        case .codex:  return codex.response.todayCost
        }
    }

    func typicalDayCost(_ scope: UsageScope) -> Double {
        var total: Double = 0
        if scope.includes(.claude) { total += claude.typicalDayCost }
        if scope.includes(.codex) { total += codex.typicalDayCost }
        return total
    }

    func typicalDayTokens(_ scope: UsageScope) -> Int {
        var total = 0
        if scope.includes(.claude) { total += claude.typicalDayTokens }
        if scope.includes(.codex) { total += codex.typicalDayTokens }
        return total
    }

    /// Per-provider totals for one day, used by the by-provider rows in "All providers".
    func breakdown(on date: String) -> [(provider: Provider, cost: Double, tokens: Int)] {
        availableProviders.compactMap { provider in
            let cost: Double
            let tokens: Int
            switch provider {
            case .claude:
                let day = claude.day(date)
                cost = day?.totalCost ?? 0
                tokens = (day?.inputTokens ?? 0) + (day?.outputTokens ?? 0)
            case .codex:
                let day = codex.response.day(date)
                cost = day?.estimatedCost ?? 0
                tokens = (day?.tokens.uncachedInputTokens ?? 0) + (day?.tokens.outputTokens ?? 0)
            }
            return cost > 0 ? (provider, cost, tokens) : nil
        }
    }

    /// Most recent day with spend before `date`, so an empty day can still show a real number.
    func lastActiveDay(scope: UsageScope, before date: String) -> DailyUsage? {
        var candidates: [DailyUsage] = []
        if scope.includes(.claude) {
            candidates += (claude.lastResponse?.daily ?? []).filter { $0.totalCost > 0 }
        }
        if scope.includes(.codex) {
            candidates += codex.response.daily.filter { $0.estimatedCost > 0 }.map(Self.asDailyUsage)
        }
        return candidates.filter { $0.date < date }.max { $0.date < $1.date }
    }

    func usageData(scope: UsageScope, weekOffset: Int = 0) -> UsageData {
        // The current week uses the service's own aggregate, which survives a cold start from cache.
        let claudeData = scope.includes(.claude)
            ? (weekOffset == 0 ? claude.usageData : claude.usageData(weekOffset: weekOffset))
            : nil
        guard scope.includes(.codex), !codex.response.isEmpty else {
            return claudeData ?? .empty
        }

        let base = claudeData ?? claude.usageData(weekOffset: weekOffset)
        let codexDays = Self.window(codex.response.daily.map(Self.asDailyUsage), like: base)
        let codexMonth = codex.response.monthCost()
        guard let claudeData else {
            return Self.rebuild(base, days: codexDays, monthTotal: codexMonth)
        }
        return Self.rebuild(
            claudeData,
            days: Self.merge(claudeData.last7Days, codexDays),
            monthTotal: claudeData.monthTotal + codexMonth
        )
    }

    // MARK: - Shaping

    /// Codex prices at API rates rather than billing, which the tab already says in its caption.
    static func asDailyUsage(_ day: CodexDailyUsage) -> DailyUsage {
        DailyUsage(
            date: day.date,
            inputTokens: day.tokens.uncachedInputTokens,
            outputTokens: day.tokens.outputTokens,
            cacheCreationTokens: 0,
            cacheReadTokens: day.tokens.cachedInputTokens,
            totalTokens: day.tokens.totalTokens,
            totalCost: day.estimatedCost,
            modelsUsed: day.modelsUsed,
            modelBreakdowns: day.modelBreakdowns.map {
                ModelBreakdown(
                    modelName: $0.modelName,
                    inputTokens: $0.tokens.uncachedInputTokens,
                    outputTokens: $0.tokens.outputTokens,
                    cacheCreationTokens: 0,
                    cacheReadTokens: $0.tokens.cachedInputTokens,
                    cost: $0.estimatedCost
                )
            }
        )
    }

    static func window(_ days: [DailyUsage], like data: UsageData) -> [DailyUsage] {
        let keys = Set(data.last7Days.map(\.date))
        return days.filter { keys.contains($0.date) }
    }

    static func merge(_ lhs: [DailyUsage], _ rhs: [DailyUsage]) -> [DailyUsage] {
        let extra = Dictionary(rhs.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        return lhs.map { day in
            guard let other = extra[day.date] else { return day }
            return DailyUsage(
                date: day.date,
                inputTokens: day.inputTokens + other.inputTokens,
                outputTokens: day.outputTokens + other.outputTokens,
                cacheCreationTokens: day.cacheCreationTokens + other.cacheCreationTokens,
                cacheReadTokens: day.cacheReadTokens + other.cacheReadTokens,
                totalTokens: day.totalTokens + other.totalTokens,
                totalCost: day.totalCost + other.totalCost,
                modelsUsed: day.modelsUsed + other.modelsUsed,
                modelBreakdowns: day.modelBreakdowns + other.modelBreakdowns
            )
        }
    }

    static func rebuild(_ data: UsageData, days: [DailyUsage], monthTotal: Double) -> UsageData {
        let today = UsageData.dateString(from: Date())
        return UsageData(
            todayCost: days.first { $0.date == today }?.totalCost ?? 0,
            last7Days: days,
            monthTotal: monthTotal,
            isCurrentWeek: data.isCurrentWeek,
            weekStart: data.weekStart,
            weekEnd: data.weekEnd,
            lastRefreshDate: data.lastRefreshDate,
            earliestDate: data.earliestDate
        )
    }
}
