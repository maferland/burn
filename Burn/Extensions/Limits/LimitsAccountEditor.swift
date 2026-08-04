import Foundation

/// The account form's behaviour, kept out of the view so the interaction can be tested directly.
@Observable
@MainActor
final class LimitsAccountEditor {
    var provider: Provider
    var label: String
    /// Editing the path clears the error: the caption should not accuse a path they are still typing.
    var homePath: String {
        didSet { pathError = nil }
    }
    var pathError: String?
    var confirmingRemove = false

    let existing: LimitsAccount?

    init(
        store: LimitsAccountStore,
        account: LimitsAccount?,
        onCommit: @escaping () -> Void = {}
    ) {
        self.store = store
        self.existing = account
        self.provider = account?.provider ?? .claude
        self.label = account?.label ?? ""
        self.homePath = account?.homePath ?? ""
        self.onCommit = onCommit
    }

    private let store: LimitsAccountStore
    private let onCommit: () -> Void

    var isNew: Bool { existing == nil }

    var canSave: Bool {
        !homePath.trimmingCharacters(in: .whitespaces).isEmpty && pathError == nil
    }

    /// A path that does not exist yet is the most common reason a new account reports nothing.
    func validatePath() {
        let trimmed = homePath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            pathError = nil
            return
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
        pathError = exists && isDirectory.boolValue ? nil : "No folder at that path."
    }

    @discardableResult
    func save() -> Bool {
        validatePath()
        guard canSave else { return false }
        if let existing {
            store.remove(id: existing.id)
        }
        store.add(
            provider: provider,
            label: label.trimmingCharacters(in: .whitespaces),
            homePath: homePath.trimmingCharacters(in: .whitespaces)
        )
        onCommit()
        return true
    }

    @discardableResult
    func removeTapped() -> Bool {
        guard let existing else { return false }
        guard confirmingRemove else {
            confirmingRemove = true
            return false
        }
        store.remove(id: existing.id)
        onCommit()
        return true
    }

    func cancelRemove() {
        confirmingRemove = false
    }
}
