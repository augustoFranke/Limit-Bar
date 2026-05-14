import AppKit
import Foundation

/// Adapter that owns a `CodexAppServerClient` per slot and translates Codex's
/// JSON-RPC surface into `AccountSlot` updates.
@MainActor
final class CodexUsageSource: AccountUsageSource {
    let provider: AccountProvider = .codex

    private var clients: [Int: CodexAppServerClient] = [:]

    func attach(slotID: Int) async throws {
        guard clients[slotID] == nil else { return }
        let client = try CodexAppServerClient(slot: slotID)
        clients[slotID] = client
        try await client.start()
    }

    func detach(slotID: Int) async {
        clients[slotID] = nil
    }

    func addAccount(slotID: Int, statusUpdate: (String) -> Void) async throws -> AccountSlot {
        statusUpdate("Opening Codex login")
        let client = try CodexAppServerClient(slot: slotID)
        clients[slotID] = client
        do {
            try await client.start()
            statusUpdate("Complete Codex login in your browser")
            try await performInteractiveLogin(client: client)
            statusUpdate("Fetching Codex limits")
            return try await buildReadySlot(slotID: slotID, client: client)
        } catch {
            clients[slotID] = nil
            throw error
        }
    }

    func refresh(slot: AccountSlot) async throws -> AccountSlot {
        guard let client = clients[slot.id] else {
            throw LimitBarError.processUnavailable
        }
        do {
            return try await buildReadySlot(slotID: slot.id, client: client)
        } catch let error as LimitBarError {
            throw classify(error)
        }
    }

    func login(slot: AccountSlot) async throws -> AccountSlot {
        guard let client = clients[slot.id] else {
            throw LimitBarError.processUnavailable
        }
        try await performInteractiveLogin(client: client)
        return try await buildReadySlot(slotID: slot.id, client: client)
    }

    func logout(slot: AccountSlot) async throws -> AccountSlot {
        guard let client = clients[slot.id] else {
            throw LimitBarError.processUnavailable
        }
        _ = try await client.requestUntyped("account/logout", params: [:])
        KeychainStore.deleteAccountMarker(slot: slot.id)

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

    /// Open the Codex auth URL in the browser and poll account/read until
    /// the user finishes signing in (or the deadline expires).
    private func performInteractiveLogin(client: CodexAppServerClient) async throws {
        let login: LoginStartResponse = try await client.request(
            "account/login/start",
            params: ["type": "chatgpt", "codexStreamlinedLogin": true]
        )

        guard let authUrl = login.authUrl, let url = URL(string: authUrl) else {
            throw LimitBarError.message("Codex did not return a login URL.")
        }

        NSWorkspace.shared.open(url)

        let deadline = Date().addingTimeInterval(LimitBarConstants.codexLoginDeadline)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: LimitBarConstants.codexLoginPollNanoseconds)
            let account: AccountReadResponse = try await client.request(
                "account/read",
                params: ["refreshToken": true]
            )
            if let payload = account.account, payload.type == "chatgpt" {
                return
            }
        }

        throw LimitBarError.loginRequired(detail: "Codex login timed out.")
    }

    private func buildReadySlot(slotID: Int, client: CodexAppServerClient) async throws -> AccountSlot {
        let account: AccountReadResponse = try await client.request(
            "account/read",
            params: ["refreshToken": true]
        )
        guard let payload = account.account, payload.type == "chatgpt" else {
            throw LimitBarError.loginRequired(detail: "Codex account is not signed in.")
        }

        if let email = payload.email {
            AccountSlotStore.saveEmail(email, for: slotID)
        }

        let limits: RateLimitResponse = try await client.request("account/rateLimits/read", params: [:])
        let snapshot = limits.codexSnapshot
        let mapped = snapshot.limitWindows
        let displayEmail = payload.email
            ?? AccountSlotStore.savedEmail(for: slotID)
            ?? "Codex"

        return AccountSlot(
            id: slotID,
            provider: .codex,
            email: displayEmail,
            planType: Self.planLabel(rawPlanType: payload.planType ?? snapshot.planType),
            status: .ready,
            weekly: mapped.weekly,
            fiveHour: mapped.fiveHour,
            lastRefresh: Date()
        )
    }

    static func planLabel(rawPlanType: String?) -> String? {
        guard let rawPlanType, !rawPlanType.isEmpty else { return nil }
        let humanized = rawPlanType.replacingOccurrences(of: "_", with: " ").capitalized
        return "Codex・\(humanized)"
    }

    /// Codex returns opaque `LimitBarError.message(...)` for JSON-RPC errors.
    /// Promote a small allowlist of known auth phrases to `.loginRequired`
    /// so the orchestrator can render the right state without string-matching.
    private func classify(_ error: LimitBarError) -> LimitBarError {
        if case .message(let text) = error {
            let lowered = text.lowercased()
            for keyword in ["unauthorized", "not authenticated", "sign in", "log in", "login required"] {
                if lowered.contains(keyword) {
                    return .loginRequired(detail: text)
                }
            }
        }
        return error
    }
}
