import SwiftUI
import ClaudeUsageKit

struct BarChartView: View {
    let days: [DailyUsage]
    @Binding var selectedDayId: String?

    private var maxCost: Double {
        days.map(\.totalCost).max() ?? 1
    }

    private var effectiveSelectedId: String? {
        selectedDayId ?? days.last?.id
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    let isSelected = effectiveSelectedId == day.id

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.3))
                            .frame(height: barHeight(cost: day.totalCost, maxHeight: geo.size.height - 16))

                        Text(Self.dayLabel(day.date))
                            .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDayId = day.id
                    }
                }
            }
        }
    }

    private func barHeight(cost: Double, maxHeight: CGFloat) -> CGFloat {
        guard maxCost > 0, cost > 0 else { return 0 }
        return max(2, CGFloat(cost / maxCost) * maxHeight)
    }

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static func dayLabel(_ dateStr: String) -> String {
        guard let date = parseFormatter.date(from: dateStr) else { return "?" }
        return displayFormatter.string(from: date)
    }
}
