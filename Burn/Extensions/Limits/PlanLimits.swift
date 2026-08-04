import Foundation

enum LimitsProvider: String, Codable, CaseIterable, Hashable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }

    /// The config home a fresh install writes to, and the fallback when an account has no explicit one.
    var defaultHome: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude")
        case .codex:  return home.appendingPathComponent(".codex")
        }
    }

    /// The env var a user sets to point a CLI at a second login.
    var homeEnvironmentVariable: String {
        switch self {
        case .claude: return "CLAUDE_CONFIG_DIR"
        case .codex:  return "CODEX_HOME"
        }
    }

    var homeExample: String {
        switch self {
        case .claude: return "~/.claude-personal"
        case .codex:  return "~/.codex-work"
        }
    }
}

/// One login. Two accounts of the same provider differ by config home, which is how the CLIs keep
/// separate credentials — so the home path is what makes the id stable across renames.
struct LimitsAccount: Codable, Hashable, Identifiable {
    let provider: LimitsProvider
    var label: String
    /// nil means the provider's default home.
    var homePath: String?
    var isAutoDetected: Bool

    var id: String { "\(provider.rawValue):\(homePath ?? "default")" }

    var home: URL {
        guard let homePath, !homePath.isEmpty else { return provider.defaultHome }
        return URL(fileURLWithPath: (homePath as NSString).expandingTildeInPath)
    }

    var isDefaultHome: Bool { homePath == nil || homePath?.isEmpty == true }
}

enum LimitWindowKind: String, Codable, Hashable {
    case fiveHour
    case week
    case weekOpus
    case weekSonnet

    var label: String {
        switch self {
        case .fiveHour:   return "5-hour"
        case .week:       return "Weekly"
        case .weekOpus:   return "Weekly Opus"
        case .weekSonnet: return "Weekly Sonnet"
        }
    }

    /// Reads inside a sentence: "30% of your week left".
    var phrase: String {
        switch self {
        case .fiveHour:   return "5-hour window"
        case .week:       return "week"
        case .weekOpus:   return "Opus week"
        case .weekSonnet: return "Sonnet week"
        }
    }
}

struct LimitWindow: Codable, Hashable, Identifiable {
    let kind: LimitWindowKind
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { kind.rawValue }

    /// A window past its reset is fully available again, even if the API still reports the old number.
    var hasReset: Bool {
        guard let resetsAt else { return false }
        return resetsAt <= Date()
    }

    var effectiveUsedPercent: Double { hasReset ? 0 : min(100, max(0, usedPercent)) }
    var remainingPercent: Double { 100 - effectiveUsedPercent }
}

/// Enterprise and credit-backed seats have no rolling windows at all — they report money instead.
struct SpendSnapshot: Codable, Hashable {
    let usedDollars: Double
    let limitDollars: Double?

    var fraction: Double? {
        guard let limitDollars, limitDollars > 0 else { return nil }
        return min(1, usedDollars / limitDollars)
    }
}

enum LimitsSource: String, Codable, Hashable {
    case api
    case rolloutLogs
}

struct LimitsFailure: Codable, Hashable, Error {
    enum Kind: String, Codable {
        case noCredentials
        case keychainRefused
        case expiredSession
        case rateLimited
        case unauthorized
        case network
        case malformedResponse
    }

    let kind: Kind
    /// Path, status code, or error text — whatever tells the user what to fix.
    let detail: String?

    var message: String {
        switch kind {
        case .noCredentials:
            return detail.map { "No credentials found at \($0)" } ?? "Not signed in"
        case .keychainRefused:
            return "Keychain refused the credential read\(detail.map { " (\($0))" } ?? "")"
        case .expiredSession:
            return "Session expired — sign in again to update"
        case .rateLimited:
            return "Usage API rate-limited this refresh"
        case .unauthorized:
            return "Credentials rejected — sign in again"
        case .network:
            return detail.map { "Couldn't reach the usage API: \($0)" } ?? "Couldn't reach the usage API"
        case .malformedResponse:
            return "Usage API returned something unexpected"
        }
    }
}

struct AccountSnapshot: Codable, Hashable, Identifiable {
    let account: LimitsAccount
    var planLabel: String?
    var windows: [LimitWindow]
    var spend: SpendSnapshot?
    var capturedAt: Date?
    var source: LimitsSource
    var failure: LimitsFailure?

    var id: String { account.id }

    var hasData: Bool { !windows.isEmpty || spend != nil }

    func window(_ kind: LimitWindowKind) -> LimitWindow? {
        windows.first { $0.kind == kind }
    }

    /// The window closest to stopping work — the only number worth putting in the menu bar.
    var tightestWindow: LimitWindow? {
        windows.max { $0.effectiveUsedPercent < $1.effectiveUsedPercent }
    }

    static func failed(_ account: LimitsAccount, _ failure: LimitsFailure, source: LimitsSource = .api) -> AccountSnapshot {
        AccountSnapshot(
            account: account, planLabel: nil, windows: [], spend: nil,
            capturedAt: nil, source: source, failure: failure
        )
    }
}

struct LimitsResponse: Codable, Hashable {
    var accounts: [AccountSnapshot]

    static let empty = LimitsResponse(accounts: [])

    var isEmpty: Bool { accounts.isEmpty }

    /// Across every account, the window with the least headroom left.
    var tightest: (snapshot: AccountSnapshot, window: LimitWindow)? {
        accounts
            .compactMap { snapshot in snapshot.tightestWindow.map { (snapshot, $0) } }
            .max { $0.1.effectiveUsedPercent < $1.1.effectiveUsedPercent }
    }
}
