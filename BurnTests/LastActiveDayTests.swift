import XCTest
import ClaudeUsageKit
@testable import Burn

/// The empty hero leans on this: without it the tab would show a bare zero.
@MainActor
final class LastActiveDayTests: XCTestCase {
    private func claudeDay(_ date: String, cost: Double) -> DailyUsage {
        DailyUsage(
            date: date, inputTokens: 10, outputTokens: 5,
            cacheCreationTokens: 0, cacheReadTokens: 0,
            totalTokens: 15, totalCost: cost,
            modelsUsed: [], modelBreakdowns: []
        )
    }

    private func codexDay(_ date: String, cost: Double) -> CodexDailyUsage {
        CodexDailyUsage(
            date: date,
            tokens: CodexTokens(
                inputTokens: 200, cachedInputTokens: 150, outputTokens: 30, reasoningOutputTokens: 10
            ),
            estimatedCost: cost,
            modelBreakdowns: []
        )
    }

    private func makeUsage(claude: [DailyUsage], codex: [CodexDailyUsage]) -> ProviderUsage {
        let service = UsageService(
            settings: SettingsStore(),
            cacheFile: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("burn-tests-no-cache.json")
        )
        service.lastResponse = CCUsageResponse(
            daily: claude,
            totals: Totals(
                inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                cacheReadTokens: 0, totalTokens: 0, totalCost: 0
            )
        )
        let codexService = CodexUsageService()
        codexService.response = CodexUsageResponse(
            daily: codex, tokens: CodexTokens(),
            estimatedCost: codex.reduce(0) { $0 + $1.estimatedCost },
            rateLimits: nil, skippedCompressedFiles: 0
        )
        return ProviderUsage(claude: service, codex: codexService)
    }

    func testSkipsZeroDaysAndReturnsTheMostRecentRealOne() {
        let usage = makeUsage(
            claude: [
                claudeDay("2026-08-01", cost: 30),
                claudeDay("2026-08-02", cost: 12),
                claudeDay("2026-08-03", cost: 0),
            ],
            codex: []
        )

        let latest = usage.lastActiveDay(scope: .provider(.claude), before: "2026-08-03")
        XCTAssertEqual(latest?.date, "2026-08-02")
        XCTAssertEqual(latest?.totalCost, 12)
    }

    /// "Last burn today" would be nonsense on the day that has nothing.
    func testNeverOffersTheDayAlreadyOnScreen() {
        let usage = makeUsage(claude: [claudeDay("2026-08-04", cost: 30)], codex: [])
        XCTAssertNil(usage.lastActiveDay(scope: .all, before: "2026-08-04"))
    }

    func testScopeDecidesWhichProviderCanSupplyTheFallback() {
        let usage = makeUsage(
            claude: [claudeDay("2026-08-01", cost: 30)],
            codex: [codexDay("2026-08-04", cost: 5)]
        )

        XCTAssertEqual(usage.lastActiveDay(scope: .all, before: "2026-08-05")?.date, "2026-08-04")
        XCTAssertEqual(usage.lastActiveDay(scope: .provider(.claude), before: "2026-08-05")?.date, "2026-08-01")
        XCTAssertEqual(usage.lastActiveDay(scope: .provider(.codex), before: "2026-08-05")?.date, "2026-08-04")
    }

    func testNoHistoryMeansNoFallbackRatherThanAZero() {
        let usage = makeUsage(claude: [claudeDay("2026-08-01", cost: 0)], codex: [])
        XCTAssertNil(usage.lastActiveDay(scope: .all, before: "2026-08-05"))
    }

    /// The pace track and the closed-day caption both read this; a token hero must not pace against dollars.
    func testTypicalDayIsAvailableInBothMetrics() {
        let usage = makeUsage(
            claude: [claudeDay("2026-08-01", cost: 30), claudeDay("2026-08-02", cost: 12)],
            codex: [codexDay("2026-08-04", cost: 5)]
        )

        XCTAssertEqual(usage.typicalDayCost(.provider(.claude)), 21, accuracy: 0.0001)
        XCTAssertEqual(usage.typicalDayTokens(.provider(.claude)), 15)
        XCTAssertEqual(usage.typicalDayTokens(.provider(.codex)), 80)
        XCTAssertEqual(usage.typicalDayTokens(.all), 95, "scoping sums the same way cost does")
    }

    /// The by-provider rows switch metric with the display mode, so both have to come back.
    func testBreakdownCarriesTokensAlongsideCost() {
        let usage = makeUsage(
            claude: [claudeDay("2026-08-04", cost: 8)],
            codex: [codexDay("2026-08-04", cost: 5)]
        )

        let rows = usage.breakdown(on: "2026-08-04")
        XCTAssertEqual(rows.map(\.provider), [.claude, .codex])
        XCTAssertEqual(rows.first { $0.provider == .claude }?.tokens, 15)
        XCTAssertEqual(rows.first { $0.provider == .codex }?.tokens, 80, "uncached input plus output")
    }
}
