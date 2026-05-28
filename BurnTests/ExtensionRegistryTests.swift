import XCTest
import SwiftUI
@testable import Burn

@MainActor
final class ExtensionRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for key in [
            ExtensionRegistry.enabledIdsKey,
            ExtensionRegistry.orderedIdsKey,
            ExtensionRegistry.seenIdsKey,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testRegisterAddsExtensionAndEnablesItByDefault() {
        let registry = ExtensionRegistry()
        registry.register(StubExtension(id: "alpha"))

        XCTAssertEqual(registry.extensions.count, 1)
        XCTAssertTrue(registry.isEnabled("alpha"))
        XCTAssertEqual(registry.activeTabId, "alpha")
    }

    func testRegisterIsIdempotent() {
        let registry = ExtensionRegistry()
        let ext = StubExtension(id: "alpha")
        registry.register(ext)
        registry.register(ext)
        XCTAssertEqual(registry.extensions.count, 1)
    }

    func testDisableHidesFromEnabledExtensions() {
        let registry = ExtensionRegistry()
        registry.register(StubExtension(id: "alpha"))
        registry.register(StubExtension(id: "beta"))

        registry.setEnabled("alpha", false)

        XCTAssertEqual(registry.enabledExtensions.map(\.id), ["beta"])
        XCTAssertEqual(registry.orderedExtensions.map(\.id), ["alpha", "beta"])
    }

    func testDisablingActiveTabFallsBackToFirstEnabled() {
        let registry = ExtensionRegistry()
        registry.register(StubExtension(id: "alpha"))
        registry.register(StubExtension(id: "beta"))
        registry.activeTabId = "alpha"

        registry.setEnabled("alpha", false)

        XCTAssertEqual(registry.activeTabId, "beta")
    }

    func testDisablingLastEnabledLeavesNilActiveTab() {
        let registry = ExtensionRegistry()
        registry.register(StubExtension(id: "alpha"))
        registry.setEnabled("alpha", false)
        XCTAssertNil(registry.activeTabId)
    }

    func testPersistedDisableSurvivesNewRegistry() {
        let first = ExtensionRegistry()
        first.register(StubExtension(id: "alpha"))
        first.setEnabled("alpha", false)

        let second = ExtensionRegistry()
        second.register(StubExtension(id: "alpha"))

        XCTAssertFalse(second.isEnabled("alpha"))
    }

    func testNewExtensionDefaultsEnabledEvenWhenOthersWereDisabled() {
        let first = ExtensionRegistry()
        first.register(StubExtension(id: "alpha"))
        first.setEnabled("alpha", false)

        let second = ExtensionRegistry()
        second.register(StubExtension(id: "alpha"))
        second.register(StubExtension(id: "beta"))

        XCTAssertFalse(second.isEnabled("alpha"))
        XCTAssertTrue(second.isEnabled("beta"))
    }

    func testRefreshAllCallsEnabledOnly() {
        let registry = ExtensionRegistry()
        let alpha = StubExtension(id: "alpha")
        let beta = StubExtension(id: "beta")
        registry.register(alpha)
        registry.register(beta)
        registry.setEnabled("alpha", false)

        registry.refreshAll()

        XCTAssertEqual(alpha.refreshCount, 0)
        XCTAssertEqual(beta.refreshCount, 1)
    }
}

@MainActor
private final class StubExtension: BurnExtension {
    let id: String
    let displayName: String
    var refreshCount = 0

    init(id: String) {
        self.id = id
        self.displayName = id.capitalized
    }

    func refresh() { refreshCount += 1 }

    func menuBarSegment() -> AnyView? { AnyView(Text(id)) }
    func popoverTab() -> AnyView { AnyView(Text(id)) }
}
