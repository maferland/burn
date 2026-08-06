import XCTest
@testable import Burn

@MainActor
final class ProviderStoreTests: XCTestCase {
    private func makeStore(
        signedIn: @escaping @Sendable (Provider, URL) -> Bool = { _, _ in true },
        suite: String = #function
    ) -> ProviderStore {
        let defaults = UserDefaults(suiteName: "burn.tests.\(suite)")!
        defaults.removePersistentDomain(forName: "burn.tests.\(suite)")
        return ProviderStore(defaults: defaults, signedIn: signedIn)
    }

    /// Upgrading shouldn't silently disconnect a provider that was already being read.
    func testUntouchedProvidersInheritWhatDetectionSays() {
        let all = makeStore(signedIn: { _, _ in true }, suite: "inherit-yes")
        XCTAssertEqual(all.connected, [.claude, .codex])

        let none = makeStore(signedIn: { _, _ in false }, suite: "inherit-no")
        XCTAssertEqual(none.connected, [])
        XCTAssertEqual(none.connectable, [.claude, .codex])
    }

    func testConnectingIsExplicitOnceTouched() {
        let store = makeStore(signedIn: { provider, _ in provider == .claude })
        XCTAssertEqual(store.connected, [.claude])

        store.connect(.codex)
        XCTAssertEqual(store.connected, [.claude, .codex], "a signed-out CLI can still be connected")

        store.disconnect(.claude)
        XCTAssertEqual(store.connected, [.codex])
    }

    func testChoicesSurviveARelaunch() {
        let suite = "burn.tests.persistence"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = ProviderStore(defaults: defaults, signedIn: { _, _ in true })
        first.disconnect(.codex)
        first.setHome(.claude, path: "~/.claude-work")
        first.setIncludedInTotal(.claude, false)

        let second = ProviderStore(defaults: defaults, signedIn: { _, _ in true })
        XCTAssertEqual(second.connected, [.claude])
        XCTAssertEqual(second.homePath(for: .claude), "~/.claude-work")
        XCTAssertFalse(second.includesInTotal(.claude))
    }

    func testHomeFallsBackToTheDefaultAndExpandsTildes() {
        let store = makeStore()
        XCTAssertEqual(store.home(for: .codex), Provider.codex.defaultHome)

        store.setHome(.codex, path: "  ~/.codex-work  ")
        XCTAssertEqual(store.home(for: .codex).path, NSString(string: "~/.codex-work").expandingTildeInPath)

        store.setHome(.codex, path: "   ")
        XCTAssertEqual(store.home(for: .codex), Provider.codex.defaultHome, "blank means default, not a folder named nothing")
    }

    /// Opting out of the total is not the same as disconnecting: the tab still shows it on its own.
    func testExcludedProviderStaysConnectedButLeavesTheTotal() {
        let store = makeStore()
        store.setIncludedInTotal(.codex, false)

        XCTAssertEqual(store.connected, [.claude, .codex])
        XCTAssertEqual(store.countedInTotal, [.claude])
    }

    func testHealthSeparatesNotConnectedFromCannotRead() {
        let store = makeStore(signedIn: { provider, _ in provider == .claude })
        XCTAssertEqual(store.health(.claude), .ok)
        XCTAssertEqual(store.health(.codex), .disconnected)

        store.connect(.codex)
        XCTAssertEqual(store.health(.codex), .unreachable, "connected, but nothing signed in where we look")
        XCTAssertEqual(store.health(.codex).caption, "not signed in")
    }
}
