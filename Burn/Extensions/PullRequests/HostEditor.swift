import Foundation

/// The host form's behaviour, kept out of the view so the interaction can be tested without a UI runner.
@Observable
@MainActor
final class HostEditor {
    enum TokenState {
        case cliManaged
        case saved
        case entering
    }

    var config: GitHostConfig
    var tokenInput = ""
    var hostError: String?
    var confirmingRemove = false

    let isNew: Bool

    init(
        store: GitHostStore,
        config: GitHostConfig,
        isNew: Bool,
        onCommit: @escaping (UUID?) -> Void = { _ in }
    ) {
        self.store = store
        self.config = config
        self.isNew = isNew
        self.onCommit = onCommit
        self.replacingToken = isNew
    }

    private let store: GitHostStore
    private let onCommit: (UUID?) -> Void
    private var replacingToken: Bool

    var tokenState: TokenState {
        if config.usesGitHubCLI { return .cliManaged }
        if !replacingToken, store.hasToken(config) { return .saved }
        return .entering
    }

    var canSave: Bool { config.isSaveable && hostError == nil }

    /// github.com switches the row to CLI auth the moment it is typed, so the token field disappears.
    func hostDidChange() {
        config.kind = GitHostConfig.isGitHubDotCom(config.host) ? .github : .selfHosted
        hostError = nil
    }

    func validateHost() {
        let trimmed = config.host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            hostError = nil
            return
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let parsed = URL(string: withScheme)?.host
        hostError = (parsed?.contains(".") ?? false) ? nil : "That doesn't look like a host name."
    }

    func beginReplacingToken() {
        replacingToken = true
    }

    @discardableResult
    func save() -> Bool {
        validateHost()
        guard canSave else { return false }
        config.host = config.host.trimmingCharacters(in: .whitespaces)
        config.org = config.org.trimmingCharacters(in: .whitespaces)
        store.upsert(config)
        if !config.usesGitHubCLI, !tokenInput.isEmpty {
            store.setToken(tokenInput, for: config)
            replacingToken = false
        }
        tokenInput = ""
        onCommit(config.id)
        return true
    }

    /// First tap arms, second removes — cheaper than a system alert over a popover this size.
    @discardableResult
    func removeTapped() -> Bool {
        guard confirmingRemove else {
            confirmingRemove = true
            return false
        }
        store.remove(config.id)
        onCommit(nil)
        return true
    }

    func cancelRemove() {
        confirmingRemove = false
    }
}
