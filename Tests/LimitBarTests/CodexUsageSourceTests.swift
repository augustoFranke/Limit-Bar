import XCTest
@testable import LimitBar

@MainActor
final class CodexUsageSourceTests: XCTestCase {
    func testPlanLabelPrefixesCodexPlan() {
        XCTAssertEqual(CodexUsageSource.planLabel(rawPlanType: "plus"), "Codex・Plus")
        XCTAssertEqual(CodexUsageSource.planLabel(rawPlanType: "pro"), "Codex・Pro")
    }

    func testPlanLabelHumanizesCompoundPlan() {
        XCTAssertEqual(CodexUsageSource.planLabel(rawPlanType: "chatgpt_plus"), "Codex・Chatgpt Plus")
    }

    func testPlanLabelOmitsEmptyPlan() {
        XCTAssertNil(CodexUsageSource.planLabel(rawPlanType: nil))
        XCTAssertNil(CodexUsageSource.planLabel(rawPlanType: ""))
    }
}
