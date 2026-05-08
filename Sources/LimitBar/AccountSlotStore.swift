import Foundation

/// Persisted slot metadata: which slots exist, what provider/email each holds,
/// where Codex's per-slot home directory lives. UserDefaults-backed; the
/// Keychain and filesystem are touched only via the small surface below.
enum AccountSlotStore {
    private static let accountCountKey = "accountCount"
    private static let activeSlotIDsKey = "activeSlotIDs"
    private static let providerKeyPrefix = "account.provider."

    // MARK: - Slot list

    static func restoreSlots() -> [AccountSlot] {
        let slotIDs = restoredSlotIDs().filter(isRestorableAccount)
        for index in slotIDs {
            cleanLegacyArtifacts(for: index)
        }
        saveSlotIDs(slotIDs)

        return slotIDs.map { index in
            AccountSlot(id: index, provider: savedProvider(for: index), email: savedEmail(for: index))
        }
    }

    static func saveSlots(_ slots: [AccountSlot]) {
        saveSlotIDs(slots.map(\.id))
    }

    static func saveSlotIDs(_ slotIDs: [Int]) {
        let ids = Array(Set(slotIDs)).sorted()
        UserDefaults.standard.set(ids, forKey: activeSlotIDsKey)
        UserDefaults.standard.set((ids.max() ?? -1) + 1, forKey: accountCountKey)
    }

    // MARK: - Per-slot fields

    static func savedEmail(for index: Int) -> String? {
        UserDefaults.standard.string(forKey: emailKey(for: index))
    }

    static func saveEmail(_ email: String, for index: Int) {
        UserDefaults.standard.set(email, forKey: emailKey(for: index))
    }

    static func savedProvider(for index: Int) -> AccountProvider {
        guard let rawValue = UserDefaults.standard.string(forKey: providerKey(for: index)) else {
            return .codex
        }
        return AccountProvider(rawValue: rawValue) ?? .codex
    }

    static func saveProvider(_ provider: AccountProvider, for index: Int) {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey(for: index))
    }

    // MARK: - Codex home (single source of truth)

    /// Application Support directory for the per-slot Codex home, or nil when
    /// Application Support is unavailable. `CodexAppServerClient` and the
    /// removal path both go through this.
    static func codexHome(for index: Int, create: Bool) -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ) else {
            return nil
        }
        return support
            .appendingPathComponent("LimitBar", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("account-\(index + 1)", isDirectory: true)
    }

    /// Codex used to live at `Application Support/CodexLimitBar/...` before the
    /// rename. Migrate the on-disk home if the new path is empty.
    static func migrateLegacyCodexHomeIfNeeded(for index: Int) throws {
        guard let target = codexHome(for: index, create: false) else { return }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let legacy = support
            .appendingPathComponent("CodexLimitBar", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("account-\(index + 1)", isDirectory: true)

        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: target.path) else { return }
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: legacy, to: target)
    }

    // MARK: - Removal

    static func deleteStoredAccount(for index: Int) {
        UserDefaults.standard.removeObject(forKey: emailKey(for: index))
        UserDefaults.standard.removeObject(forKey: providerKey(for: index))
        cleanLegacyArtifacts(for: index)
        KeychainStore.deleteAccountMarker(slot: index)

        if let home = codexHome(for: index, create: false) {
            try? FileManager.default.removeItem(at: home)
        }
    }

    /// One-shot cleanup for slots that were created by older versions of the
    /// app (cookie-based Claude flow, "admin key" prototype). Safe to remove
    /// from this codebase after a future release.
    private static func cleanLegacyArtifacts(for index: Int) {
        UserDefaults.standard.removeObject(forKey: legacyClaudeOrgIDKey(for: index))
        UserDefaults.standard.removeObject(forKey: legacyClaudeOrgNameKey(for: index))
        KeychainStore.deleteLegacyClaudeArtifacts(slot: index)
    }

    // MARK: - Restoration helpers

    private static func restoredSlotIDs() -> [Int] {
        if let savedIDs = UserDefaults.standard.object(forKey: activeSlotIDsKey) as? [Int] {
            return savedIDs.sorted()
        }
        let savedCount = UserDefaults.standard.integer(forKey: accountCountKey)
        guard savedCount > 0 else { return [] }
        let lastKnown = (0..<savedCount).last { isRestorableAccount($0) }
        return Array(0..<((lastKnown ?? -1) + 1))
    }

    private static func isRestorableAccount(_ index: Int) -> Bool {
        if let email = savedEmail(for: index), !isPlaceholderEmail(email, for: index) {
            return true
        }
        switch savedProvider(for: index) {
        case .codex: return hasStoredCodexAuth(for: index)
        case .claude: return false
        }
    }

    private static func isPlaceholderEmail(_ email: String, for index: Int) -> Bool {
        email == "Account \(index + 1)" || email == "Claude Account \(index + 1)"
    }

    private static func hasStoredCodexAuth(for index: Int) -> Bool {
        guard let auth = codexHome(for: index, create: false)?.appendingPathComponent("auth.json") else {
            return false
        }
        return FileManager.default.fileExists(atPath: auth.path)
    }

    // MARK: - Key shapes

    private static func emailKey(for index: Int) -> String { "account.\(index).email" }
    private static func providerKey(for index: Int) -> String { "\(providerKeyPrefix)\(index)" }
    private static func legacyClaudeOrgIDKey(for index: Int) -> String { "account.\(index).claude.organizationID" }
    private static func legacyClaudeOrgNameKey(for index: Int) -> String { "account.\(index).claude.organizationName" }
}
