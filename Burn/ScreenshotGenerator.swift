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
        let codexService = CodexUsageService()
        codexService.response = mockCodexUsage()
        registry.register(CodexExtension(service: codexService, settings: settings))
        let limitsService = LimitsService(
            store: LimitsAccountStore(detect: { [] }),
            cacheFile: FileManager.default.temporaryDirectory.appendingPathComponent("burn-shot-limits.json")
        )
        limitsService.response = mockLimits()
        registry.register(LimitsExtension(service: limitsService))
        let prExt = PullRequestExtension(usageService: service, hostStore: mockHostStore())
        prExt.prs = mockPRs()
        prExt.lastRefresh = Date()
        registry.register(prExt)
        if let activeId = ProcessInfo.processInfo.environment["BURN_ACTIVE_TAB"] {
            registry.activeTabId = activeId
        }
        let view = MenuBarView(service: service, settings: settings, registry: registry)
            .background(Ember.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(6)
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

    private static func mockPRs() -> [PullRequest] {
        let now = Date()
        let cal = Calendar.current
        return [
            PullRequest(
                url: "https://github.com/maferland/burn/pull/3",
                title: "GitHub PR extension with stat cards",
                createdAt: cal.date(byAdding: .minute, value: -12, to: now)!,
                repository: .init(nameWithOwner: "maferland/burn"),
                state: "OPEN",
                closedAt: nil
            ),
            PullRequest(
                url: "https://github.com/maferland/burn/pull/2",
                title: "Extension architecture: BurnExtension protocol + registry",
                createdAt: cal.date(byAdding: .hour, value: -3, to: now)!,
                repository: .init(nameWithOwner: "maferland/burn"),
                state: "MERGED",
                closedAt: cal.date(byAdding: .hour, value: -2, to: now)!
            ),
            PullRequest(
                url: "https://github.com/acme/platform/pull/4966",
                title: "Retry flaky artifact uploads",
                createdAt: cal.date(byAdding: .hour, value: -5, to: now)!,
                repository: .init(nameWithOwner: "acme/platform"),
                state: "OPEN",
                closedAt: nil
            ),
            PullRequest(
                url: "https://git.example.com/acme/ledger/pulls/50",
                title: "Round distribution amounts",
                createdAt: cal.date(byAdding: .hour, value: -6, to: now)!,
                repository: .init(nameWithOwner: "acme/ledger"),
                state: "MERGED",
                closedAt: cal.date(byAdding: .hour, value: -4, to: now)!,
                provider: .forgejo,
                hostLabel: "git.example.com"
            ),
        ]
    }

    /// Isolated defaults and a canned token read, so screenshots never depend on the real config.
    @MainActor private static func mockHostStore() -> GitHostStore {
        let defaults = UserDefaults(suiteName: "burn.screenshot.hosts")!
        defaults.removePersistentDomain(forName: "burn.screenshot.hosts")
        let store = GitHostStore(
            defaults: defaults,
            legacyTokenService: "burn.screenshot.legacy",
            readToken: { _ in .value("mock-token") }
        )
        for host in store.hosts {
            store.remove(host.id)
        }
        store.upsert(GitHostConfig(host: "github.com", org: "carta"))
        store.upsert(GitHostConfig(host: "git.carta.rocks", org: "carta"))
        return store
    }

    private static func mockLimits() -> LimitsResponse {
        let now = Date()
        let personal = LimitsAccount(
            provider: .claude, label: "personal", homePath: "~/.claude-personal", isAutoDetected: false
        )
        let work = LimitsAccount(provider: .claude, label: "work", homePath: nil, isAutoDetected: true)
        let codex = LimitsAccount(provider: .codex, label: "codex", homePath: nil, isAutoDetected: true)

        return LimitsResponse(accounts: [
            AccountSnapshot(
                account: personal,
                planLabel: "Max 20×",
                windows: [
                    LimitWindow(kind: .fiveHour, usedPercent: 38, resetsAt: now.addingTimeInterval(2 * 3_600)),
                    LimitWindow(kind: .week, usedPercent: 70, resetsAt: now.addingTimeInterval(3 * 86_400)),
                    LimitWindow(kind: .weekOpus, usedPercent: 12, resetsAt: now.addingTimeInterval(3 * 86_400)),
                ],
                spend: nil, capturedAt: now, source: .api, failure: nil
            ),
            AccountSnapshot(
                account: work,
                planLabel: "Enterprise",
                windows: [],
                spend: SpendSnapshot(usedDollars: 73.35, limitDollars: 10_000),
                capturedAt: now, source: .api, failure: nil
            ),
            AccountSnapshot(
                account: codex,
                planLabel: "Pro",
                windows: [
                    LimitWindow(kind: .fiveHour, usedPercent: 21, resetsAt: now.addingTimeInterval(4_200)),
                    LimitWindow(kind: .week, usedPercent: 44, resetsAt: now.addingTimeInterval(4 * 86_400)),
                ],
                spend: nil, capturedAt: now.addingTimeInterval(-900), source: .rolloutLogs, failure: nil
            ),
        ])
    }

    private static func mockCodexUsage() -> CodexUsageResponse {
        let calendar = Calendar.current
        let today = Date()
        let costs: [Double] = [1.90, 4.10, 0.80, 6.25, 3.40, 5.10, 2.85]

        let daily: [CodexDailyUsage] = (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: -(6 - i), to: today)!
            let tokens = CodexTokens(
                inputTokens: Int(costs[i] * 900_000),
                cachedInputTokens: Int(costs[i] * 610_000),
                outputTokens: Int(costs[i] * 24_000),
                reasoningOutputTokens: Int(costs[i] * 9_000)
            )
            return CodexDailyUsage(
                date: CodexSessionReader.dateString(from: date),
                tokens: tokens,
                estimatedCost: costs[i],
                modelBreakdowns: [
                    CodexModelBreakdown(
                        modelName: "gpt-5.1-codex-max",
                        tokens: tokens,
                        estimatedCost: costs[i] * 0.78
                    ),
                    CodexModelBreakdown(
                        modelName: "gpt-5.1-codex",
                        tokens: tokens,
                        estimatedCost: costs[i] * 0.22
                    ),
                ]
            )
        }

        let limits = CodexRateLimits(
            capturedAt: calendar.date(byAdding: .hour, value: -2, to: today)!,
            planType: "pro",
            primary: CodexRateLimitWindow(
                usedPercent: 61,
                windowMinutes: 300,
                resetsAt: calendar.date(byAdding: .hour, value: 3, to: today)!
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 47,
                windowMinutes: 10_080,
                resetsAt: calendar.date(byAdding: .day, value: 4, to: today)!
            )
        )

        return CodexUsageResponse(
            daily: daily,
            tokens: daily.reduce(CodexTokens()) { $0 + $1.tokens },
            estimatedCost: costs.reduce(0, +),
            rateLimits: limits,
            skippedCompressedFiles: 3
        )
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
