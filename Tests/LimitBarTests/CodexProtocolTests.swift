import XCTest
@testable import LimitBar

final class CodexProtocolTests: XCTestCase {
    func testFiveHourMappedFromPrimary() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1700000000},
            "secondary": {"usedPercent": 17, "windowDurationMins": 10080, "resetsAt": 1700001000},
            "planType": "pro"
          },
          "rateLimitsByLimitId": null
        }
        """
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
        let windows = response.rateLimits.limitWindows

        XCTAssertEqual(windows.fiveHour?.usedPercent, 42)
        XCTAssertEqual(windows.fiveHour?.windowMinutes, 300)
        XCTAssertEqual(windows.weekly?.usedPercent, 17)
        XCTAssertEqual(windows.weekly?.windowMinutes, 10080)
    }

    func testWeeklyAcceptsAnyDurationOverThreshold() throws {
        let monthly = 30 * 24 * 60
        let json = """
        {
          "rateLimits": {
            "primary": {"usedPercent": 80, "windowDurationMins": \(monthly), "resetsAt": 1700000000},
            "secondary": null,
            "planType": "pro"
          },
          "rateLimitsByLimitId": null
        }
        """
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
        let windows = response.rateLimits.limitWindows

        XCTAssertGreaterThanOrEqual(monthly, LimitBarConstants.weeklyWindowMinutes)
        XCTAssertEqual(windows.weekly?.windowMinutes, monthly)
        XCTAssertNil(windows.fiveHour)
    }

    func testFiveHourNotInferredFromArbitraryDuration() throws {
        // Neither window matches 300 minutes; fiveHour must stay nil
        // (locks in the bug fix from the refactor — the old code returned
        // `windows.first` as a fallback).
        let json = """
        {
          "rateLimits": {
            "primary": {"usedPercent": 50, "windowDurationMins": 60, "resetsAt": 1700000000},
            "secondary": {"usedPercent": 25, "windowDurationMins": 120, "resetsAt": 1700001000},
            "planType": "pro"
          },
          "rateLimitsByLimitId": null
        }
        """
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
        let windows = response.rateLimits.limitWindows

        XCTAssertNil(windows.fiveHour)
        XCTAssertNil(windows.weekly)
    }

    func testPlanTypePreservedFromSnapshot() throws {
        let json = """
        {
          "rateLimits": {
            "primary": null,
            "secondary": null,
            "planType": "pro"
          },
          "rateLimitsByLimitId": null
        }
        """
        let response = try JSONDecoder().decode(RateLimitResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.rateLimits.planType, "pro")
    }
}
