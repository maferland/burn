import Foundation
import ClaudeUsageKit

enum Formatters {
    static func cost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func tokensCompact(_ total: Int) -> String {
        let value = Double(total)
        if value >= 10_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 10_000     { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1          { return String(format: "%dK",   max(1, total / 1_000)) }
        return "0"
    }

    static func tokenSplit(input: Int, output: Int) -> String {
        "\(tokensCompact(input)) in · \(tokensCompact(output)) out"
    }

    static func tokenLine(input: Int, output: Int, cache: Int) -> String {
        var parts = ["\(tokensCompact(input)) in", "\(tokensCompact(output)) out"]
        if cache > 0 { parts.append("\(tokensCompact(cache)) cache") }
        return parts.joined(separator: " · ")
    }

    static func formatPrimary(cost: Double, tokens: Int, mode: DisplayMode) -> String {
        switch mode {
        case .cost, .both: return Formatters.cost(cost)
        case .tokens:      return Formatters.tokensCompact(tokens)
        }
    }

    static func weekRange(_ data: UsageData) -> String {
        "\(weekDay.string(from: data.weekStart)) – \(weekDay.string(from: data.weekEnd))"
    }

    static func monthName(_ data: UsageData) -> String {
        monthFormatter.string(from: data.weekEnd)
    }

    /// "Today" if the date is today, otherwise "EEE, MMM d".
    static func dayLabel(_ dateString: String) -> String {
        if dateString == UsageData.dateString(from: Date()) { return "Today" }
        if let parsed = dayParser.date(from: dateString) {
            return longDay.string(from: parsed)
        }
        return dateString
    }

    static func relativeTime(_ date: Date) -> String {
        guard date != .distantPast else { return "Never refreshed" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Updated \(f.string(from: date))"
    }

    // MARK: - DateFormatters

    private static let weekDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
