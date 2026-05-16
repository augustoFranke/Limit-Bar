import AppKit
import Foundation
import os

/// Provider-agnostic orchestrator. Owns the slot list, dispatches to the
/// per-provider `AccountUsageSource`, and fans out post-refresh side effects
/// (notification scheduling, persistence). Heavy lifting lives behind sources.
@MainActor
final class AccountsModel: ObservableObject {
    @Published private(set) var slots: [AccountSlot]
    @Published var isRefreshing = false
    @Published var pendingAdd: PendingAccountAdd?

    private let sources: [AccountProvider: any AccountUsageSource]
    private let slotStore: any AccountSlotStoring
    private let notifications: any AccountNotificationScheduling
    private let presentAddAccountError: @MainActor (AccountProvider, String) -> Void
    private var lastRefresh: [Int: Date] = [:]
    private var scheduler: RefreshScheduler?

    convenience init() {
        self.init(
            codexSource: CodexUsageSource(),
            claudeSource: ClaudeCodeUsageSource()
        )
    }

    init(
        codexSource: any AccountUsageSource,
        claudeSource: any AccountUsageSource,
        slotStore: any AccountSlotStoring = UserDefaultsAccountSlotStore(),
        notifications: any AccountNotificationScheduling = LimitNotificationScheduler.shared,
        presentAddAccountError: (@MainActor (AccountProvider, String) -> Void)? = nil
    ) {
        self.sources = [
            .codex: codexSource,
            .claude: claudeSource
        ]
        self.slotStore = slotStore
        self.notifications = notifications
        self.presentAddAccountError = presentAddAccountError ?? AccountsModel.showAddAccountError
        self.slots = slotStore.restoreSlots()
    }

    func start() async {
        for slot in slots {
            await attach(slot)
        }
        let scheduler = RefreshScheduler(
            refreshSlot: { [weak self] id, force in
                await self?.refresh(id, force: force)
            },
            slotIDs: { [weak self] in
                self?.slots.map(\.id) ?? []
            }
        )
        self.scheduler = scheduler
        await scheduler.kick(force: true)
        scheduler.start()
    }

    // MARK: - Add / login / logout

    func addCodexAccount() async { await addAccount(provider: .codex) }

    func addClaudeAccount() async {
        if let existing = slots.first(where: { $0.provider == .claude }) {
            pendingAdd = nil
            await refresh(existing.id)
            return
        }
        await addAccount(provider: .claude)
    }

    private func addAccount(provider: AccountProvider) async {
        guard let source = sources[provider] else { return }
        let index = nextAccountID()
        pendingAdd = PendingAccountAdd(provider: provider, statusText: "Preparing \(provider.displayName)")

        do {
            let slot = try await source.addAccount(slotID: index) { [weak self] text in
                self?.pendingAdd?.statusText = text
            }
            slotStore.saveProvider(provider, for: index)
            if let email = slot.email {
                slotStore.saveEmail(email, for: index)
            }
            slotStore.saveSlotIDs(slots.map(\.id) + [index])
            slots.append(slot)
            lastRefresh[index] = Date()
            await scheduleNotifications(for: slot)
            pendingAdd = nil
        } catch {
            await sources[provider]?.detach(slotID: index)
            slotStore.deleteStoredAccount(for: index)
            pendingAdd = nil
            presentAddAccountError(provider, error.localizedDescription)
        }
    }

    func login(_ index: Int) async {
        guard let slot = slots.first(where: { $0.id == index }),
              let source = sources[slot.provider] else { return }
        setStatus(.authenticating, for: index)
        do {
            let updated = try await source.login(slot: slot)
            applyUpdated(updated)
        } catch let error as LimitBarError where error.isLoginRequired {
            markLoginRequired(index)
        } catch {
            setStatus(.error(error.localizedDescription), for: index)
        }
    }

    func logout(_ index: Int) async {
        guard let slot = slots.first(where: { $0.id == index }),
              let source = sources[slot.provider] else { return }
        do {
            let updated = try await source.logout(slot: slot)
            await notifications.cancelNotifications(accountIndex: index)
            applyUpdated(updated)
        } catch {
            setStatus(.error(error.localizedDescription), for: index)
        }
    }

    func removeAccount(_ index: Int) {
        guard let slotIndex = slots.firstIndex(where: { $0.id == index }),
              slots[slotIndex].status.canRemoveAccount else {
            return
        }
        let provider = slots[slotIndex].provider
        Task {
            await sources[provider]?.detach(slotID: index)
            await notifications.cancelNotifications(accountIndex: index)
        }
        slotStore.deleteStoredAccount(for: index)
        slots.remove(at: slotIndex)
        lastRefresh[index] = nil
        slotStore.saveSlots(slots)
    }

    // MARK: - Refresh

    func refreshAll() async {
        await refreshAll(force: true)
    }

    func refreshOnMenuOpen() async {
        await refreshAll(force: false)
    }

    private func refreshAll(force: Bool) async {
        guard !slots.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await scheduler?.kick(force: force)
    }

    func refresh(_ index: Int) async { await refresh(index, force: true) }

    private func refresh(_ index: Int, force: Bool) async {
        guard let slot = slots.first(where: { $0.id == index }),
              let source = sources[slot.provider] else { return }

        if !force, let last = lastRefresh[index],
           Date().timeIntervalSince(last) < LimitBarConstants.refreshDebounce {
            return
        }

        do {
            let updated = try await source.refresh(slot: slot)
            applyUpdated(updated)
            lastRefresh[index] = Date()
            await scheduleNotifications(for: updated)
        } catch let error as LimitBarError where error.isLoginRequired {
            Log.refresh.info("Slot \(index) login required during refresh")
            markLoginRequired(index)
        } catch {
            Log.refresh.error("Slot \(index) refresh failed: \(error.localizedDescription, privacy: .public)")
            setStatus(.error(error.localizedDescription), for: index)
        }
    }

    // MARK: - Internal helpers

    private func attach(_ slot: AccountSlot) async {
        guard let source = sources[slot.provider] else { return }
        if slot.provider == .codex {
            setStatus(.starting, for: slot.id)
        }
        do {
            try await source.attach(slotID: slot.id)
            if slot.provider == .codex {
                setStatus(.loading, for: slot.id)
            }
        } catch {
            Log.refresh.error("Slot \(slot.id) attach failed: \(error.localizedDescription, privacy: .public)")
            setStatus(.error(error.localizedDescription), for: slot.id)
        }
    }

    private func scheduleNotifications(for slot: AccountSlot) async {
        guard let email = slot.email else { return }
        await notifications.scheduleResetNotifications(
            accountIndex: slot.id,
            provider: slot.provider,
            email: email,
            fiveHour: slot.fiveHour,
            weekly: slot.weekly
        )
    }

    private func applyUpdated(_ updated: AccountSlot) {
        if let email = updated.email {
            slotStore.saveEmail(email, for: updated.id)
        }
        updateSlot(updated.id) { $0 = updated }
    }

    private func setStatus(_ status: AccountStatus, for index: Int) {
        updateSlot(index) { $0.status = status }
    }

    private func markLoginRequired(_ index: Int) {
        updateSlot(index) {
            $0.email = $0.email ?? slotStore.savedEmail(for: index)
            if $0.weekly == nil && $0.fiveHour == nil {
                $0.planType = nil
                $0.status = .unauthenticated
            } else {
                $0.status = .loginRequired
            }
        }
    }

    private func updateSlot(_ index: Int, _ update: (inout AccountSlot) -> Void) {
        guard let slotIndex = slots.firstIndex(where: { $0.id == index }) else { return }
        var copy = slots[slotIndex]
        update(&copy)
        slots[slotIndex] = copy
    }

    private func nextAccountID() -> Int {
        let used = Set(slots.map(\.id))
        var index = 0
        while used.contains(index) { index += 1 }
        return index
    }

    private static func showAddAccountError(provider: AccountProvider, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(provider.displayName) account was not added"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
