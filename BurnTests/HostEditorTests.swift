import XCTest
@testable import Burn

/// Drives the host form the way a click-through would: type, blur, tap Save, tap Remove twice.
@MainActor
final class HostEditorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: GitHostStore!
    private var storedTokens: [String: String] = [:]
    private var commits: [UUID?] = []
    private var createdServices: [String] = []

    override func setUp() {
        suiteName = "burn.tests.editor-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.set(Data("[]".utf8), forKey: GitHostStore.hostsKey)
        storedTokens = [:]
        commits = []
        store = GitHostStore(
            defaults: defaults,
            legacyTokenService: "burn.tests.legacy-\(UUID().uuidString)",
            readToken: { [weak self] service in
                guard let token = self?.storedTokens[service] else { return .missing }
                return .value(token)
            }
        )
    }

    override func tearDown() {
        for service in createdServices {
            KeychainStore.delete(service: service)
        }
        createdServices = []
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func editor(_ config: GitHostConfig, isNew: Bool = false) -> HostEditor {
        createdServices.append(config.tokenService)
        return HostEditor(store: store, config: config, isNew: isNew) { [weak self] id in
            self?.commits.append(id)
        }
    }

    // MARK: - Add host

    func testAddHostCannotSaveUntilBothFieldsAreFilled() {
        let editor = editor(GitHostConfig(host: "", org: ""), isNew: true)
        XCTAssertFalse(editor.canSave)

        editor.config.host = "git.example.com"
        editor.hostDidChange()
        XCTAssertFalse(editor.canSave, "a self-hosted row still needs an org")

        editor.config.org = "acme"
        XCTAssertTrue(editor.canSave)
    }

    func testTypingGitHubDotComSwitchesTheRowToCLIAuth() {
        let editor = editor(GitHostConfig(host: "", org: ""), isNew: true)
        editor.config.host = "github.com"
        editor.hostDidChange()

        XCTAssertEqual(editor.config.kind, .github)
        XCTAssertEqual(editor.tokenState, .cliManaged)
        XCTAssertTrue(editor.canSave, "github.com with no org means every org")
    }

    func testBlurringAMalformedHostBlocksSaveUntilFixed() {
        let editor = editor(GitHostConfig(host: "", org: ""), isNew: true)
        editor.config.host = "not a host"
        editor.hostDidChange()
        editor.config.org = "acme"
        editor.validateHost()

        XCTAssertNotNil(editor.hostError)
        XCTAssertFalse(editor.canSave)
        XCTAssertFalse(editor.save())
        XCTAssertTrue(store.hosts.isEmpty)

        editor.config.host = "git.example.com"
        editor.hostDidChange()
        XCTAssertNil(editor.hostError)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(store.hosts.count, 1)
    }

    func testSaveTrimsAndReportsTheSavedRow() {
        let editor = editor(GitHostConfig(host: "", org: ""), isNew: true)
        editor.config.host = "  git.example.com "
        editor.hostDidChange()
        editor.config.org = " acme "

        XCTAssertTrue(editor.save())
        XCTAssertEqual(store.hosts.first?.host, "git.example.com")
        XCTAssertEqual(store.hosts.first?.org, "acme")
        XCTAssertEqual(commits, [store.hosts.first?.id])
    }

    func testSaveStoresATokenOnlyWhenOneWasTyped() {
        let first = editor(GitHostConfig(host: "git.example.com", org: "acme"), isNew: true)
        XCTAssertTrue(first.save())
        guard case .missing = KeychainStore.read(service: first.config.tokenService) else {
            return XCTFail("an untouched token field should not write to the keychain")
        }

        let second = editor(GitHostConfig(host: "git.two.com", org: "acme"), isNew: true)
        second.tokenInput = "tok-2"
        XCTAssertTrue(second.save())
        guard case .value(let token) = KeychainStore.read(service: second.config.tokenService) else {
            return XCTFail("expected the typed token to be stored")
        }
        XCTAssertEqual(token, "tok-2")
        XCTAssertTrue(second.tokenInput.isEmpty, "the field should not keep the secret around")
    }

    // MARK: - Edit host

    func testExistingTokenStaysHiddenUntilReplaceIsTapped() {
        var config = GitHostConfig(host: "git.example.com", org: "acme")
        storedTokens[config.tokenService] = "existing"
        store.upsert(config)
        config.adoptsLegacyToken = false

        let editor = editor(config)
        XCTAssertEqual(editor.tokenState, .saved)

        editor.beginReplacingToken()
        XCTAssertEqual(editor.tokenState, .entering)
    }

    func testEditingAnExistingRowUpdatesItInPlace() {
        let config = GitHostConfig(host: "git.example.com", org: "acme")
        store.upsert(config)

        let editor = editor(config)
        editor.config.org = "renamed"
        XCTAssertTrue(editor.save())

        XCTAssertEqual(store.hosts.count, 1)
        XCTAssertEqual(store.hosts.first?.org, "renamed")
    }

    // MARK: - Remove

    func testRemoveTakesTwoTaps() {
        let config = GitHostConfig(host: "git.example.com", org: "acme")
        store.upsert(config)
        let editor = editor(config)

        XCTAssertFalse(editor.removeTapped(), "the first tap only arms the confirm")
        XCTAssertTrue(editor.confirmingRemove)
        XCTAssertEqual(store.hosts.count, 1)

        XCTAssertTrue(editor.removeTapped())
        XCTAssertTrue(store.hosts.isEmpty)
        XCTAssertEqual(commits, [nil])
    }

    func testCancelRemoveDisarmsTheConfirm() {
        let config = GitHostConfig(host: "git.example.com", org: "acme")
        store.upsert(config)
        let editor = editor(config)

        _ = editor.removeTapped()
        editor.cancelRemove()
        XCTAssertFalse(editor.confirmingRemove)

        XCTAssertFalse(editor.removeTapped(), "after disarming, the next tap arms again")
        XCTAssertEqual(store.hosts.count, 1)
    }
}
