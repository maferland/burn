import XCTest
import ClaudeUsageKit
@testable import Burn

@MainActor
final class ExtensionStateTests: XCTestCase {
    private func day(_ date: String, cost: Double) -> DailyUsage {
        DailyUsage(
            date: date, inputTokens: 100, outputTokens: 50,
            cacheCreationTokens: 0, cacheReadTokens: 0,
            totalTokens: 150, totalCost: cost,
            modelsUsed: ["claude-opus-5"], modelBreakdowns: []
        )
    }

    private func response(_ days: [DailyUsage]) -> CCUsageResponse {
        CCUsageResponse(
            daily: days,
            totals: Totals(
                inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                cacheReadTokens: 0, totalTokens: 0,
                totalCost: days.reduce(0) { $0 + $1.totalCost }
            )
        )
    }

    /// Points the disk cache at nothing, so these read the values under test and not the dev machine's.
    private func makeUsage() -> UsageExtension {
        let settings = SettingsStore()
        let ext = UsageExtension(
            service: UsageService(settings: settings, cacheFile: Self.emptyCache),
            codexService: CodexUsageService(),
            settings: settings
        )
        ext.scope = .provider(.claude)
        return ext
    }

    private static let emptyCache = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("burn-tests-no-cache.json")

    private var today: String { UsageData.dateString(from: Date()) }

    /// Lands data the way a finished refresh does: the raw response and the derived aggregate together.
    private func load(_ ext: UsageExtension, _ days: [DailyUsage]) {
        let response = response(days)
        ext.service.lastResponse = response
        ext.service.usageData = UsageData.from(response: response)
    }

    func testFirstReadIsLoadingAndLaterOnesAreNot() {
        let ext = makeUsage()
        ext.service.isLoading = true
        XCTAssertEqual(ext.state, .loading)

        load(ext, [day(today, cost: 12)])
        XCTAssertEqual(ext.state, .live, "a refresh under real numbers is not a loading state")
    }

    func testDormantWhenTodayHasNoSpendYet() {
        let ext = makeUsage()
        load(ext, [day("2026-08-01", cost: 12)])
        XCTAssertEqual(ext.state, .dormant)
    }

    func testFailureWinsOverCachedNumbers() {
        let ext = makeUsage()
        load(ext, [day(today, cost: 12)])
        ext.service.errorMessage = "log directory unreadable"
        XCTAssertEqual(ext.state, .failed("log directory unreadable"))
    }

    /// Grey for both loading and a closed day; the dot only goes amber when money is moving.
    func testDotColours() {
        XCTAssertEqual(ExtensionState.live.dotColor, Ember.accent)
        XCTAssertEqual(ExtensionState.failed("x").dotColor, Ember.danger)
        XCTAssertEqual(ExtensionState.loading.dotColor, ExtensionState.dormant.dotColor)
        XCTAssertNotEqual(ExtensionState.dormant.dotColor, Ember.accent)
    }

    func testFailureMessageOnlyReadsBackFromFailed() {
        XCTAssertEqual(ExtensionState.failed("boom").failureMessage, "boom")
        XCTAssertNil(ExtensionState.live.failureMessage)
    }

    /// A dead host must not blank PRs that other hosts returned.
    func testPullRequestsKeepPartialResultsOnFailure() {
        let settings = SettingsStore()
        let ext = PullRequestExtension(
            usageService: UsageService(settings: settings, cacheFile: Self.emptyCache),
            hostStore: GitHostStore(defaults: UserDefaults(suiteName: #function)!)
        )
        ext.errorMessage = "bad credentials"
        XCTAssertEqual(ext.state, .failed("bad credentials"))

        ext.prs = [
            PullRequest(
                url: "https://example.com/1", title: "Ship it", createdAt: Date(),
                repository: .init(nameWithOwner: "carta/web"), state: "OPEN", closedAt: nil
            )
        ]
        ext.lastRefresh = Date()
        XCTAssertEqual(ext.state, .live, "partial data downgrades the failure to a banner")
    }

    /// Browsing to a past week must not stick past the popover closing and reopening.
    func testResetBrowsingReturnsUsageToToday() {
        let ext = makeUsage()
        ext.period = .month
        ext.weekOffset = -2
        ext.monthOffset = -1
        ext.selectedDayId = "2026-01-01"

        ext.resetBrowsing()

        XCTAssertEqual(ext.period, .day)
        XCTAssertEqual(ext.weekOffset, 0)
        XCTAssertEqual(ext.monthOffset, 0)
        XCTAssertNil(ext.selectedDayId)
    }
}
