import XCTest
@testable import Burn

@MainActor
final class GitHostStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var createdServices: [String] = []

    /// Never the real burn.forgejo.token: reading an item owned by the app prompts and hangs the run.
    private var legacyService: String!

    override func setUp() {
        suiteName = "burn.tests.hosts-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        legacyService = "burn.tests.legacy-\(UUID().uuidString)"
        createdServices = [legacyService]
    }

    override func tearDown() {
        for service in createdServices {
            KeychainStore.delete(service: service)
        }
        createdServices = []
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> GitHostStore {
        GitHostStore(defaults: defaults, legacyTokenService: legacyService)
    }

    private func track(_ hosts: [GitHostConfig]) -> [GitHostConfig] {
        createdServices.append(contentsOf: hosts.map(\.tokenService))
        return hosts
    }

    // MARK: - Migration

    func testMigratesOwnersAndForgejoHostIntoOneRowEach() {
        defaults.set(["carta"], forKey: PullRequestExtension.ownersKey)
        defaults.set("git.carta.rocks", forKey: PullRequestExtension.forgejoHostKey)
        KeychainStore.write("legacy-token", service: legacyService)

        let store = makeStore()
        let hosts = track(store.hosts)

        XCTAssertEqual(hosts.count, 2)
        XCTAssertEqual(hosts[0].host, "github.com")
        XCTAssertEqual(hosts[0].kind, .github)
        XCTAssertEqual(hosts[0].org, "carta")
        XCTAssertEqual(hosts[1].host, "git.carta.rocks")
        XCTAssertEqual(hosts[1].kind, .selfHosted)
        XCTAssertEqual(hosts[1].org, "carta")
    }

    /// The self-hosted row has to adopt the old token or PRs silently stop resolving after upgrade.
    func testSelfHostedRowAdoptsTheLegacyTokenOnFirstRead() throws {
        defaults.set(["carta"], forKey: PullRequestExtension.ownersKey)
        defaults.set("git.carta.rocks", forKey: PullRequestExtension.forgejoHostKey)
        KeychainStore.write("legacy-token", service: legacyService)

        let store = makeStore()
        let hosts = track(store.hosts)
        let selfHosted = try XCTUnwrap(hosts.first { $0.kind == .selfHosted })
        XCTAssertTrue(selfHosted.adoptsLegacyToken)

        guard case .value(let token) = store.token(for: selfHosted) else {
            return XCTFail("expected the legacy token to carry over")
        }
        XCTAssertEqual(token, "legacy-token")
        XCTAssertEqual(store.hosts.last?.adoptsLegacyToken, false, "adoption should happen once")
        guard case .value = KeychainStore.read(service: selfHosted.tokenService) else {
            return XCTFail("the token should now live under the row's own service")
        }
        guard case .value = KeychainStore.read(service: legacyService) else {
            return XCTFail("legacy item should stay for downgrades")
        }
    }

    /// A keychain prompt on the launch path freezes the app, so init must not touch the keychain.
    func testInitDoesNotReadTheKeychain() {
        defaults.set(["carta"], forKey: PullRequestExtension.ownersKey)
        defaults.set("git.carta.rocks", forKey: PullRequestExtension.forgejoHostKey)
        var reads: [String] = []

        let store = GitHostStore(
            defaults: defaults,
            legacyTokenService: legacyService,
            readToken: { service in
                reads.append(service)
                return .missing
            }
        )
        _ = track(store.hosts)

        XCTAssertTrue(reads.isEmpty, "init read the keychain: \(reads)")
    }

    func testMigrationWithoutLegacyConfigCreatesOneGitHubRowForAllOrgs() {
        let store = makeStore()
        let hosts = track(store.hosts)

        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].host, "github.com")
        XCTAssertTrue(hosts[0].org.isEmpty)
        XCTAssertEqual(hosts[0].owners, [], "empty org means every org the CLI can see")
    }

    func testMigrationRunsOnceAndKeepsIdsStable() {
        defaults.set(["carta"], forKey: PullRequestExtension.ownersKey)
        let first = track(makeStore().hosts)
        let second = makeStore().hosts

        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testEveryOwnerBecomesItsOwnRow() {
        defaults.set(["carta", "acme"], forKey: PullRequestExtension.ownersKey)
        defaults.set("git.example.com", forKey: PullRequestExtension.forgejoHostKey)

        let hosts = track(makeStore().hosts)

        XCTAssertEqual(hosts.count, 4)
        XCTAssertEqual(hosts.filter { $0.kind == .github }.map(\.org), ["carta", "acme"])
        XCTAssertEqual(hosts.filter { $0.kind == .selfHosted }.map(\.org), ["carta", "acme"])
    }

    // MARK: - Store

    func testUpsertReplacesByIdAndPersists() {
        let store = makeStore()
        var host = GitHostConfig(host: "git.example.com", org: "acme")
        createdServices.append(host.tokenService)
        store.upsert(host)
        host.org = "renamed"
        store.upsert(host)

        XCTAssertEqual(store.hosts.filter { $0.id == host.id }.count, 1)
        XCTAssertEqual(makeStore().hosts.last?.org, "renamed")
    }

    func testRemoveTakesTheTokenWithIt() {
        let store = makeStore()
        let host = GitHostConfig(host: "git.example.com", org: "acme")
        createdServices.append(host.tokenService)
        store.upsert(host)
        store.setToken("tok", for: host)
        XCTAssertTrue(store.hasToken(host))

        store.remove(host.id)

        XCTAssertFalse(store.hosts.contains { $0.id == host.id })
        guard case .missing = KeychainStore.read(service: host.tokenService) else {
            return XCTFail("removing a host must delete its keychain item")
        }
    }

    func testSetTokenWithBlankInputClearsIt() {
        let store = makeStore()
        let host = GitHostConfig(host: "git.example.com", org: "acme")
        createdServices.append(host.tokenService)
        store.setToken("tok", for: host)
        store.setToken("   ", for: host)

        XCTAssertFalse(store.hasToken(host))
    }

    // MARK: - Config

    func testGitHubDetection() {
        XCTAssertTrue(GitHostConfig.isGitHubDotCom("github.com"))
        XCTAssertTrue(GitHostConfig.isGitHubDotCom("https://GitHub.com"))
        XCTAssertTrue(GitHostConfig.isGitHubDotCom(" github.com "))
        XCTAssertFalse(GitHostConfig.isGitHubDotCom("git.carta.rocks"))
        XCTAssertFalse(GitHostConfig.isGitHubDotCom("github.company.com"))
    }

    /// GitHub can scope to every org; a self-hosted row without an org has nothing to query.
    func testSaveableRules() {
        XCTAssertTrue(GitHostConfig(host: "github.com", org: "").isSaveable)
        XCTAssertFalse(GitHostConfig(host: "  ", org: "carta").isSaveable)
        XCTAssertFalse(GitHostConfig(host: "git.example.com", org: " ").isSaveable)
        XCTAssertTrue(GitHostConfig(host: "git.example.com", org: "acme").isSaveable)
    }

    func testTokenServiceIsScopedPerHost() {
        let a = GitHostConfig(host: "git.example.com", org: "acme")
        let b = GitHostConfig(host: "git.example.com", org: "acme")

        XCTAssertNotEqual(a.tokenService, b.tokenService)
        XCTAssertTrue(a.tokenService.hasPrefix("burn.host.token."))
    }
}
