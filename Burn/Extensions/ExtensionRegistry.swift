import SwiftUI

@Observable
@MainActor
final class ExtensionRegistry {
    static let enabledIdsKey = "extensions.enabledIds"
    static let orderedIdsKey = "extensions.orderedIds"
    static let seenIdsKey = "extensions.seenIds"

    private(set) var extensions: [any BurnExtension] = []

    var enabledIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIds), forKey: Self.enabledIdsKey) }
    }

    var orderedIds: [String] {
        didSet { UserDefaults.standard.set(orderedIds, forKey: Self.orderedIdsKey) }
    }

    var activeTabId: String?

    private var seenIds: Set<String>

    init() {
        let storedEnabled = UserDefaults.standard.array(forKey: Self.enabledIdsKey) as? [String]
        let storedOrder = UserDefaults.standard.array(forKey: Self.orderedIdsKey) as? [String]
        let storedSeen = UserDefaults.standard.array(forKey: Self.seenIdsKey) as? [String]
        self.enabledIds = storedEnabled.map(Set.init) ?? []
        self.orderedIds = storedOrder ?? []
        self.seenIds = storedSeen.map(Set.init) ?? []
    }

    func register(_ ext: any BurnExtension) {
        guard !extensions.contains(where: { $0.id == ext.id }) else { return }
        extensions.append(ext)

        if !orderedIds.contains(ext.id) {
            orderedIds.append(ext.id)
        }

        if !seenIds.contains(ext.id) {
            seenIds.insert(ext.id)
            UserDefaults.standard.set(Array(seenIds), forKey: Self.seenIdsKey)
            enabledIds.insert(ext.id)
        }

        if activeTabId == nil, enabledIds.contains(ext.id) {
            activeTabId = ext.id
        }
    }

    var orderedExtensions: [any BurnExtension] {
        orderedIds.compactMap { id in extensions.first(where: { $0.id == id }) }
    }

    var enabledExtensions: [any BurnExtension] {
        orderedExtensions.filter { enabledIds.contains($0.id) }
    }

    func isEnabled(_ id: String) -> Bool { enabledIds.contains(id) }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled {
            enabledIds.insert(id)
            if activeTabId == nil {
                activeTabId = id
            }
        } else {
            enabledIds.remove(id)
            if activeTabId == id {
                activeTabId = enabledExtensions.first?.id
            }
        }
    }

    func refreshAll() {
        for ext in enabledExtensions { ext.refresh() }
    }
}
