import Foundation

/// Adapter that satisfies `AccountUsageSource` for the Claude Code CLI's
/// OAuth credentials. Stateless: there is no per-slot resource to manage.
@MainActor
final class ClaudeCodeUsageSource: AccountUsageSource {
    let provider: AccountProvider = .claude

    private let usageClient: ClaudeCodeUsageClient

    init(usageClient: ClaudeCodeUsageClient = ClaudeCodeUsageClient()) {
        self.usageClient = usageClient
    }

    func attach(slotID: Int) async throws {}
    func detach(slotID: Int) async {}

    func addAccount(slotID: Int, statusUpdate: (String) -> Void) async throws -> AccountSlot {
        statusUpdate("Detecting Claude Code login")
        let credentials = try ClaudeCodeCredentialsReader.readCredentials()
        let identity = ClaudeCodeCredentialsReader.readAccountIdentity()

        statusUpdate("Fetching Claude usage")
        let usage = try await usageClient.fetchUsage(accessToken: credentials.accessToken)

        return makeSlot(slotID: slotID, credentials: credentials, identity: identity, usage: usage)
    }

    func refresh(slot: AccountSlot) async throws -> AccountSlot {
        let credentials = try ClaudeCodeCredentialsReader.readCredentials()
        let identity = ClaudeCodeCredentialsReader.readAccountIdentity()
        let usage = try await usageClient.fetchUsage(accessToken: credentials.accessToken)
        return makeSlot(slotID: slot.id, credentials: credentials, identity: identity, usage: usage)
    }

    func login(slot: AccountSlot) async throws -> AccountSlot {
        ClaudeCodeCredentialsReader.invalidateCachedServiceName()
        return try await refresh(slot: slot)
    }

    func logout(slot: AccountSlot) async throws -> AccountSlot {
        var updated = slot
        updated.email = updated.email ?? AccountSlotStore.savedEmail(for: slot.id)
        updated.planType = nil
        updated.weekly = nil
        updated.fiveHour = nil
        updated.lastRefresh = nil
        updated.status = .unauthenticated
        return updated
    }

    // MARK: - Private

    private func makeSlot(
        slotID: Int,
        credentials: ClaudeCodeOAuthCredentials,
        identity: ClaudeCodeAccountIdentity?,
        usage: ClaudeCodeUsage
    ) -> AccountSlot {
        let displayEmail = identity?.email
            ?? identity?.organizationName
            ?? AccountSlotStore.savedEmail(for: slotID)
            ?? "Claude Code"
        AccountSlotStore.saveEmail(displayEmail, for: slotID)

        return AccountSlot(
            id: slotID,
            provider: .claude,
            email: displayEmail,
            planType: planLabel(credentials: credentials, identity: identity),
            status: .ready,
            weekly: usage.weekly,
            fiveHour: usage.fiveHour,
            lastRefresh: Date()
        )
    }

    private func planLabel(
        credentials: ClaudeCodeOAuthCredentials,
        identity: ClaudeCodeAccountIdentity?
    ) -> String {
        if let raw = credentials.subscriptionType, !raw.isEmpty {
            let humanized = raw.replacingOccurrences(of: "_", with: " ").capitalized
            return "Claude Code · \(humanized)"
        }
        if let organization = identity?.organizationName, !organization.isEmpty {
            return "Claude Code · \(organization)"
        }
        return "Claude Code"
    }
}
