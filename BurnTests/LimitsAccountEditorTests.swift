import XCTest
@testable import Burn

/// Drives the account form the way a click-through would: type a path, blur, Save, Remove twice.
@MainActor
final class LimitsAccountEditorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: LimitsAccountStore!
    private var home: URL!
    private var commits = 0

    override func setUpWithError() throws {
        suiteName = "burn.tests.limits-editor-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = LimitsAccountStore(defaults: defaults, detect: { [] })
        commits = 0
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("limits-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func editor(_ account: LimitsAccount? = nil) -> LimitsAccountEditor {
        LimitsAccountEditor(store: store, account: account) { [weak self] in
            self?.commits += 1
        }
    }

    func testAddAccountNeedsAPathBeforeItCanSave() {
        let editor = editor()
        XCTAssertFalse(editor.canSave)
        XCTAssertFalse(editor.save())
        XCTAssertTrue(store.accounts.isEmpty)

        editor.homePath = home.path
        XCTAssertTrue(editor.canSave)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(commits, 1)
    }

    /// The commonest reason a new account reports nothing is a path that is not there.
    func testBlurringAMissingPathBlocksSave() {
        let editor = editor()
        editor.homePath = home.appendingPathComponent("nope").path
        editor.validatePath()

        XCTAssertEqual(editor.pathError, "No folder at that path.")
        XCTAssertFalse(editor.canSave)
        XCTAssertFalse(editor.save())
        XCTAssertTrue(store.accounts.isEmpty)

        editor.homePath = home.path
        XCTAssertNil(editor.pathError, "typing again clears the error")
        XCTAssertTrue(editor.save())
    }

    func testSaveTrimsAndKeepsTheProvider() {
        let editor = editor()
        editor.provider = .codex
        editor.homePath = " \(home.path) "
        editor.label = "  work  "

        XCTAssertTrue(editor.save())
        XCTAssertEqual(store.accounts.first?.provider, .codex)
        XCTAssertEqual(store.accounts.first?.label, "work")
        XCTAssertEqual(store.accounts.first?.homePath, home.path)
    }

    func testUnnamedAccountFallsBackToTheFolderName() {
        let editor = editor()
        editor.homePath = home.path
        XCTAssertTrue(editor.save())

        XCTAssertEqual(store.accounts.first?.label, home.lastPathComponent)
    }

    func testEditingAnAccountReplacesItRatherThanDuplicating() throws {
        let first = editor()
        first.homePath = home.path
        first.label = "personal"
        XCTAssertTrue(first.save())
        let saved = try XCTUnwrap(store.accounts.first)

        let second = editor(saved)
        second.label = "renamed"
        XCTAssertTrue(second.save())

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts.first?.label, "renamed")
    }

    func testRemoveTakesTwoTaps() throws {
        let creator = editor()
        creator.homePath = home.path
        XCTAssertTrue(creator.save())
        let saved = try XCTUnwrap(store.accounts.first)

        let editor = editor(saved)
        XCTAssertFalse(editor.removeTapped())
        XCTAssertTrue(editor.confirmingRemove)
        XCTAssertEqual(store.accounts.count, 1)

        XCTAssertTrue(editor.removeTapped())
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testRemoveDoesNothingOnANewAccount() {
        let editor = editor()
        XCTAssertFalse(editor.removeTapped())
        XCTAssertFalse(editor.confirmingRemove)
    }
}
