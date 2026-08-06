import Foundation

/// What the user has decided about one provider, as opposed to what we detected about it.
struct ProviderSettings: Codable, Hashable {
    var isConnected: Bool
    /// nil means the provider's default home; set when a CLI lives somewhere non-standard.
    var homeOverride: String?
    var includeInTotal: Bool

    init(isConnected: Bool, homeOverride: String? = nil, includeInTotal: Bool = true) {
        self.isConnected = isConnected
        self.homeOverride = homeOverride
        self.includeInTotal = includeInTotal
    }
}

/// The one place a provider is connected, pointed somewhere, or dropped from the total.
/// Detection still runs, but only to answer "would this work if you connected it".
@Observable
@MainActor
final class ProviderStore {
    static let settingsKey = "providers.settings"

    private(set) var settings: [String: ProviderSettings]

    private let defaults: UserDefaults
    private let signedIn: @Sendable (Provider, URL) -> Bool

    init(
        defaults: UserDefaults = .standard,
        signedIn: (@Sendable (Provider, URL) -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.signedIn = signedIn ?? { LimitsAccountStore.isSignedIn(provider: $0, home: $1) }
        let stored = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode([String: ProviderSettings].self, from: $0) }
        self.settings = stored ?? [:]
    }

    // MARK: - Reading

    /// Untouched providers inherit what detection says, so an upgrade doesn't disconnect anyone.
    func isConnected(_ provider: Provider) -> Bool {
        if let stored = settings[provider.rawValue] { return stored.isConnected }
        return isDetectable(provider)
    }

    /// True when the CLI is signed in at the configured home, whatever the user has chosen.
    func isDetectable(_ provider: Provider) -> Bool {
        signedIn(provider, home(for: provider))
    }

    func home(for provider: Provider) -> URL {
        guard let path = settings[provider.rawValue]?.homeOverride, !path.isEmpty else {
            return provider.defaultHome
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    func homePath(for provider: Provider) -> String {
        settings[provider.rawValue]?.homeOverride ?? "~/\(provider.defaultHome.lastPathComponent)"
    }

    func includesInTotal(_ provider: Provider) -> Bool {
        settings[provider.rawValue]?.includeInTotal ?? true
    }

    var connected: [Provider] { Provider.allCases.filter(isConnected) }

    /// What "All providers" actually sums: connected, minus anything opted out of the total.
    var countedInTotal: [Provider] {
        connected.filter(includesInTotal)
    }

    var connectable: [Provider] { Provider.allCases.filter { !isConnected($0) } }

    /// Green once it reads, amber when it is connected but the CLI isn't signed in where we look.
    func health(_ provider: Provider) -> ProviderHealth {
        guard isConnected(provider) else { return .disconnected }
        return isDetectable(provider) ? .ok : .unreachable
    }

    // MARK: - Writing

    func connect(_ provider: Provider) {
        update(provider) { $0.isConnected = true }
    }

    func disconnect(_ provider: Provider) {
        update(provider) { $0.isConnected = false }
    }

    func setHome(_ provider: Provider, path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        update(provider) { $0.homeOverride = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    func setIncludedInTotal(_ provider: Provider, _ included: Bool) {
        update(provider) { $0.includeInTotal = included }
    }

    private func update(_ provider: Provider, _ change: (inout ProviderSettings) -> Void) {
        var current = settings[provider.rawValue]
            ?? ProviderSettings(isConnected: isDetectable(provider))
        change(&current)
        settings[provider.rawValue] = current
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }
}

enum ProviderHealth: Hashable {
    case ok
    case unreachable
    case disconnected

    var caption: String? {
        switch self {
        case .ok:           return nil
        case .unreachable:  return "not signed in"
        case .disconnected: return "Not connected"
        }
    }
}
