import Foundation

/// Per-provider adapter for the account-source seam. Two implementations
/// (Codex, Claude Code) satisfy this protocol; `AccountsModel` is provider-agnostic.
@MainActor
protocol AccountUsageSource: AnyObject {
    var provider: AccountProvider { get }

    /// Called for each persisted slot on app launch. Used to spawn long-running
    /// resources (e.g. Codex's app-server). No-op for stateless sources.
    func attach(slotID: Int) async throws

    /// Called when a slot is removed. Cleans up resources owned by `attach`.
    func detach(slotID: Int) async

    /// Add a fresh account at the given slot ID. Returns the populated slot
    /// (status `.ready`) or throws. Status updates flow through `statusUpdate`.
    func addAccount(slotID: Int, statusUpdate: (String) -> Void) async throws -> AccountSlot

    /// Refresh an existing slot. Returns an updated slot with new limits.
    func refresh(slot: AccountSlot) async throws -> AccountSlot

    /// Re-authenticate an existing slot. Returns an updated, ready slot.
    func login(slot: AccountSlot) async throws -> AccountSlot

    /// Sign out an existing slot. Returns the slot in `.unauthenticated` state.
    func logout(slot: AccountSlot) async throws -> AccountSlot
}
