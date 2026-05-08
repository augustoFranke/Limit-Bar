import XCTest
@testable import LimitBar

@MainActor
final class RefreshSchedulerTests: XCTestCase {
    func testKickRefreshesCurrentSlotIDs() async {
        var refreshed: [(Int, Bool)] = []
        var ids = [1, 2]
        let scheduler = RefreshScheduler(
            refreshSlot: { id, force in
                refreshed.append((id, force))
            },
            slotIDs: { ids }
        )

        await scheduler.kick(force: true)
        ids = [3]
        await scheduler.kick(force: false)

        XCTAssertEqual(refreshed.map(\.0), [1, 2, 3])
        XCTAssertEqual(refreshed.map(\.1), [true, true, false])
    }
}
