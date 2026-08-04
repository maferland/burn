import XCTest
import ClaudeUsageKit
@testable import Burn

@MainActor
final class ProviderUsageTests: XCTestCase {
    private func claudeDay(_ date: String, cost: Double) -> DailyUsage {
        DailyUsage(
            date: date, inputTokens: 100, outputTokens: 50,
            cacheCreationTokens: 10, cacheReadTokens: 900,
            totalTokens: 1_060, totalCost: cost,
            modelsUsed: ["claude-opus-5"],
            modelBreakdowns: [
                ModelBreakdown(
                    modelName: "claude-opus-5", inputTokens: 100, outputTokens: 50,
                    cacheCreationTokens: 10, cacheReadTokens: 900, cost: cost
                )
            ]
        )
    }

    private func codexDay(_ date: String, cost: Double) -> CodexDailyUsage {
        let tokens = CodexTokens(
            inputTokens: 200, cachedInputTokens: 150, outputTokens: 30, reasoningOutputTokens: 10
        )
        return CodexDailyUsage(
            date: date, tokens: tokens, estimatedCost: cost,
            modelBreakdowns: [
                CodexModelBreakdown(modelName: "gpt-5.1-codex", tokens: tokens, estimatedCost: cost)
            ]
        )
    }

    /// The dashboard only understands DailyUsage, so Codex has to arrive in that shape.
    func testCodexDaysConvertWithoutInventingCacheWrites() {
        let converted = ProviderUsage.asDailyUsage(codexDay("2026-08-04", cost: 4.25))

        XCTAssertEqual(converted.date, "2026-08-04")
        XCTAssertEqual(converted.totalCost, 4.25)
        XCTAssertEqual(converted.inputTokens, 50, "input already includes the cached half")
        XCTAssertEqual(converted.cacheReadTokens, 150)
        XCTAssertEqual(converted.cacheCreationTokens, 0)
        XCTAssertEqual(converted.modelBreakdowns.first?.modelName, "gpt-5.1-codex")
    }

    func testMergeSumsMatchingDaysAndLeavesOthersAlone() {
        let merged = ProviderUsage.merge(
            [claudeDay("2026-08-03", cost: 10), claudeDay("2026-08-04", cost: 20)],
            [ProviderUsage.asDailyUsage(codexDay("2026-08-04", cost: 5))]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].totalCost, 10)
        XCTAssertEqual(merged[1].totalCost, 25)
        XCTAssertEqual(merged[1].modelBreakdowns.count, 2, "both providers keep their own rows")
    }

    /// A Codex day outside the visible week must not stretch the chart.
    func testWindowKeepsOnlyTheDaysTheWeekAlreadyShows() {
        let week = UsageData(
            todayCost: 0, last7Days: [claudeDay("2026-08-03", cost: 1), claudeDay("2026-08-04", cost: 2)],
            monthTotal: 3, isCurrentWeek: true, weekStart: Date(), weekEnd: Date(),
            lastRefreshDate: Date(), earliestDate: "2026-08-01"
        )
        let windowed = ProviderUsage.window(
            [
                ProviderUsage.asDailyUsage(codexDay("2026-07-30", cost: 9)),
                ProviderUsage.asDailyUsage(codexDay("2026-08-04", cost: 5)),
            ],
            like: week
        )

        XCTAssertEqual(windowed.map(\.date), ["2026-08-04"])
    }

    func testScopeMembership() {
        XCTAssertTrue(UsageScope.all.includes(.claude))
        XCTAssertTrue(UsageScope.all.includes(.codex))
        XCTAssertTrue(UsageScope.provider(.codex).includes(.codex))
        XCTAssertFalse(UsageScope.provider(.codex).includes(.claude))
        XCTAssertEqual(UsageScope.provider(.claude).id, "claude")
        XCTAssertEqual(UsageScope.all.label, "All providers")
    }

    func testScopeListStaysSingleUntilASecondProviderHasData() {
        let settings = SettingsStore()
        let usage = ProviderUsage(claude: UsageService(settings: settings), codex: CodexUsageService())
        XCTAssertEqual(usage.availableProviders, [.claude])
        XCTAssertEqual(usage.availableScopes.map(\.id), ["claude"], "no chip worth showing yet")

        usage.codex.response = CodexUsageResponse(
            daily: [codexDay("2026-08-04", cost: 5)], tokens: CodexTokens(),
            estimatedCost: 5, rateLimits: nil, skippedCompressedFiles: 0
        )
        XCTAssertEqual(usage.availableScopes.map(\.id), ["all", "claude", "codex"])
    }
}
