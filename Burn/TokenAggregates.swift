import Foundation
import ClaudeUsageKit

struct TokenAggregates: Sendable {
    let todayInput: Int
    let todayOutput: Int
    let weekInput: Int
    let weekOutput: Int
    let monthInput: Int
    let monthOutput: Int

    static let empty = TokenAggregates(
        todayInput: 0, todayOutput: 0,
        weekInput: 0, weekOutput: 0,
        monthInput: 0, monthOutput: 0
    )

    static func compute(response: CCUsageResponse?, weekEnd: Date) -> TokenAggregates {
        guard let response else { return .empty }

        let calendar = Calendar.current
        let todayStr = UsageData.dateString(from: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
        let weekStartStr = UsageData.dateString(from: weekStart)
        let weekEndStr = UsageData.dateString(from: weekEnd)
        let monthPrefix = String(UsageData.dateString(from: weekEnd).prefix(7))

        let todayDay = response.daily.first { $0.date == todayStr }
        var weekIn = 0, weekOut = 0, monthIn = 0, monthOut = 0
        for day in response.daily {
            if day.date >= weekStartStr && day.date <= weekEndStr {
                weekIn += day.inputTokens
                weekOut += day.outputTokens
            }
            if day.date.hasPrefix(monthPrefix) {
                monthIn += day.inputTokens
                monthOut += day.outputTokens
            }
        }

        return TokenAggregates(
            todayInput: todayDay?.inputTokens ?? 0,
            todayOutput: todayDay?.outputTokens ?? 0,
            weekInput: weekIn, weekOutput: weekOut,
            monthInput: monthIn, monthOutput: monthOut
        )
    }
}
