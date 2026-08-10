import SwiftUI

/// Every surface that talks about "where the spend came from" keys off this, so a new provider is
/// one case plus its accent rather than a switch in each tab.
enum Provider: String, Codable, CaseIterable, Hashable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }

    /// Claude keeps Ember's amber; each additional provider gets one accent, capped at three.
    var accent: Color {
        switch self {
        case .claude: return Ember.accent
        case .codex:  return Color(red: 0.478, green: 0.635, blue: 1.0)
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

    /// Where the numbers come from, said once so every provider row reads the same way.
    var sourceDescription: String {
        switch self {
        case .claude: return "Local usage logs"
        case .codex:  return "OpenAI CLI logs"
        }
    }

    var homeExample: String {
        switch self {
        case .claude: return "~/.claude-personal"
        case .codex:  return "~/.codex-work"
        }
    }
}
