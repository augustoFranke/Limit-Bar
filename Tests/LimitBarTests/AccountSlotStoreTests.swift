import XCTest
@testable import LimitBar

/// AccountSlotStore is hard-coded to UserDefaults.standard, so these tests
/// mutate the global defaults domain. To stay isolated we:
///   - use slot indices in the 9000+ range (no overlap with real app slots),
///   - snapshot/restore the `activeSlotIDs` key around each test,
///   - explicitly remove every key we touch in tearDown.
/// Tests that would require the production code to accept an injected
/// UserDefaults instance are skipped with a comment.
final class AccountSlotStoreTests: XCTestCase {
    private let testSlots = [9001, 9002]
    private let activeSlotIDsKey = "activeSlotIDs"
    private let accountCountKey = "accountCount"
    private var savedActiveSlotIDs: Any?
    private var savedAccountCount: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedActiveSlotIDs = defaults.object(forKey: activeSlotIDsKey)
        savedAccountCount = defaults.object(forKey: accountCountKey)
        cleanTestSlotKeys()
    }

    override func tearDown() {
        cleanTestSlotKeys()
        let defaults = UserDefaults.standard
        if let savedActiveSlotIDs {
            defaults.set(savedActiveSlotIDs, forKey: activeSlotIDsKey)
        } else {
            defaults.removeObject(forKey: activeSlotIDsKey)
        }
        if let savedAccountCount {
            defaults.set(savedAccountCount, forKey: accountCountKey)
        } else {
            defaults.removeObject(forKey: accountCountKey)
        }
        super.tearDown()
    }

    private func cleanTestSlotKeys() {
        let defaults = UserDefaults.standard
        for index in testSlots {
            defaults.removeObject(forKey: "account.\(index).email")
            defaults.removeObject(forKey: "account.provider.\(index)")
            defaults.removeObject(forKey: "account.\(index).claude.organizationID")
            defaults.removeObject(forKey: "account.\(index).claude.organizationName")
        }
    }

    func testSavedProviderDefaultsToCodexWhenUnset() {
        XCTAssertEqual(AccountSlotStore.savedProvider(for: 9001), .codex)
    }

    func testSaveAndReadEmail() {
        AccountSlotStore.saveEmail("real@example.com", for: 9001)
        XCTAssertEqual(AccountSlotStore.savedEmail(for: 9001), "real@example.com")
    }

    func testSaveAndReadProvider() {
        AccountSlotStore.saveProvider(.claude, for: 9001)
        XCTAssertEqual(AccountSlotStore.savedProvider(for: 9001), .claude)
    }

    func testRestoreSlotsRecognizesNonPlaceholderEmail() {
        AccountSlotStore.saveEmail("real@example.com", for: 9001)
        AccountSlotStore.saveProvider(.claude, for: 9001)
        AccountSlotStore.saveSlotIDs([9001])

        let slots = AccountSlotStore.restoreSlots()
        XCTAssertTrue(slots.contains { $0.id == 9001 })
    }

    func testRestoreSlotsDropsPlaceholderClaudeAccount() {
        // isPlaceholderEmail compares against "Claude Account \(index + 1)".
        AccountSlotStore.saveEmail("Claude Account 9002", for: 9001)
        AccountSlotStore.saveProvider(.claude, for: 9001)
        AccountSlotStore.saveSlotIDs([9001])

        let slots = AccountSlotStore.restoreSlots()
        XCTAssertFalse(slots.contains { $0.id == 9001 })
    }

    func testRestoreSlotsDropsClaudeWithoutEmail() {
        AccountSlotStore.saveProvider(.claude, for: 9001)
        AccountSlotStore.saveSlotIDs([9001])

        let slots = AccountSlotStore.restoreSlots()
        XCTAssertFalse(slots.contains { $0.id == 9001 })
    }

    func testDeleteStoredAccountWipesUserDefaultsKeys() {
        AccountSlotStore.saveEmail("real@example.com", for: 9001)
        AccountSlotStore.saveProvider(.claude, for: 9001)

        AccountSlotStore.deleteStoredAccount(for: 9001)

        XCTAssertNil(AccountSlotStore.savedEmail(for: 9001))
        XCTAssertEqual(AccountSlotStore.savedProvider(for: 9001), .codex)
    }

    func testCodexHomeIsStableAcrossCalls() {
        let first = AccountSlotStore.codexHome(for: 9001, create: false)
        let second = AccountSlotStore.codexHome(for: 9001, create: false)
        XCTAssertEqual(first, second)
    }
}
