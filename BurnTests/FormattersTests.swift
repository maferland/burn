import XCTest
@testable import Burn

final class FormattersTests: XCTestCase {

    func testCostPartsSplitsDollarsFromCents() {
        let parts = Formatters.costParts(194.13)
        XCTAssertEqual(parts.whole, "$194")
        XCTAssertEqual(parts.cents, ".13")
    }

    func testCostPartsGroupsThousandsAndPadsCents() {
        XCTAssertEqual(Formatters.costParts(2318.4).whole, "$2,318")
        XCTAssertEqual(Formatters.costParts(12.05).cents, ".05")
        XCTAssertEqual(Formatters.costParts(0).cents, ".00")
    }

    func testCostPartsRoundsRatherThanTruncating() {
        let parts = Formatters.costParts(9.999)
        XCTAssertEqual(parts.whole, "$10")
        XCTAssertEqual(parts.cents, ".00")
    }

    func testCostRoundedDropsCents() {
        XCTAssertEqual(Formatters.costRounded(4424.62), "$4,425")
    }

    func testComparisonReadsAsOverOrUnder() {
        XCTAssertEqual(Formatters.comparison(value: 150, baseline: 100), "50% over a typical day")
        XCTAssertEqual(Formatters.comparison(value: 50, baseline: 100), "50% under a typical day")
        XCTAssertEqual(Formatters.comparison(value: 101, baseline: 100), "right on a typical day")
    }

    func testComparisonNeedsBothSides() {
        XCTAssertNil(Formatters.comparison(value: 10, baseline: 0))
        XCTAssertNil(Formatters.comparison(value: 0, baseline: 10))
    }

    func testModelLabelReadsClaudeAndGPTNames() {
        XCTAssertEqual(Formatters.modelLabel("claude-opus-4-7"), "Opus 4.7")
        XCTAssertEqual(Formatters.modelLabel("claude-sonnet-4-5"), "Sonnet 4.5")
        XCTAssertEqual(Formatters.modelLabel("gpt-5.1-codex-max"), "GPT-5.1 Codex Max")
        XCTAssertEqual(Formatters.modelLabel("unknown"), "Unknown")
    }

    func testCodexLabelDropsTheVendorPrefix() {
        XCTAssertEqual(Formatters.codexModelLabel("gpt-5.1-codex"), "5.1 Codex")
        XCTAssertEqual(Formatters.codexModelLabel("unknown"), "Unknown")
    }

    func testAgoUsesTheCoarsestUnitThatFits() {
        XCTAssertEqual(Formatters.ago(Date().addingTimeInterval(-30)), "just now")
        XCTAssertEqual(Formatters.ago(Date().addingTimeInterval(-600)), "10m ago")
        XCTAssertEqual(Formatters.ago(Date().addingTimeInterval(-7_200)), "2h ago")
        XCTAssertEqual(Formatters.ago(Date().addingTimeInterval(-172_800)), "2d ago")
    }

    func testResetLabelSwitchesToWeekdayBeyondToday() {
        let soon = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        XCTAssertTrue(Formatters.resetLabel(soon).hasPrefix("resets "))
        let later = Date().addingTimeInterval(4 * 86_400)
        XCTAssertEqual(Formatters.resetLabel(later).count, "resets Mon".count)
    }
}
