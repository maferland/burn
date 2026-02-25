import Foundation

struct CCUsageResponse: Codable {
    let daily: [DailyUsage]
    let totals: Totals
}

struct DailyUsage: Codable, Identifiable {
    var id: String { date }

    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let modelsUsed: [String]
    let modelBreakdowns: [ModelBreakdown]

}

struct ModelBreakdown: Codable {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
}

struct Totals: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
}

struct UsageData {
    let todayCost: Double
    let last7Days: [DailyUsage]
    let currentMonthTotal: Double
    let lastRefreshDate: Date

    static let empty = UsageData(
        todayCost: 0,
        last7Days: [],
        currentMonthTotal: 0,
        lastRefreshDate: .distantPast
    )

    static func from(response: CCUsageResponse) -> UsageData {
        let today = dateString(from: Date())
        let todayCost = response.daily.first { $0.date == today }?.totalCost ?? 0

        let calendar = Calendar.current
        let now = Date()
        let existingByDate = Dictionary(
            uniqueKeysWithValues: response.daily.map { ($0.date, $0) }
        )
        let last7Days: [DailyUsage] = (0...6).map { offset in
            let day = calendar.date(byAdding: .day, value: -6 + offset, to: now)!
            let dayStr = dateString(from: day)
            return existingByDate[dayStr] ?? DailyUsage(
                date: dayStr, inputTokens: 0, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 0,
                totalCost: 0, modelsUsed: [], modelBreakdowns: []
            )
        }

        let monthPrefix = String(today.prefix(7))
        let currentMonthTotal = response.daily
            .filter { $0.date.hasPrefix(monthPrefix) }
            .reduce(0) { $0 + $1.totalCost }

        return UsageData(
            todayCost: todayCost,
            last7Days: last7Days,
            currentMonthTotal: currentMonthTotal,
            lastRefreshDate: now
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
