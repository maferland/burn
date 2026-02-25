import SwiftUI

struct BarChartView: View {
    let days: [DailyUsage]
    @State private var hoveredDay: String?

    private var maxCost: Double {
        days.map(\.totalCost).max() ?? 1
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    let isHovered = hoveredDay == day.id

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.8))
                            .frame(height: barHeight(cost: day.totalCost, maxHeight: geo.size.height - 16))
                            .overlay(alignment: .top) {
                                if isHovered {
                                    Text(String(format: "$%.2f", day.totalCost))
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.75))
                                        .cornerRadius(4)
                                        .fixedSize()
                                        .offset(y: -20)
                                }
                            }

                        Text(Self.dayLabel(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(isHovered ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .onHover { hovering in
                        hoveredDay = hovering ? day.id : nil
                    }
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
