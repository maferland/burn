import XCTest
import ClaudeUsageKit
@testable import Burn

@MainActor
final class PullRequestExtensionTests: XCTestCase {
    private func makeExtension() -> PullRequestExtension {
        PullRequestExtension(
            usageService: UsageService(settings: SettingsStore()),
            hostStore: GitHostStore(defaults: UserDefaults(suiteName: #function)!)
        )
    }

    private func pr(_ title: String, opened daysAgo: Int, merged: Bool = false) -> PullRequest {
        let createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return PullRequest(
            url: title, title: title, createdAt: createdAt,
            repository: .init(nameWithOwner: "contoso/web"),
            state: merged ? "MERGED" : "OPEN",
            closedAt: merged ? createdAt : nil
        )
    }

    /// This is the bug: a PR opened last week and never scoped into "today" used to disappear
    /// everywhere, counts and list alike. `openPRs` is the list's escape from that scoping.
    func testOpenPRsIgnoreWhenTheyWereOpened() {
        let ext = makeExtension()
        ext.prs = [pr("stale", opened: 9), pr("fresh", opened: 0)]

        XCTAssertEqual(ext.openPRs.map(\.title).sorted(), ["fresh", "stale"])
    }

    func testOpenPRsExcludeMergedRegardlessOfAge() {
        let ext = makeExtension()
        ext.prs = [pr("shipped", opened: 9, merged: true), pr("open", opened: 9)]

        XCTAssertEqual(ext.openPRs.map(\.title), ["open"])
    }

    /// Merged PRs are the half that stays scoped — "merged today" is still the interesting number.
    /// Kept to a 3-day offset so the fixture can't accidentally cross a month boundary.
    func testMergedPRsStayScopedToThePeriod() {
        let ext = makeExtension()
        ext.prs = [
            pr("today", opened: 0, merged: true),
            pr("earlier-this-month", opened: 3, merged: true),
        ]

        XCTAssertEqual(ext.mergedPRs(for: .today).map(\.title), ["today"])
        XCTAssertEqual(ext.mergedPRs(for: .month).map(\.title).sorted(), ["earlier-this-month", "today"])
    }

    /// The fix, end to end: five PRs open from last week must not vanish on a day nothing merged.
    func testFiveStaleOpensSurviveEvenWhenNothingMergedToday() {
        let ext = makeExtension()
        ext.prs = (1...5).map { pr("open-\($0)", opened: 9) }

        XCTAssertEqual(ext.stats(for: .today).openCount, 0, "the count stays period-scoped, per the issue")
        XCTAssertEqual(ext.openPRs.count, 5, "but the list itself must still see all five")
    }

    /// No PR history exists before the current month, so "typical" is a run rate off
    /// month-to-date rather than a real historical average — this locks in that math.
    func testTypicalMergedCountsAreARunRateOffMonthToDate() {
        let ext = makeExtension()
        ext.prs = [
            pr("today-1", opened: 0, merged: true),
            pr("today-2", opened: 0, merged: true),
        ]

        let elapsed = Double(Calendar.current.component(.day, from: Date()))
        let daysInMonth = Double(Calendar.current.range(of: .day, in: .month, for: Date())!.count)
        let expectedRate = 2.0 / elapsed

        XCTAssertEqual(ext.stats(for: .today).typicalCount!, expectedRate, accuracy: 0.0001)
        XCTAssertEqual(ext.stats(for: .week).typicalCount!, expectedRate * 7, accuracy: 0.0001)
        XCTAssertEqual(ext.stats(for: .month).typicalCount!, expectedRate * daysInMonth, accuracy: 0.0001)
    }

    /// stats(for:) replaced fifteen period-indexed properties with one function; this pins down
    /// that merged/open counts and the average still land on the right period.
    func testStatsCarriesTheRightCountsAndAverageForEachPeriod() {
        let ext = makeExtension()
        ext.prs = [
            pr("today-merged", opened: 0, merged: true),
            pr("today-open", opened: 0),
            pr("stale-open", opened: 9),
        ]
        ext.usageService.usageData = UsageData(
            todayCost: 40, last7Days: [], monthTotal: 40, isCurrentWeek: true,
            weekStart: Date(), weekEnd: Date(), lastRefreshDate: Date(), earliestDate: nil
        )

        let today = ext.stats(for: .today)
        XCTAssertEqual(today.mergedCount, 1)
        XCTAssertEqual(today.openCount, 1, "scoped to today, unlike ext.openPRs")
        XCTAssertEqual(today.average, 40)

        let week = ext.stats(for: .week)
        XCTAssertEqual(week.mergedCount, 1)
        XCTAssertEqual(week.average, 0, "weekTotal defaults to 0 since last7Days is empty in this fixture")
    }

    /// Open PRs and the period's merged PRs are computed separately now (Turn 11 groups them into
    /// labeled sections), so this locks in that they're the same underlying sets as before, just
    /// no longer merged into one flat, unlabeled list.
    func testOpenAndMergedStayAsSeparateGroups() {
        let ext = makeExtension()
        ext.prs = [
            pr("stale-open", opened: 9),
            pr("today-merged", opened: 0, merged: true),
        ]

        XCTAssertEqual(ext.openPRs.map(\.title), ["stale-open"])
        XCTAssertEqual(ext.mergedPRs(for: .today).map(\.title), ["today-merged"])
    }

    /// effectiveDate is what both the fetch sort and the period filters key off.
    func testEffectiveDatePrefersMergedOverCreated() {
        let open = pr("open", opened: 3)
        XCTAssertEqual(open.effectiveDate, open.createdAt)

        let merged = pr("merged", opened: 3, merged: true)
        XCTAssertEqual(merged.effectiveDate, merged.mergedAt)
    }
}
