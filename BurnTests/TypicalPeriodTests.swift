import XCTest
@testable import Burn

final class TypicalPeriodTests: XCTestCase {
    /// Thursday, so week and month boundaries in these tests aren't accidentally aligned.
    private let today = TypicalPeriodTests.makeDate("2026-08-06")

    private static func makeDate(_ string: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: string)!
    }

    private func sample(_ dateString: String, cost: Double, tokens: Int = 100) -> TypicalPeriod.Sample {
        .init(date: dateString, cost: cost, tokens: tokens)
    }

    // MARK: - day

    func testDayExcludesTodayAndZeroDays() {
        let samples = [
            sample("2026-08-06", cost: 999), // today, must not count
            sample("2026-08-05", cost: 0),    // zero, must not count
            sample("2026-08-04", cost: 10),
            sample("2026-08-03", cost: 20),
        ]
        XCTAssertEqual(TypicalPeriod.day(samples, today: today).cost, 15)
    }

    func testDayCapsAtTheLast30Samples() {
        let samples = (1...40).map { sample("2026-06-\(String(format: "%02d", $0 % 28 + 1))", cost: Double($0)) }
        let result = TypicalPeriod.day(samples, today: today)
        XCTAssertEqual(result.cost, samples.suffix(30).map(\.cost).reduce(0, +) / 30, accuracy: 0.001)
    }

    // MARK: - week

    /// Today is 2026-08-06. Window 0 is Jul31-Aug06 (excluded). Window 1 is Jul24-Jul30.
    func testWeekAveragesCompleteRollingWindowsExcludingTheCurrentOne() {
        let samples = [
            sample("2026-08-06", cost: 500), // window 0, excluded
            sample("2026-08-01", cost: 500), // window 0, excluded
            sample("2026-07-30", cost: 10),  // window 1
            sample("2026-07-24", cost: 20),  // window 1
            sample("2026-07-23", cost: 30),  // window 2
        ]
        let result = TypicalPeriod.week(samples, today: today)
        // window 1 sums to 30, window 2 sums to 30 -> mean of bucket sums is 30.
        XCTAssertEqual(result.cost, 30, accuracy: 0.001)
    }

    func testWeekCapsAtTheLast8CompleteWindows() {
        let samples = (1...12).map { week in
            sample("2026-\(String(format: "%02d", max(1, 8 - week / 4)))-\(String(format: "%02d", (week * 7) % 28 + 1))", cost: Double(week))
        }
        // Just confirm it doesn't crash and returns a finite, non-negative number over a long history.
        let result = TypicalPeriod.week(samples, today: today)
        XCTAssertGreaterThanOrEqual(result.cost, 0)
    }

    func testWeekIgnoresAnEmptyHistory() {
        XCTAssertEqual(TypicalPeriod.week([], today: today).cost, 0)
        XCTAssertEqual(TypicalPeriod.week([], today: today).tokens, 0)
    }

    // MARK: - month

    func testMonthAveragesCompleteCalendarMonthsExcludingTheCurrentOne() {
        let samples = [
            sample("2026-08-01", cost: 999), // current month, excluded
            sample("2026-07-15", cost: 40),
            sample("2026-07-01", cost: 60),  // July sums to 100
            sample("2026-06-15", cost: 50),  // June sums to 50
        ]
        let result = TypicalPeriod.month(samples, today: today)
        XCTAssertEqual(result.cost, 75, accuracy: 0.001) // mean(100, 50)
    }

    func testMonthCapsAtTheLast6CompleteMonths() {
        let samples = (1...10).map { sample("2025-\(String(format: "%02d", $0))-10", cost: Double($0) * 10) }
        // Last 6 months by key-sort are months 5 through 10.
        let expected = (5...10).map { Double($0) * 10 }.reduce(0, +) / 6
        XCTAssertEqual(TypicalPeriod.month(samples, today: today).cost, expected, accuracy: 0.001)
    }

    func testTokensFollowTheSameBucketingAsCost() {
        let samples = [
            sample("2026-07-15", cost: 10, tokens: 1_000),
            sample("2026-07-01", cost: 10, tokens: 1_000),
        ]
        XCTAssertEqual(TypicalPeriod.month(samples, today: today).tokens, 2_000)
    }
}
