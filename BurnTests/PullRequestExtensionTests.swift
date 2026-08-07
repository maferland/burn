import XCTest
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
            repository: .init(nameWithOwner: "carta/web"),
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

        XCTAssertEqual(ext.todayOpenCount, 0, "the count stays period-scoped, per the issue")
        XCTAssertEqual(ext.openPRs.count, 5, "but the list itself must still see all five")
    }

    /// effectiveDate is what both the fetch sort and the period filters key off.
    func testEffectiveDatePrefersMergedOverCreated() {
        let open = pr("open", opened: 3)
        XCTAssertEqual(open.effectiveDate, open.createdAt)

        let merged = pr("merged", opened: 3, merged: true)
        XCTAssertEqual(merged.effectiveDate, merged.mergedAt)
    }
}
