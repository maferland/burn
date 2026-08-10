import XCTest
@testable import Burn

final class EmberMotionTests: XCTestCase {
    /// Repeated manual refreshes on a quiet day shouldn't pretend something happened.
    func testRefreshOnlySpinsWhenTheNumbersMoved() {
        XCTAssertEqual(EmberMotion.refreshRotation(before: "$18 today", after: "$21 today"), 360)
        XCTAssertEqual(EmberMotion.refreshRotation(before: "$18 today", after: "$18 today"), 15)
    }

    /// A status line that goes from absent to present still counts as news.
    func testAppearingFromNothingCountsAsAChange() {
        XCTAssertEqual(EmberMotion.refreshRotation(before: "", after: "$4 today"), 360)
        XCTAssertEqual(EmberMotion.refreshRotation(before: "", after: ""), 15)
    }

    func testStaggerWalksDownTheRowsAndNeverGoesBackwards() {
        XCTAssertEqual(EmberMotion.revealDelay(row: 0), 0)
        XCTAssertEqual(EmberMotion.revealDelay(row: 2), 0.08, accuracy: 0.0001)
        XCTAssertEqual(EmberMotion.revealDelay(row: -1), 0, "a negative index would delay into the past")
    }
}
