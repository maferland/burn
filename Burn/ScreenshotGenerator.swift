import AppKit
import SwiftUI

enum ScreenshotGenerator {
    @MainActor static func generate(outputPath: String, scale: CGFloat = 3.0) {
        let settings = SettingsStore()
        let service = UsageService(settings: settings)

        service.usageData = UsageData(
            todayCost: 202.46,
            last7Days: mockDays(),
            monthTotal: 3813.63,
            isCurrentWeek: true,
            weekStart: Calendar.current.date(byAdding: .day, value: -6, to: Date())!,
            weekEnd: Date(),
            lastRefreshDate: Date()
        )

        let view = MenuBarView(service: service, settings: settings)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(4)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            fputs("Failed to render screenshot\n", stderr)
            exit(1)
        }

        do {
            let url = URL(filePath: outputPath)
            try png.write(to: url)
            print("Screenshot saved to \(outputPath) (\(Int(scale))x)")
        } catch {
            fputs("Failed to write: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func mockDays() -> [DailyUsage] {
        let calendar = Calendar.current
        let today = Date()
        let costs: [Double] = [85.20, 120.50, 95.30, 180.75, 45.60, 150.90, 202.46]

        return (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: -(6 - i), to: today)!
            return DailyUsage(
                date: UsageData.dateString(from: date),
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                totalTokens: 0,
                totalCost: costs[i],
                modelsUsed: [],
                modelBreakdowns: []
            )
        }
    }
}
