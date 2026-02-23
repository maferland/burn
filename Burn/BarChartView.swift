import SwiftUI

struct BarChartView: View {
    let days: [DailyUsage]

    private var maxCost: Double {
        days.map(\.totalCost).max() ?? 1
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor)
                            .frame(height: barHeight(cost: day.totalCost, maxHeight: geo.size.height - 16))

                        Text(Self.dayLabel(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barHeight(cost: Double, maxHeight: CGFloat) -> CGFloat {
        guard maxCost > 0 else { return 2 }
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
