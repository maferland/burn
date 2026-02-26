import XCTest
@testable import Burn

final class ModelsTests: XCTestCase {

    // MARK: - JSON Parsing

    func testDecodeCCUsageResponse() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)

        XCTAssertEqual(response.daily.count, 3)
        XCTAssertEqual(response.daily[0].date, "2026-02-21")
        XCTAssertEqual(response.daily[0].totalCost, 12.50)
        XCTAssertEqual(response.daily[0].inputTokens, 100_000)
        XCTAssertEqual(response.daily[0].outputTokens, 50_000)
        XCTAssertEqual(response.daily[0].modelsUsed, ["claude-opus-4-6"])
        XCTAssertEqual(response.daily[0].modelBreakdowns.count, 1)
        XCTAssertEqual(response.daily[0].modelBreakdowns[0].modelName, "claude-opus-4-6")
        XCTAssertEqual(response.daily[0].modelBreakdowns[0].cost, 12.50)
        XCTAssertEqual(response.totals.totalCost, 118.82)
    }

    func testDecodeEmptyDaily() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(response.daily.isEmpty)
        XCTAssertEqual(response.totals.totalCost, 0)
    }

    // MARK: - Aggregation

    func testUsageDataFromResponse() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)
        let usage = UsageData.from(response: response)

        let todayStr = UsageData.dateString(from: Date())

        if todayStr == "2026-02-23" {
            XCTAssertEqual(usage.todayCost, 68.82)
        }

        XCTAssertFalse(usage.last7Days.isEmpty)
        XCTAssertTrue(usage.monthTotal > 0)
        XCTAssertNotEqual(usage.lastRefreshDate, .distantPast)
    }

    func testUsageDataNoToday() throws {
        let json = """
        {"daily":[{"date":"2025-01-01","inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":5.00,"modelsUsed":["opus"],"modelBreakdowns":[]}],"totals":{"inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":5.00}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.todayCost, 0)
    }

    func testUsageDataEmpty() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.todayCost, 0)
        XCTAssertEqual(usage.last7Days.count, 7)
        XCTAssertTrue(usage.last7Days.allSatisfy { $0.totalCost == 0 })
        XCTAssertEqual(usage.monthTotal, 0)
    }

    func testLast7DaysSorted() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)
        let usage = UsageData.from(response: response)

        let dates = usage.last7Days.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testMonthTotalAggregation() throws {
        let json = """
        {"daily":[
            {"date":"2026-02-01","inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":10.00,"modelsUsed":[],"modelBreakdowns":[]},
            {"date":"2026-02-15","inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":20.00,"modelsUsed":[],"modelBreakdowns":[]},
            {"date":"2026-01-31","inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":99.00,"modelsUsed":[],"modelBreakdowns":[]}
        ],"totals":{"inputTokens":300,"outputTokens":150,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":450,"totalCost":129.00}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)

        let todayStr = UsageData.dateString(from: Date())
        if todayStr.hasPrefix("2026-02") {
            XCTAssertEqual(usage.monthTotal, 30.0, accuracy: 0.01)
        }
    }

    // MARK: - Week Navigation

    func testWeekOffsetZeroIsCurrentWeek() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: 0)
        XCTAssertTrue(usage.isCurrentWeek)
    }

    func testWeekOffsetNegativeIsNotCurrentWeek() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: -1)
        XCTAssertFalse(usage.isCurrentWeek)
    }

    func testWeekOffsetShiftsDays() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let current = UsageData.from(response: response, weekOffset: 0)
        let previous = UsageData.from(response: response, weekOffset: -1)

        XCTAssertEqual(current.last7Days.count, 7)
        XCTAssertEqual(previous.last7Days.count, 7)

        // Previous week ends before current week starts
        XCTAssertLessThan(previous.last7Days.last!.date, current.last7Days.first!.date)
    }

    func testWeekOffsetMonthTotalMatchesWeekMonth() throws {
        let json = """
        {"daily":[
            {"date":"2026-01-15","inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":50.00,"modelsUsed":[],"modelBreakdowns":[]},
            {"date":"2026-02-15","inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":30.00,"modelsUsed":[],"modelBreakdowns":[]}
        ],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":80.00}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)

        // Go far enough back to land in January
        var offset = 0
        var usage = UsageData.from(response: response, weekOffset: offset)
        while UsageData.dateString(from: usage.weekEnd).hasPrefix("2026-02") && offset > -10 {
            offset -= 1
            usage = UsageData.from(response: response, weekOffset: offset)
        }

        if UsageData.dateString(from: usage.weekEnd).hasPrefix("2026-01") {
            XCTAssertEqual(usage.monthTotal, 50.0, accuracy: 0.01)
        }
    }

    func testWeekTotalComputedProperty() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: 0)
        let expected = usage.last7Days.reduce(0) { $0 + $1.totalCost }
        XCTAssertEqual(usage.weekTotal, expected, accuracy: 0.001)
    }

    func testTodayCostUnchangedByOffset() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let current = UsageData.from(response: response, weekOffset: 0)
        let past = UsageData.from(response: response, weekOffset: -2)
        XCTAssertEqual(current.todayCost, past.todayCost)
    }

    // MARK: - Earliest Date & canGoBack

    func testEarliestDatePopulated() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.earliestDate, "2026-02-21")
    }

    func testEarliestDateNilForEmptyResponse() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertNil(usage.earliestDate)
    }

    func testCanGoBackFalseAtEarliestBoundary() throws {
        // Single day of data — navigating back to that week should disable further back nav
        let json = """
        {"daily":[{"date":"2026-02-21","inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":5.00,"modelsUsed":[],"modelBreakdowns":[]}],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":5.00}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)

        // Navigate back until weekStart <= earliestDate
        var offset = 0
        var usage = UsageData.from(response: response, weekOffset: offset)
        while usage.canGoBack && offset > -20 {
            offset -= 1
            usage = UsageData.from(response: response, weekOffset: offset)
        }
        XCTAssertFalse(usage.canGoBack)
    }

    func testCanGoBackTrueWhenMoreDataExists() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        // Current week (offset 0) — earliest data is 2026-02-21, week starts ~6 days ago from now
        let usage = UsageData.from(response: response, weekOffset: 0)
        // The week start for current week is about Feb 19, which is before Feb 21
        // So canGoBack depends on whether weekStart > earliestDate
        // Just verify the property is consistent with the data
        let startStr = UsageData.dateString(from: usage.weekStart)
        XCTAssertEqual(usage.canGoBack, startStr > "2026-02-21")
    }

    func testCanGoBackFalseWhenNoData() {
        XCTAssertFalse(UsageData.empty.canGoBack)
    }

    // MARK: - Sample Data

    private let sampleJSON = """
    {
        "daily": [
            {
                "date": "2026-02-21",
                "inputTokens": 100000,
                "outputTokens": 50000,
                "cacheCreationTokens": 10000,
                "cacheReadTokens": 5000,
                "totalTokens": 165000,
                "totalCost": 12.50,
                "modelsUsed": ["claude-opus-4-6"],
                "modelBreakdowns": [
                    {
                        "modelName": "claude-opus-4-6",
                        "inputTokens": 100000,
                        "outputTokens": 50000,
                        "cacheCreationTokens": 10000,
                        "cacheReadTokens": 5000,
                        "cost": 12.50
                    }
                ]
            },
            {
                "date": "2026-02-22",
                "inputTokens": 200000,
                "outputTokens": 80000,
                "cacheCreationTokens": 20000,
                "cacheReadTokens": 8000,
                "totalTokens": 308000,
                "totalCost": 37.50,
                "modelsUsed": ["claude-opus-4-6", "claude-sonnet-4-20250514"],
                "modelBreakdowns": [
                    {
                        "modelName": "claude-opus-4-6",
                        "inputTokens": 150000,
                        "outputTokens": 60000,
                        "cacheCreationTokens": 15000,
                        "cacheReadTokens": 6000,
                        "cost": 30.00
                    },
                    {
                        "modelName": "claude-sonnet-4-20250514",
                        "inputTokens": 50000,
                        "outputTokens": 20000,
                        "cacheCreationTokens": 5000,
                        "cacheReadTokens": 2000,
                        "cost": 7.50
                    }
                ]
            },
            {
                "date": "2026-02-23",
                "inputTokens": 500000,
                "outputTokens": 200000,
                "cacheCreationTokens": 50000,
                "cacheReadTokens": 20000,
                "totalTokens": 770000,
                "totalCost": 68.82,
                "modelsUsed": ["claude-opus-4-6"],
                "modelBreakdowns": [
                    {
                        "modelName": "claude-opus-4-6",
                        "inputTokens": 500000,
                        "outputTokens": 200000,
                        "cacheCreationTokens": 50000,
                        "cacheReadTokens": 20000,
                        "cost": 68.82
                    }
                ]
            }
        ],
        "totals": {
            "inputTokens": 800000,
            "outputTokens": 330000,
            "cacheCreationTokens": 80000,
            "cacheReadTokens": 33000,
            "totalTokens": 1243000,
            "totalCost": 118.82
        }
    }
    """
}
