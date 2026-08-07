import Foundation

/// "Typical day/week/month" baseline math, shared by every provider's usage service so a week
/// compares against the same definition of typical wherever it's asked.
enum TypicalPeriod {
    struct Sample {
        let date: String
        let cost: Double
        let tokens: Int
    }

    /// Mean of the last 30 days with spend, today excluded so it stays a baseline.
    static func day(_ samples: [Sample], today: Date = Date()) -> (cost: Double, tokens: Int) {
        let todayKey = key(today)
        let past = samples.filter { $0.date != todayKey && $0.cost > 0 }.suffix(30)
        return meanOfSamples(past)
    }

    /// Mean of the last 8 complete rolling-7-day totals before the one still in progress — the
    /// same window boundaries `UsageData`'s own week-offset math uses.
    static func week(_ samples: [Sample], today: Date = Date()) -> (cost: Double, tokens: Int) {
        let grouped = Dictionary(grouping: samples.filter { $0.cost > 0 }) { weekIndex($0.date, relativeTo: today) }
        let complete = grouped.filter { $0.key != 0 }.sorted { $0.key < $1.key }.prefix(8)
        return meanOfBuckets(complete.map(\.value))
    }

    /// Mean of the last 6 complete calendar-month totals before the current, in-progress one.
    static func month(_ samples: [Sample], today: Date = Date()) -> (cost: Double, tokens: Int) {
        let currentMonth = String(key(today).prefix(7))
        let grouped = Dictionary(
            grouping: samples.filter { $0.cost > 0 && !$0.date.hasPrefix(currentMonth) },
            by: { String($0.date.prefix(7)) }
        )
        let complete = grouped.sorted { $0.key > $1.key }.prefix(6)
        return meanOfBuckets(complete.map(\.value))
    }

    // MARK: - Shared math

    private static func meanOfSamples(_ samples: ArraySlice<Sample>) -> (cost: Double, tokens: Int) {
        guard !samples.isEmpty else { return (0, 0) }
        let cost = samples.reduce(0) { $0 + $1.cost }
        let tokens = samples.reduce(0) { $0 + $1.tokens }
        return (cost / Double(samples.count), tokens / samples.count)
    }

    /// Averages the per-bucket sums, not the raw samples — a "typical week" is the mean of whole
    /// weekly totals, not the mean daily cost repeated seven times.
    private static func meanOfBuckets(_ buckets: [[Sample]]) -> (cost: Double, tokens: Int) {
        guard !buckets.isEmpty else { return (0, 0) }
        let sums = buckets.map { bucket in
            (cost: bucket.reduce(0) { $0 + $1.cost }, tokens: bucket.reduce(0) { $0 + $1.tokens })
        }
        let cost = sums.reduce(0) { $0 + $1.cost } / Double(sums.count)
        let tokens = sums.reduce(0) { $0 + $1.tokens } / sums.count
        return (cost, tokens)
    }

    /// 0 = the 7-day window ending today, 1 = the 7 days before that, and so on.
    private static func weekIndex(_ dateKey: String, relativeTo today: Date) -> Int {
        guard let date = parse(dateKey) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
        return days >= 0 ? days / 7 : 0
    }

    private static func parse(_ dateKey: String) -> Date? { formatter.date(from: dateKey) }
    private static func key(_ date: Date) -> String { formatter.string(from: date) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}
