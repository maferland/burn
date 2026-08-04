import Foundation

/// What a config home says about who is signed in there.
struct LimitsIdentity: Hashable {
    var email: String?
    var planLabel: String?
    var accountId: String?

    static let unknown = LimitsIdentity()
}

/// Accounts come from two places: the default login this machine already has, and extra config homes
/// the user points us at. Only labels and paths are persisted — never credentials.
@Observable
@MainActor
final class LimitsAccountStore {
    static let manualAccountsKey = "limits.accounts"

    private(set) var manualAccounts: [LimitsAccount]

    init(
        defaults: UserDefaults = .standard,
        detect: @escaping () -> [LimitsAccount] = { LimitsAccountStore.autoDetected() }
    ) {
        self.defaults = defaults
        self.detect = detect
        if let data = defaults.data(forKey: Self.manualAccountsKey),
           let decoded = try? JSONDecoder().decode([LimitsAccount].self, from: data) {
            self.manualAccounts = decoded
        } else {
            self.manualAccounts = []
        }
    }

    private let defaults: UserDefaults
    private let detect: () -> [LimitsAccount]

    /// Auto-detected defaults first, then the user's extra homes, deduped by id.
    var accounts: [LimitsAccount] {
        var seen = Set<String>()
        return (detect() + manualAccounts).filter { seen.insert($0.id).inserted }
    }

    func add(provider: Provider, label: String, homePath: String) {
        let trimmedPath = homePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        let home = URL(fileURLWithPath: (trimmedPath as NSString).expandingTildeInPath)
        let identity = Self.identity(provider: provider, home: home, isDefaultHome: false)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = LimitsAccount(
            provider: provider,
            label: trimmedLabel.isEmpty ? (identity.email ?? home.lastPathComponent) : trimmedLabel,
            homePath: trimmedPath,
            isAutoDetected: false
        )
        guard !accounts.contains(where: { $0.id == account.id }) else { return }
        manualAccounts.append(account)
        persist()
    }

    func remove(id: String) {
        manualAccounts.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(manualAccounts) else { return }
        defaults.set(data, forKey: Self.manualAccountsKey)
    }

    // MARK: - Detection

    /// A directory alone proves nothing: an unsigned-in CLI leaves one behind with only config in it.
    nonisolated static func autoDetected() -> [LimitsAccount] {
        Provider.allCases.compactMap { provider in
            let home = provider.defaultHome
            guard isSignedIn(provider: provider, home: home) else { return nil }
            let identity = identity(provider: provider, home: home, isDefaultHome: true)
            return LimitsAccount(
                provider: provider,
                label: identity.email ?? provider.displayName,
                homePath: nil,
                isAutoDetected: true
            )
        }
    }

    nonisolated static func isSignedIn(provider: Provider, home: URL) -> Bool {
        switch provider {
        case .claude:
            if FileManager.default.fileExists(atPath: home.appendingPathComponent(".credentials.json").path) {
                return true
            }
            // The Keychain holds the token, so the profile beside it is the only prompt-free proof.
            return identity(provider: .claude, home: home, isDefaultHome: true).email != nil
        case .codex:
            return CodexSessionReader.isConfigured(home: home)
        }
    }

    nonisolated static func identity(provider: Provider, home: URL, isDefaultHome: Bool) -> LimitsIdentity {
        switch provider {
        case .claude: return claudeIdentity(home: home, isDefaultHome: isDefaultHome)
        case .codex:  return codexIdentity(home: home)
        }
    }

    // MARK: - Claude

    /// `CLAUDE_CONFIG_DIR` keeps `.claude.json` inside the home; the default install keeps it beside `~/.claude`.
    nonisolated static func claudeConfigFile(home: URL, isDefaultHome: Bool) -> URL? {
        let candidates = isDefaultHome
            ? [home.deletingLastPathComponent().appendingPathComponent(".claude.json"),
               home.appendingPathComponent(".claude.json")]
            : [home.appendingPathComponent(".claude.json"),
               home.deletingLastPathComponent().appendingPathComponent(".claude.json")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated private static func claudeIdentity(home: URL, isDefaultHome: Bool) -> LimitsIdentity {
        guard let file = claudeConfigFile(home: home, isDefaultHome: isDefaultHome),
              let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return .unknown }

        return LimitsIdentity(
            email: account["emailAddress"] as? String,
            planLabel: (account["seatTier"] as? String).map(claudePlanLabel),
            accountId: account["accountUuid"] as? String
        )
    }

    /// Seat tiers arrive snake_cased: `max_20x`, `enterprise_usage_based`.
    nonisolated static func claudePlanLabel(_ seatTier: String) -> String {
        switch seatTier {
        case "pro":                     return "Pro"
        case "max_5x":                  return "Max 5×"
        case "max_20x":                 return "Max 20×"
        case "enterprise_usage_based":  return "Enterprise"
        default:
            return seatTier.split(separator: "_").map(\.capitalized).joined(separator: " ")
        }
    }

    // MARK: - Codex

    nonisolated static func codexAuthFile(home: URL) -> URL {
        home.appendingPathComponent("auth.json")
    }

    nonisolated private static func codexIdentity(home: URL) -> LimitsIdentity {
        guard let credentials = CodexLimitsClient.credentials(home: home) else { return .unknown }
        return LimitsIdentity(
            email: credentials.email,
            planLabel: nil,
            accountId: credentials.accountId
        )
    }
}
