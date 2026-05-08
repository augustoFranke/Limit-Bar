import XCTest
@testable import LimitBar

final class ClaudeCodeCredentialsReaderTests: XCTestCase {
    func testParsesValidCredentialsJSON() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1700000000000,"subscriptionType":"pro"}}"#
        let creds = try ClaudeCodeCredentialsReader.parseCredentialsJSON(json)

        XCTAssertEqual(creds.accessToken, "tok")
        XCTAssertEqual(creds.subscriptionType, "pro")
        XCTAssertEqual(creds.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testInterpretsExpiresAtAsSecondsWhenSmall() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1700000000}}"#
        let creds = try ClaudeCodeCredentialsReader.parseCredentialsJSON(json)

        XCTAssertEqual(creds.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRejectsCredentialsMissingAccessToken() {
        let json = #"{"claudeAiOauth":{}}"#
        XCTAssertThrowsError(try ClaudeCodeCredentialsReader.parseCredentialsJSON(json)) { error in
            guard let err = error as? LimitBarError, err.isLoginRequired else {
                return XCTFail("Expected loginRequired error, got \(error)")
            }
        }
    }

    func testRejectsCredentialsWithEmptyAccessToken() {
        let json = #"{"claudeAiOauth":{"accessToken":""}}"#
        XCTAssertThrowsError(try ClaudeCodeCredentialsReader.parseCredentialsJSON(json)) { error in
            guard let err = error as? LimitBarError, err.isLoginRequired else {
                return XCTFail("Expected loginRequired error, got \(error)")
            }
        }
    }

    func testRejectsTopLevelMalformedJSON() {
        XCTAssertThrowsError(try ClaudeCodeCredentialsReader.parseCredentialsJSON("not json")) { error in
            guard let err = error as? LimitBarError, err.isLoginRequired else {
                return XCTFail("Expected loginRequired error, got \(error)")
            }
        }
    }

    func testResolverReadsCredentialsFileBeforeKeychain() throws {
        let environment = FakeCredentialEnvironment()
        let fileURL = environment.claudeConfigDirectory!.appendingPathComponent(".credentials.json")
        let files = FakeCredentialFiles(values: [
            fileURL: #"{"claudeAiOauth":{"accessToken":"file-token","subscriptionType":"max"}}"#
        ])
        let keychain = FakeCredentialKeychain(passwords: [
            serviceKey(ClaudeCodeCredentialsResolver.legacyServiceName, environment.username): #"{"claudeAiOauth":{"accessToken":"keychain-token"}}"#
        ])
        let resolver = makeResolver(files: files, keychain: keychain, environment: environment)

        let credentials = try resolver.readCredentials()

        XCTAssertEqual(credentials.accessToken, "file-token")
        XCTAssertEqual(credentials.subscriptionType, "max")
    }

    func testResolverFallsBackToHashedKeychainServiceAndCachesIt() throws {
        let environment = FakeCredentialEnvironment()
        let defaults = FakeCredentialDefaults()
        let hashedService = "Claude Code-credentials-abc123"
        let keychain = FakeCredentialKeychain(
            passwords: [
                serviceKey(hashedService, environment.username): #"{"claudeAiOauth":{"accessToken":"hashed-token"}}"#
            ],
            services: [hashedService]
        )
        let resolver = makeResolver(
            keychain: keychain,
            defaults: defaults,
            environment: environment
        )

        let credentials = try resolver.readCredentials()

        XCTAssertEqual(credentials.accessToken, "hashed-token")
        XCTAssertEqual(defaults.values[ClaudeCodeCredentialsResolver.resolvedServiceNameKey], hashedService)
    }

    func testResolverUsesCachedKeychainServiceName() throws {
        let environment = FakeCredentialEnvironment()
        let defaults = FakeCredentialDefaults(values: [
            ClaudeCodeCredentialsResolver.resolvedServiceNameKey: "Claude Code-credentials-cached"
        ])
        let keychain = FakeCredentialKeychain(passwords: [
            serviceKey("Claude Code-credentials-cached", environment.username): #"{"claudeAiOauth":{"accessToken":"cached-token"}}"#
        ])
        let resolver = makeResolver(
            keychain: keychain,
            defaults: defaults,
            environment: environment
        )

        let credentials = try resolver.readCredentials()

        XCTAssertEqual(credentials.accessToken, "cached-token")
        XCTAssertTrue(keychain.listedPrefixes.isEmpty)
    }

    func testResolverExtractsTokenFromFragmentedKeychainBlob() throws {
        let environment = FakeCredentialEnvironment()
        let keychain = FakeCredentialKeychain(passwords: [
            serviceKey(ClaudeCodeCredentialsResolver.legacyServiceName, environment.username): #"... "accessToken": "fragment-token" ..."#
        ])
        let resolver = makeResolver(keychain: keychain, environment: environment)

        let credentials = try resolver.readCredentials()

        XCTAssertEqual(credentials.accessToken, "fragment-token")
        XCTAssertNil(credentials.expiresAt)
    }

    func testResolverReadsAccountIdentityFromInjectedConfigDirectory() {
        let environment = FakeCredentialEnvironment()
        let configFile = environment.claudeConfigDirectory!.appendingPathComponent(".claude.json")
        let payload = #"{"oauthAccount":{"emailAddress":"a@b.com","organizationName":"Acme"}}"#
        let resolver = makeResolver(
            files: FakeCredentialFiles(values: [configFile: payload]),
            environment: environment
        )

        let identity = resolver.readAccountIdentity()

        XCTAssertEqual(identity?.email, "a@b.com")
        XCTAssertEqual(identity?.organizationName, "Acme")
    }

    func testInvalidateCachedServiceNameRemovesDefault() {
        let defaults = FakeCredentialDefaults(values: [
            ClaudeCodeCredentialsResolver.resolvedServiceNameKey: "Claude Code-credentials-cached"
        ])
        let resolver = makeResolver(defaults: defaults)

        resolver.invalidateCachedServiceName()

        XCTAssertNil(defaults.values[ClaudeCodeCredentialsResolver.resolvedServiceNameKey])
    }

    private func makeResolver(
        files: FakeCredentialFiles = FakeCredentialFiles(),
        keychain: FakeCredentialKeychain = FakeCredentialKeychain(),
        defaults: FakeCredentialDefaults = FakeCredentialDefaults(),
        environment: FakeCredentialEnvironment = FakeCredentialEnvironment()
    ) -> ClaudeCodeCredentialsResolver {
        ClaudeCodeCredentialsResolver(
            files: files,
            keychain: keychain,
            defaults: defaults,
            environment: environment
        )
    }
}

private func serviceKey(_ service: String, _ account: String) -> String {
    "\(service)|\(account)"
}

private final class FakeCredentialFiles: ClaudeCodeCredentialFileReading {
    var values: [URL: String]

    init(values: [URL: String] = [:]) {
        self.values = values
    }

    func readValidJSONString(at url: URL) -> String? {
        values[url]
    }
}

private final class FakeCredentialKeychain: ClaudeCodeCredentialKeychainReading {
    var passwords: [String: String]
    var services: [String]
    var requestedKeys: [String] = []
    var listedPrefixes: [String] = []

    init(passwords: [String: String] = [:], services: [String] = []) {
        self.passwords = passwords
        self.services = services
    }

    func readGenericPassword(service: String, account: String) -> String? {
        requestedKeys.append(serviceKey(service, account))
        return passwords[serviceKey(service, account)]
    }

    func listServiceNames(prefix: String, account: String) -> [String] {
        listedPrefixes.append(prefix)
        return services.filter { $0.hasPrefix(prefix) }
    }
}

private final class FakeCredentialDefaults: ClaudeCodeCredentialDefaults {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values[key] = nil
    }
}

private struct FakeCredentialEnvironment: ClaudeCodeCredentialEnvironment {
    var homeDirectory = URL(fileURLWithPath: "/tmp/limitbar-home")
    var claudeConfigDirectory: URL? = URL(fileURLWithPath: "/tmp/limitbar-claude")
    var username = "limitbar-test-user"
}
