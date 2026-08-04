import Foundation

/// One connected forge. github.com rides on the `gh` CLI, everything else on a per-host token.
struct GitHostConfig: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case github
        case selfHosted
    }

    let id: UUID
    var host: String
    var org: String
    var kind: Kind
    /// Migrated rows inherit the pre-multi-host token, but only when someone actually asks for it.
    var adoptsLegacyToken = false

    init(id: UUID = UUID(), host: String, org: String, kind: Kind? = nil, adoptsLegacyToken: Bool = false) {
        self.id = id
        self.host = host
        self.org = org
        self.kind = kind ?? (Self.isGitHubDotCom(host) ? .github : .selfHosted)
        self.adoptsLegacyToken = adoptsLegacyToken
    }

    static func isGitHubDotCom(_ host: String) -> Bool {
        let stripped = host.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return stripped == "github.com" || stripped.hasPrefix("github.com/")
    }

    var usesGitHubCLI: Bool { kind == .github }

    var tokenService: String { "burn.host.token.\(id.uuidString)" }

    var label: String {
        host.trimmingCharacters(in: .whitespaces).isEmpty ? "New host" : host
    }

    /// GitHub with no org means every org the CLI can see, which is the old default.
    var owners: [String] {
        let trimmed = org.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    var isSaveable: Bool {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return usesGitHubCLI || !org.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

@Observable
@MainActor
final class GitHostStore {
    static let hostsKey = "github-pr.hosts"

    private(set) var hosts: [GitHostConfig]

    init(
        defaults: UserDefaults = .standard,
        legacyTokenService: String = PullRequestExtension.forgejoTokenService,
        readToken: @escaping (String) -> KeychainStore.ReadResult = { KeychainStore.read(service: $0) }
    ) {
        self.defaults = defaults
        self.readToken = readToken
        self.legacyTokenService = legacyTokenService
        if let data = defaults.data(forKey: Self.hostsKey),
           let decoded = try? JSONDecoder().decode([GitHostConfig].self, from: data) {
            self.hosts = decoded
        } else {
            self.hosts = Self.migrateLegacy(defaults: defaults)
            persist()
        }
    }

    private let defaults: UserDefaults
    private let readToken: (String) -> KeychainStore.ReadResult
    let legacyTokenService: String

    func clearLegacyAdoption(_ id: UUID) {
        guard let index = hosts.firstIndex(where: { $0.id == id }), hosts[index].adoptsLegacyToken else {
            return
        }
        hosts[index].adoptsLegacyToken = false
        persist()
    }

    func upsert(_ config: GitHostConfig) {
        if let index = hosts.firstIndex(where: { $0.id == config.id }) {
            hosts[index] = config
        } else {
            hosts.append(config)
        }
        persist()
    }

    func remove(_ id: UUID) {
        guard let config = hosts.first(where: { $0.id == id }) else { return }
        KeychainStore.delete(service: config.tokenService)
        hosts.removeAll { $0.id == id }
        persist()
    }

    func setToken(_ token: String, for config: GitHostConfig) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(service: config.tokenService)
        } else {
            KeychainStore.write(trimmed, service: config.tokenService)
        }
    }

    /// Reads never happen at launch: a keychain prompt on the init path freezes the whole app.
    func token(for config: GitHostConfig) -> KeychainStore.ReadResult {
        let own = readToken(config.tokenService)
        guard case .missing = own, config.adoptsLegacyToken else { return own }

        let legacy = readToken(legacyTokenService)
        if case .value(let token) = legacy {
            KeychainStore.write(token, service: config.tokenService)
        }
        if let index = hosts.firstIndex(where: { $0.id == config.id }) {
            hosts[index].adoptsLegacyToken = false
            persist()
        }
        return legacy
    }

    /// Side-effect free so views can call it while rendering; adoption happens on the refresh path.
    func hasToken(_ config: GitHostConfig) -> Bool {
        if case .value = readToken(config.tokenService) { return true }
        return config.adoptsLegacyToken
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(data, forKey: Self.hostsKey)
    }

    /// UserDefaults only. Legacy keys stay put so an older build still reads its own config, and the
    /// old token is adopted later by `token(for:)` rather than on the launch path.
    static func migrateLegacy(defaults: UserDefaults) -> [GitHostConfig] {
        let owners = defaults.array(forKey: PullRequestExtension.ownersKey) as? [String] ?? []
        let forgejoHost = (defaults.string(forKey: PullRequestExtension.forgejoHostKey) ?? "")
            .trimmingCharacters(in: .whitespaces)

        var migrated: [GitHostConfig] = owners.isEmpty
            ? [GitHostConfig(host: "github.com", org: "")]
            : owners.map { GitHostConfig(host: "github.com", org: $0) }

        guard !forgejoHost.isEmpty else { return migrated }

        let forgejoOrgs = owners.isEmpty ? [""] : owners
        migrated.append(contentsOf: forgejoOrgs.map {
            GitHostConfig(host: forgejoHost, org: $0, adoptsLegacyToken: true)
        })
        return migrated
    }
}
