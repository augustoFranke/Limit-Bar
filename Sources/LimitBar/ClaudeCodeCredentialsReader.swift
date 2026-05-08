import Foundation

struct ClaudeCodeOAuthCredentials: Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
}

struct ClaudeCodeAccountIdentity: Equatable {
    let email: String?
    let organizationName: String?
}

protocol ClaudeCodeCredentialFileReading {
    func readValidJSONString(at url: URL) -> String?
}

protocol ClaudeCodeCredentialKeychainReading {
    func readGenericPassword(service: String, account: String) -> String?
    func listServiceNames(prefix: String, account: String) -> [String]
}

protocol ClaudeCodeCredentialDefaults {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeObject(forKey key: String)
}

protocol ClaudeCodeCredentialEnvironment {
    var homeDirectory: URL { get }
    var claudeConfigDirectory: URL? { get }
    var username: String { get }
}

struct ClaudeCodeCredentialsResolver {
    static let legacyServiceName = "Claude Code-credentials"
    static let hashedServicePrefix = "Claude Code-credentials-"
    static let resolvedServiceNameKey = "ClaudeCodeCredentialsReader.resolvedServiceName"

    private let files: any ClaudeCodeCredentialFileReading
    private let keychain: any ClaudeCodeCredentialKeychainReading
    private let defaults: any ClaudeCodeCredentialDefaults
    private let environment: any ClaudeCodeCredentialEnvironment

    init(
        files: any ClaudeCodeCredentialFileReading,
        keychain: any ClaudeCodeCredentialKeychainReading,
        defaults: any ClaudeCodeCredentialDefaults,
        environment: any ClaudeCodeCredentialEnvironment
    ) {
        self.files = files
        self.keychain = keychain
        self.defaults = defaults
        self.environment = environment
    }

    func readCredentials() throws -> ClaudeCodeOAuthCredentials {
        if let json = readCredentialsFile() {
            return try Self.parseCredentialsJSON(json)
        }

        if let json = readKeychainCredentialsValue() {
            if let credentials = try? Self.parseCredentialsJSON(json) {
                return credentials
            }
            if let token = Self.extractAccessTokenViaRegex(from: json) {
                return ClaudeCodeOAuthCredentials(accessToken: token, expiresAt: nil, subscriptionType: nil)
            }
        }

        throw LimitBarError.loginRequired(
            detail: "Claude Code credentials were not found. Install Claude Code from claude.com/claude-code and run `claude login`."
        )
    }

    func readAccountIdentity() -> ClaudeCodeAccountIdentity? {
        for url in claudeConfigCandidates {
            guard let json = files.readValidJSONString(at: url),
                  let identity = Self.parseAccountIdentityJSON(json) else {
                continue
            }
            return identity
        }
        return nil
    }

    func invalidateCachedServiceName() {
        defaults.removeObject(forKey: Self.resolvedServiceNameKey)
    }

    // MARK: - Parsing

    static func parseCredentialsJSON(_ jsonString: String) throws -> ClaudeCodeOAuthCredentials {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            throw LimitBarError.loginRequired(detail: "Claude Code credentials are missing an access token.")
        }

        let expiresAt: Date? = {
            guard let raw = oauth["expiresAt"] as? Double else { return nil }
            // Claude Code stores expiresAt in milliseconds-since-epoch. Anything
            // above ~10^12 is unambiguously milliseconds (year 2001+ in ms vs
            // year 33658 in seconds), so we convert. Smaller values are seconds.
            let epochSeconds = raw > 1_000_000_000_000 ? raw / 1000.0 : raw
            return Date(timeIntervalSince1970: epochSeconds)
        }()

        return ClaudeCodeOAuthCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    static func parseAccountIdentityJSON(_ jsonString: String) -> ClaudeCodeAccountIdentity? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthAccount = root["oauthAccount"] as? [String: Any] else {
            return nil
        }

        let email = oauthAccount["emailAddress"] as? String
            ?? oauthAccount["email"] as? String
        let organizationName = oauthAccount["organizationName"] as? String
            ?? oauthAccount["organization_name"] as? String
        return ClaudeCodeAccountIdentity(email: email, organizationName: organizationName)
    }

    /// Last-resort extraction when the keychain blob is truncated. Claude Code
    /// keychain items can exceed the 2KB visible-via-`security` limit; the
    /// raw blob may be valid JSON that decodes fine, or a fragment from which
    /// only the access token is recoverable.
    static func extractAccessTokenViaRegex(from rawString: String) -> String? {
        let pattern = "\"accessToken\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawString, range: NSRange(rawString.startIndex..., in: rawString)),
              let tokenRange = Range(match.range(at: 1), in: rawString) else {
            return nil
        }
        return String(rawString[tokenRange])
    }

    // MARK: - Source resolution

    private func readCredentialsFile() -> String? {
        credentialsFileCandidates.firstNonNil { files.readValidJSONString(at: $0) }
    }

    private func readKeychainCredentialsValue() -> String? {
        let serviceName = resolveServiceName()
        return keychain.readGenericPassword(service: serviceName, account: environment.username)
    }

    /// Resolves the keychain service name once and caches it. Tries the legacy
    /// name first; on miss, looks up the v2.1.52+ hashed-suffix variant via
    /// `SecItemCopyMatching` (no subprocess).
    private func resolveServiceName() -> String {
        if let persisted = defaults.string(forKey: Self.resolvedServiceNameKey), !persisted.isEmpty {
            return persisted
        }

        if keychain.readGenericPassword(service: Self.legacyServiceName, account: environment.username) != nil {
            defaults.set(Self.legacyServiceName, forKey: Self.resolvedServiceNameKey)
            return Self.legacyServiceName
        }

        let hashedNames = keychain.listServiceNames(prefix: Self.hashedServicePrefix, account: environment.username)
        if let hashed = hashedNames.first {
            defaults.set(hashed, forKey: Self.resolvedServiceNameKey)
            return hashed
        }
        return Self.legacyServiceName
    }

    private var claudeDirectory: URL {
        environment.claudeConfigDirectory ?? environment.homeDirectory.appendingPathComponent(".claude")
    }

    private var credentialsFileCandidates: [URL] {
        [
            claudeDirectory.appendingPathComponent(".credentials.json"),
            claudeDirectory.appendingPathComponent("credentials.json")
        ]
    }

    private var claudeConfigCandidates: [URL] {
        var urls: [URL] = []
        if let configDir = environment.claudeConfigDirectory {
            urls.append(configDir.appendingPathComponent(".claude.json"))
        }
        urls.append(environment.homeDirectory.appendingPathComponent(".claude.json"))
        urls.append(environment.homeDirectory.appendingPathComponent(".claude").appendingPathComponent(".claude.json"))
        return urls
    }
}

/// Reads Claude Code's OAuth credentials. Strategy:
///   1. `~/.claude/.credentials.json` (the on-disk source of truth, never truncated).
///   2. The `Claude Code-credentials` keychain item (or its hashed-suffix variant
///      written by Claude Code v2.1.52+), via `Security.framework`.
enum ClaudeCodeCredentialsReader {
    static func readCredentials() throws -> ClaudeCodeOAuthCredentials {
        try liveResolver.readCredentials()
    }

    static func readAccountIdentity() -> ClaudeCodeAccountIdentity? {
        liveResolver.readAccountIdentity()
    }

    static func invalidateCachedServiceName() {
        liveResolver.invalidateCachedServiceName()
    }

    static func parseCredentialsJSON(_ jsonString: String) throws -> ClaudeCodeOAuthCredentials {
        try ClaudeCodeCredentialsResolver.parseCredentialsJSON(jsonString)
    }

    static func parseAccountIdentityJSON(_ jsonString: String) -> ClaudeCodeAccountIdentity? {
        ClaudeCodeCredentialsResolver.parseAccountIdentityJSON(jsonString)
    }

    static func extractAccessTokenViaRegex(from rawString: String) -> String? {
        ClaudeCodeCredentialsResolver.extractAccessTokenViaRegex(from: rawString)
    }

    private static var liveResolver: ClaudeCodeCredentialsResolver {
        ClaudeCodeCredentialsResolver(
            files: FileSystemClaudeCodeCredentialReader(),
            keychain: KeychainClaudeCodeCredentialReader(),
            defaults: UserDefaultsClaudeCodeCredentialCache(),
            environment: ProcessClaudeCodeCredentialEnvironment()
        )
    }
}

private struct FileSystemClaudeCodeCredentialReader: ClaudeCodeCredentialFileReading {
    func readValidJSONString(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              (try? JSONSerialization.jsonObject(with: data)) != nil,
              let json = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty else {
            return nil
        }
        return json
    }
}

private struct KeychainClaudeCodeCredentialReader: ClaudeCodeCredentialKeychainReading {
    func readGenericPassword(service: String, account: String) -> String? {
        KeychainStore.readGenericPassword(service: service, account: account)
    }

    func listServiceNames(prefix: String, account: String) -> [String] {
        KeychainStore.listServiceNames(prefix: prefix, account: account)
    }
}

private struct UserDefaultsClaudeCodeCredentialCache: ClaudeCodeCredentialDefaults {
    func string(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct ProcessClaudeCodeCredentialEnvironment: ClaudeCodeCredentialEnvironment {
    var homeDirectory: URL {
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    var claudeConfigDirectory: URL? {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: $0)
        }
    }

    var username: String {
        NSUserName()
    }
}

private extension Array {
    func firstNonNil<T>(_ transform: (Element) -> T?) -> T? {
        for element in self {
            if let value = transform(element) {
                return value
            }
        }
        return nil
    }
}
