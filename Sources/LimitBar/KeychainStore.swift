import Foundation
import Security

/// Thin wrapper over `Security.framework` for the marker that keys a slot's
/// Codex home directory. All other Claude-era / admin-key items are wiped via
/// `deleteLegacyClaudeArtifacts` and otherwise untouched.
enum KeychainStore {
    private static let service = "com.augustodorego.LimitBar"
    private static let legacyService = "com.augustodorego.CodexLimitBar"

    static func saveAccountMarker(slot: Int, codexHome: String) {
        let account = codexHomeAccount(slot: slot)
        save(codexHome, account: account)
        SecItemDelete(query(service: legacyService, account: account) as CFDictionary)
    }

    static func deleteAccountMarker(slot: Int) {
        let account = codexHomeAccount(slot: slot)
        SecItemDelete(query(account: account) as CFDictionary)
        SecItemDelete(query(service: legacyService, account: account) as CFDictionary)
    }

    /// One-shot cleanup of items written by the previous cookie-based Claude
    /// flow and the earlier "admin key" prototype. Safe to delete from a
    /// future release once enough users have upgraded.
    static func deleteLegacyClaudeArtifacts(slot: Int) {
        let legacyAccounts = [
            "account-\(slot + 1)-claude-cookie",
            "account-\(slot + 1)-claude-session-key",
            "account-\(slot + 1)-claude-admin-key"
        ]
        for account in legacyAccounts {
            SecItemDelete(query(account: account) as CFDictionary)
            SecItemDelete(query(service: legacyService, account: account) as CFDictionary)
        }
    }

    // MARK: - Generic-password reads (used by the Claude Code credentials reader)

    /// Reads a generic-password item by service + account. Returns the raw UTF-8
    /// value or nil. Used to talk to items written by *other* apps (e.g. the
    /// Claude Code CLI's `Claude Code-credentials*` items) without spawning
    /// `/usr/bin/security`.
    static func readGenericPassword(service: String, account: String) -> String? {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        item.removeAll() // silence "var only written" if compiler ever complains
        return String(data: data, encoding: .utf8)
    }

    /// Lists every generic-password service whose name starts with `prefix`,
    /// for the current user. Used to discover Claude Code's hashed-suffix
    /// keychain item without `security dump-keychain`.
    static func listServiceNames(prefix: String, account: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items
            .compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(prefix) }
    }

    // MARK: - Internals

    private static func codexHomeAccount(slot: Int) -> String {
        "account-\(slot + 1)-codex-home"
    }

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        SecItemDelete(query(account: account) as CFDictionary)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func query(account: String) -> [String: Any] {
        query(service: service, account: account)
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
