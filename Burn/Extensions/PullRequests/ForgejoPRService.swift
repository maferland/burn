import Foundation

struct ForgejoConfig: Equatable {
    let host: URL
    let token: String

    /// Accepts "git.example.com" or "https://git.example.com".
    init?(host: String, token: String) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !token.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        self.host = url
        self.token = token
    }

    var label: String { host.host ?? host.absoluteString }
}

enum ForgejoPRError: LocalizedError {
    case unauthorized(host: String)
    case forbidden(host: String, detail: String)
    case accessGateway(host: String, status: Int)
    case http(host: String, status: Int, body: String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let host):
            return "\(host) rejected the token. Regenerate it with the read:issue scope."
        case .forbidden(let host, let detail):
            return "\(host) denied the token: \(detail)"
        case .accessGateway(let host, let status):
            return "\(host) answered \(status) from an access gateway, not Forgejo. Check your VPN or SSO session."
        case .http(let host, let status, let body):
            return "\(host) request failed (\(status)): \(body)"
        case .decodeFailed(let detail):
            return "Failed to parse Forgejo response: \(detail)"
        }
    }
}

enum ForgejoPRService {
    /// Gitea/Forgejo clamps page size to MAX_RESPONSE_ITEMS (50 by default).
    static let pageSize = 50
    static let maxPages = 20

    static func fetchAll(config: ForgejoConfig, since: Date, owners: [String] = []) async throws -> PRFetchResult {
        async let openPages = fetchPages(config: config, state: "open", since: nil)
        async let closedPages = fetchPages(config: config, state: "closed", since: since)
        let (open, closed) = try await (openPages, closedPages)

        let prs = pullRequests(from: open.issues + closed.issues, hostLabel: config.label, owners: owners)
        return PRFetchResult(prs: prs, truncated: open.truncated || closed.truncated)
    }

    // MARK: - Mapping

    /// Drops closed-but-unmerged PRs so the list matches the GitHub side (open + merged only).
    static func pullRequests(from issues: [ForgejoIssue], hostLabel: String, owners: [String]) -> [PullRequest] {
        issues.compactMap { pullRequest(from: $0, hostLabel: hostLabel) }
            .filter { matches(owners: owners, pr: $0) }
    }

    static func pullRequest(from issue: ForgejoIssue, hostLabel: String) -> PullRequest? {
        guard let pull = issue.pullRequest else { return nil }
        let isOpen = issue.state.lowercased() == "open"
        guard isOpen || pull.merged else { return nil }

        return PullRequest(
            url: pull.htmlUrl ?? issue.htmlUrl,
            title: issue.title,
            createdAt: issue.createdAt,
            repository: .init(nameWithOwner: issue.repository.fullName),
            state: pull.merged ? "MERGED" : issue.state.uppercased(),
            closedAt: pull.mergedAt,
            provider: .forgejo,
            hostLabel: hostLabel
        )
    }

    private static func matches(owners: [String], pr: PullRequest) -> Bool {
        guard !owners.isEmpty else { return true }
        return owners.contains { $0.caseInsensitiveCompare(pr.repository.owner) == .orderedSame }
    }

    // MARK: - Requests

    /// `created=true` is the only author filter the API honours; `created_by` is silently ignored.
    static func searchURL(config: ForgejoConfig, state: String, since: Date?, page: Int) -> URL {
        var components = URLComponents(url: config.host, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/repos/issues/search"
        var items = [
            URLQueryItem(name: "type", value: "pulls"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "created", value: "true"),
            URLQueryItem(name: "limit", value: "\(pageSize)"),
            URLQueryItem(name: "page", value: "\(page)"),
        ]
        if let since {
            items.append(URLQueryItem(name: "since", value: rfc3339.string(from: since)))
        }
        components.queryItems = items
        return components.url!
    }

    private struct Page {
        let issues: [ForgejoIssue]
        let truncated: Bool
    }

    private static func fetchPages(config: ForgejoConfig, state: String, since: Date?) async throws -> Page {
        var issues: [ForgejoIssue] = []
        for page in 1...maxPages {
            let url = searchURL(config: config, state: state, since: since, page: page)
            let batch = try await fetch(url: url, token: config.token, host: config.label)
            issues += batch
            if batch.count < pageSize { return Page(issues: issues, truncated: false) }
        }
        return Page(issues: issues, truncated: true)
    }

    private static func fetch(url: URL, token: String, host: String) async throws -> [ForgejoIssue] {
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return try decode(data) }
        throw error(status: status, data: data, host: host)
    }

    /// An HTML body means something in front of Forgejo answered (Cloudflare Access, an SSO
    /// portal), so the token isn't the problem and shouldn't be blamed for it.
    static func error(status: Int, data: Data, host: String) -> ForgejoPRError {
        guard looksLikeJSON(data) else {
            return .accessGateway(host: host, status: status)
        }
        let detail = clip(apiMessage(data) ?? flatten(data))
        switch status {
        case 401:
            return .unauthorized(host: host)
        case 403:
            return .forbidden(host: host, detail: detail)
        default:
            return .http(host: host, status: status, body: detail)
        }
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = data.first(where: { !" \t\r\n".utf8.contains($0) }) else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    private static func apiMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String,
              !message.isEmpty else { return nil }
        return message
    }

    private static func flatten(_ data: Data) -> String {
        (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func clip(_ text: String, limit: Int = 120) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func decode(_ data: Data) throws -> [ForgejoIssue] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ForgejoIssue].self, from: data)
        } catch {
            throw ForgejoPRError.decodeFailed(String(describing: error))
        }
    }

    static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

struct ForgejoIssue: Decodable {
    let title: String
    let htmlUrl: String
    let createdAt: Date
    let state: String
    let repository: Repository
    let pullRequest: PullRequestRef?

    struct Repository: Decodable {
        let fullName: String
    }

    struct PullRequestRef: Decodable {
        let merged: Bool
        let mergedAt: Date?
        let htmlUrl: String?
    }
}
