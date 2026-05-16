import XCTest
@testable import LimitBar

@MainActor
final class AccountsModelTests: XCTestCase {
    func testRefreshLoginRequiredPreservesLastKnownLimits() async {
        let existing = AccountSlot(
            id: 9001,
            provider: .codex,
            email: "user@example.com",
            planType: "Plus",
            status: .ready,
            weekly: LimitWindow(label: "Weekly limit", usedPercent: 40, windowMinutes: 10_080, resetsAt: nil),
            fiveHour: LimitWindow(label: "5-hour limit", usedPercent: 20, windowMinutes: 300, resetsAt: nil),
            lastRefresh: Date()
        )
        let store = FakeAccountSlotStore(restoredSlots: [existing])
        let source = FakeUsageSource(provider: .codex)
        source.refreshHandler = { _ in
            throw LimitBarError.loginRequired(detail: "Expired")
        }
        let model = makeModel(codexSource: source, store: store)

        await model.refresh(9001)

        XCTAssertEqual(model.slots.first?.status, .loginRequired)
        XCTAssertEqual(model.slots.first?.email, "user@example.com")
        XCTAssertEqual(model.slots.first?.weekly?.usedPercent, 40)
        XCTAssertEqual(model.slots.first?.fiveHour?.usedPercent, 20)
    }

    func testRefreshLoginRequiredWithoutLastKnownLimitsBecomesUnauthenticated() async {
        let existing = AccountSlot(id: 9001, provider: .codex, email: nil, status: .ready)
        let store = FakeAccountSlotStore(restoredSlots: [existing])
        store.emails[9001] = "saved@example.com"
        let source = FakeUsageSource(provider: .codex)
        source.refreshHandler = { _ in
            throw LimitBarError.loginRequired(detail: "Expired")
        }
        let model = makeModel(codexSource: source, store: store)

        await model.refresh(9001)

        XCTAssertEqual(model.slots.first?.status, .unauthenticated)
        XCTAssertEqual(model.slots.first?.email, "saved@example.com")
        XCTAssertNil(model.slots.first?.planType)
    }

    func testAddAccountFailureDoesNotPersistSlotAndDetachesSource() async {
        let store = FakeAccountSlotStore()
        let source = FakeUsageSource(provider: .codex)
        source.addHandler = { _, _ in
            throw LimitBarError.message("Could not add")
        }
        var presentedErrors: [(AccountProvider, String)] = []
        let model = makeModel(
            codexSource: source,
            store: store,
            presentAddAccountError: { presentedErrors.append(($0, $1)) }
        )

        await model.addCodexAccount()

        XCTAssertTrue(model.slots.isEmpty)
        XCTAssertNil(model.pendingAdd)
        XCTAssertEqual(store.deletedAccounts, [0])
        XCTAssertEqual(source.detachedSlotIDs, [0])
        XCTAssertEqual(presentedErrors.first?.0, .codex)
        XCTAssertTrue(presentedErrors.first?.1.contains("Could not add") ?? false)
    }

    func testAddAccountSuccessPersistsSlotAndSchedulesNotifications() async {
        let store = FakeAccountSlotStore()
        let notifications = FakeNotificationScheduler()
        let source = FakeUsageSource(provider: .codex)
        source.addHandler = { slotID, statusUpdate in
            statusUpdate("Fetching")
            return AccountSlot(
                id: slotID,
                provider: .codex,
                email: "new@example.com",
                status: .ready,
                weekly: LimitWindow(label: "Weekly limit", usedPercent: 10, windowMinutes: 10_080, resetsAt: Date()),
                fiveHour: nil
            )
        }
        let model = makeModel(codexSource: source, store: store, notifications: notifications)

        await model.addCodexAccount()

        XCTAssertEqual(model.slots.map(\.id), [0])
        XCTAssertEqual(store.providers[0], .codex)
        XCTAssertEqual(store.emails[0], "new@example.com")
        XCTAssertEqual(store.savedSlotIDs, [0])
        let scheduled = await notifications.scheduled
        XCTAssertEqual(scheduled.map(\.accountIndex), [0])
    }

    func testLogoutCancelsNotificationsAndAppliesUpdatedSlot() async {
        let existing = AccountSlot(id: 9001, provider: .codex, email: "user@example.com", status: .ready)
        let store = FakeAccountSlotStore(restoredSlots: [existing])
        let notifications = FakeNotificationScheduler()
        let source = FakeUsageSource(provider: .codex)
        source.logoutHandler = { slot in
            var updated = slot
            updated.status = .unauthenticated
            updated.weekly = nil
            updated.fiveHour = nil
            return updated
        }
        let model = makeModel(codexSource: source, store: store, notifications: notifications)

        await model.logout(9001)

        XCTAssertEqual(model.slots.first?.status, .unauthenticated)
        let canceled = await notifications.canceledAccountIndexes
        XCTAssertEqual(canceled, [9001])
    }

    func testMenuOpenRefreshRespectsDebounce() async {
        let existing = AccountSlot(id: 9001, provider: .codex, email: "user@example.com", status: .ready)
        let store = FakeAccountSlotStore(restoredSlots: [existing])
        let source = FakeUsageSource(provider: .codex)
        var refreshCount = 0
        source.refreshHandler = { slot in
            refreshCount += 1
            return slot
        }
        let model = makeModel(codexSource: source, store: store)
        await model.start()

        await model.refreshOnMenuOpen()
        await model.refreshOnMenuOpen()

        XCTAssertEqual(refreshCount, 1)
    }

    func testManualRefreshForcesThroughMenuOpenDebounce() async {
        let existing = AccountSlot(id: 9001, provider: .codex, email: "user@example.com", status: .ready)
        let store = FakeAccountSlotStore(restoredSlots: [existing])
        let source = FakeUsageSource(provider: .codex)
        var refreshCount = 0
        source.refreshHandler = { slot in
            refreshCount += 1
            return slot
        }
        let model = makeModel(codexSource: source, store: store)
        await model.start()

        await model.refreshOnMenuOpen()
        await model.refreshAll()

        XCTAssertEqual(refreshCount, 2)
    }

    private func makeModel(
        codexSource: FakeUsageSource? = nil,
        claudeSource: FakeUsageSource? = nil,
        store: FakeAccountSlotStore = FakeAccountSlotStore(),
        notifications: FakeNotificationScheduler = FakeNotificationScheduler(),
        presentAddAccountError: @escaping (AccountProvider, String) -> Void = { _, _ in }
    ) -> AccountsModel {
        AccountsModel(
            codexSource: codexSource ?? FakeUsageSource(provider: .codex),
            claudeSource: claudeSource ?? FakeUsageSource(provider: .claude),
            slotStore: store,
            notifications: notifications,
            presentAddAccountError: presentAddAccountError
        )
    }
}

@MainActor
private final class FakeUsageSource: AccountUsageSource {
    let provider: AccountProvider
    var attachedSlotIDs: [Int] = []
    var detachedSlotIDs: [Int] = []

    var attachHandler: (Int) async throws -> Void = { _ in }
    var addHandler: (Int, (String) -> Void) async throws -> AccountSlot = { slotID, _ in
        AccountSlot(id: slotID, provider: .codex, email: "fake@example.com", status: .ready)
    }
    var refreshHandler: (AccountSlot) async throws -> AccountSlot = { $0 }
    var loginHandler: (AccountSlot) async throws -> AccountSlot = { $0 }
    var logoutHandler: (AccountSlot) async throws -> AccountSlot = { $0 }

    init(provider: AccountProvider) {
        self.provider = provider
    }

    func attach(slotID: Int) async throws {
        attachedSlotIDs.append(slotID)
        try await attachHandler(slotID)
    }

    func detach(slotID: Int) async {
        detachedSlotIDs.append(slotID)
    }

    func addAccount(slotID: Int, statusUpdate: (String) -> Void) async throws -> AccountSlot {
        try await addHandler(slotID, statusUpdate)
    }

    func refresh(slot: AccountSlot) async throws -> AccountSlot {
        try await refreshHandler(slot)
    }

    func login(slot: AccountSlot) async throws -> AccountSlot {
        try await loginHandler(slot)
    }

    func logout(slot: AccountSlot) async throws -> AccountSlot {
        try await logoutHandler(slot)
    }
}

private final class FakeAccountSlotStore: AccountSlotStoring {
    var restoredSlots: [AccountSlot]
    var savedSlotIDs: [Int] = []
    var emails: [Int: String] = [:]
    var providers: [Int: AccountProvider] = [:]
    var deletedAccounts: [Int] = []
    var savedSlots: [[AccountSlot]] = []

    init(restoredSlots: [AccountSlot] = []) {
        self.restoredSlots = restoredSlots
    }

    func restoreSlots() -> [AccountSlot] {
        restoredSlots
    }

    func saveSlots(_ slots: [AccountSlot]) {
        savedSlots.append(slots)
        savedSlotIDs = slots.map(\.id)
    }

    func saveSlotIDs(_ slotIDs: [Int]) {
        savedSlotIDs = slotIDs
    }

    func savedEmail(for index: Int) -> String? {
        emails[index]
    }

    func saveEmail(_ email: String, for index: Int) {
        emails[index] = email
    }

    func saveProvider(_ provider: AccountProvider, for index: Int) {
        providers[index] = provider
    }

    func deleteStoredAccount(for index: Int) {
        deletedAccounts.append(index)
        emails[index] = nil
        providers[index] = nil
    }
}

private actor FakeNotificationScheduler: AccountNotificationScheduling {
    struct Scheduled: Equatable {
        let accountIndex: Int
        let provider: AccountProvider
        let email: String
    }

    private(set) var scheduled: [Scheduled] = []
    private(set) var canceledAccountIndexes: [Int] = []

    func scheduleResetNotifications(
        accountIndex: Int,
        provider: AccountProvider,
        email: String,
        fiveHour: LimitWindow?,
        weekly: LimitWindow?
    ) async {
        scheduled.append(Scheduled(accountIndex: accountIndex, provider: provider, email: email))
    }

    func cancelNotifications(accountIndex: Int) async {
        canceledAccountIndexes.append(accountIndex)
    }
}
