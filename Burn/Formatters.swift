import Foundation
import ClaudeUsageKit

enum Formatters {
    static func cost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// Hero split: "$194" + ".13", so the cents can be dimmed.
    static func costParts(_ value: Double) -> (whole: String, cents: String) {
        let rounded = (value * 100).rounded() / 100
        let whole = Int(rounded)
        let cents = Int(((rounded - Double(whole)) * 100).rounded())
        return ("$" + grouped.string(from: NSNumber(value: whole))!, String(format: ".%02d", cents))
    }

    /// Whole dollars with a thousands separator, for period totals.
    static func costRounded(_ value: Double) -> String {
        "$" + (grouped.string(from: NSNumber(value: Int(value.rounded()))) ?? "0")
    }

    static func clockTime(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// "2h ago", "5m ago", "just now".
    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    /// "resets 6:40 PM" for today, "resets Mon" beyond it.
    static func resetLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "resets \(clock.string(from: date))" }
        return "resets \(weekdayShort.string(from: date))"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Says "billed" so it can't be mistaken for the Usage tab, which prices local logs at API rates.
    static func spendLine(_ spend: SpendSnapshot) -> String {
        guard let limit = spend.limitDollars else {
            return "\(costRounded(spend.usedDollars)) billed this month"
        }
        return "\(costRounded(spend.usedDollars)) of \(costRounded(limit)) billed this month"
    }

    /// "18% under typical" / "42% over typical", nil when there's no baseline.
    static func comparison(value: Double, baseline: Double, noun: String = "a typical day") -> String? {
        guard baseline > 0, value > 0 else { return nil }
        let delta = (value - baseline) / baseline
        let percent = Int((abs(delta) * 100).rounded())
        if percent < 3 { return "right on \(noun)" }
        return "\(percent)% \(delta > 0 ? "over" : "under") \(noun)"
    }

    static func tokensCompact(_ total: Int) -> String {
        let value = Double(total)
        if value >= 10_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 10_000     { return String(format: "%.2fM", value / 1_000_000) }
        if value >= 1          { return String(format: "%dK",   max(1, total / 1_000)) }
        return "0"
    }

    /// "claude-opus-4-7" reads as "Opus 4.7", "gpt-5.1-codex-max" as "GPT-5.1 Codex Max".
    static func modelLabel(_ raw: String) -> String {
        let parts = raw.split(separator: "-").map(String.init)
        if raw.hasPrefix("claude-"), parts.count >= 2 {
            let family = parts[1].capitalized
            let version = parts.dropFirst(2).filter { Int($0) != nil }.joined(separator: ".")
            return version.isEmpty ? family : "\(family) \(version)"
        }
        if raw.hasPrefix("gpt-"), parts.count >= 2 {
            let rest = parts.dropFirst(2).map(\.capitalized).joined(separator: " ")
            return rest.isEmpty ? "GPT-\(parts[1])" : "GPT-\(parts[1]) \(rest)"
        }
        return raw.capitalized
    }

    /// Inside the Codex tab the vendor prefix is redundant: "gpt-5.1-codex-max" reads as "5.1 Codex Max".
    static func codexModelLabel(_ raw: String) -> String {
        let full = modelLabel(raw)
        return full.hasPrefix("GPT-") ? String(full.dropFirst(4)) : full
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

    static func monthLabel(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    /// "Today" if the date is today, otherwise "EEE, MMM d".
    static func dayLabel(_ dateString: String) -> String {
        if dateString == UsageData.dateString(from: Date()) { return "Today" }
        if let parsed = dayParser.date(from: dateString) {
            return longDay.string(from: parsed)
        }
        return dateString
    }

    /// "August 6, 2026" — a detail subtitle needs a date more specific than the title above it.
    static func dayFullLabel(_ dateString: String) -> String {
        guard let parsed = dayParser.date(from: dateString) else { return dateString }
        return fullDay.string(from: parsed)
    }

    /// "August 2026" — the month detail's subtitle, next to a title that only names the month.
    static func monthYearLabel(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    static func relativeTime(_ date: Date) -> String {
        guard date != .distantPast else { return "Never refreshed" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Updated \(f.string(from: date))"
    }

    // MARK: - DateFormatters

    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

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

    private static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
