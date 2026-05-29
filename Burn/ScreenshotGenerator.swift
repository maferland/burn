import AppKit
import SwiftUI
import ClaudeUsageKit

enum ScreenshotGenerator {
    @MainActor static func generate(outputPath: String, scale: CGFloat = 3.0) {
        let settings = SettingsStore()
        if let mode = ProcessInfo.processInfo.environment["BURN_DISPLAY_MODE"] {
            switch mode.lowercased() {
            case "tokens": settings.displayMode = .tokens
            case "both":   settings.displayMode = .both
            case "cost":   settings.displayMode = .cost
            default: break
            }
        }
        let service = UsageService(settings: settings)

        let days = mockDays()
        service.usageData = UsageData(
            todayCost: 18.73,
            last7Days: days,
            monthTotal: 142.58,
            isCurrentWeek: true,
            weekStart: Calendar.current.date(byAdding: .day, value: -6, to: Date())!,
            weekEnd: Date(),
            lastRefreshDate: Date(),
            earliestDate: UsageData.dateString(from: Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        )
        let weekIn = days.reduce(0) { $0 + $1.inputTokens }
        let weekOut = days.reduce(0) { $0 + $1.outputTokens }
        service.lastResponse = CCUsageResponse(
            daily: days,
            totals: Totals(
                inputTokens: weekIn, outputTokens: weekOut,
                cacheCreationTokens: 0, cacheReadTokens: 0,
                totalTokens: weekIn + weekOut, totalCost: 142.58
            )
        )

        let registry = ExtensionRegistry()
        registry.register(UsageExtension(service: service, settings: settings))
        let prExt = GitHubPRExtension(usageService: service)
        prExt.prs = mockPRs()
        prExt.lastRefresh = Date()
        registry.register(prExt)
        if let activeId = ProcessInfo.processInfo.environment["BURN_ACTIVE_TAB"] {
            registry.activeTabId = activeId
        }
        let view = MenuBarView(service: service, settings: settings, registry: registry)
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

    private static func mockPRs() -> [GitHubPR] {
        let now = Date()
        let cal = Calendar.current
        return [
            GitHubPR(
                url: "https://github.com/maferland/burn/pull/3",
                title: "GitHub PR extension with stat cards",
                createdAt: cal.date(byAdding: .minute, value: -12, to: now)!,
                repository: .init(nameWithOwner: "maferland/burn")
            ),
            GitHubPR(
                url: "https://github.com/maferland/burn/pull/2",
                title: "Extension architecture: BurnExtension protocol + registry",
                createdAt: cal.date(byAdding: .hour, value: -3, to: now)!,
                repository: .init(nameWithOwner: "maferland/burn")
            ),
            GitHubPR(
                url: "https://github.com/carta/claude-marketplace/pull/4966",
                title: "verdict: persona-scoped MCP token cache",
                createdAt: cal.date(byAdding: .hour, value: -5, to: now)!,
                repository: .init(nameWithOwner: "carta/claude-marketplace")
            ),
        ]
    }

    private static func mockDays() -> [DailyUsage] {
        let calendar = Calendar.current
        let today = Date()
        let costs: [Double] = [12.40, 22.30, 18.90, 31.50, 8.20, 30.55, 18.73]

        return (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: -(6 - i), to: today)!
            // Plausible Opus split: most cost from output, large cache_read volume, tiny input.
            let input  = Int(costs[i] * 10_000)      // ~10K per $1
            let output = Int(costs[i] * 25_000)      // ~25K per $1
            let cw     = Int(costs[i] * 50_000)      // ~50K per $1
            let cr     = Int(costs[i] * 12_000_000)  // ~12M per $1 (cheap, dominant volume)
            let breakdown = ModelBreakdown(
                modelName: "claude-opus-4-7",
                inputTokens: input, outputTokens: output,
                cacheCreationTokens: cw, cacheReadTokens: cr,
                cost: costs[i]
            )
            return DailyUsage(
                date: UsageData.dateString(from: date),
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cw,
                cacheReadTokens: cr,
                totalTokens: input + output + cw + cr,
                totalCost: costs[i],
                modelsUsed: ["claude-opus-4-7"],
                modelBreakdowns: [breakdown]
            )
        }
    }
}
