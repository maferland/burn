import Foundation

enum PRProvider: String, Hashable {
    case github
    case forgejo
}

struct PullRequest: Decodable, Identifiable, Hashable {
    let url: String
    let title: String
    let createdAt: Date
    let repository: Repository
    let state: String      // "OPEN", "CLOSED", "MERGED"
    let closedAt: Date?    // set when merged or closed

    // Not on the wire: filled in by whichever service produced the PR.
    var provider: PRProvider = .github
    // Host shown next to the repo for self-hosted PRs, so rows stay distinguishable.
    var hostLabel: String?

    var id: String { url }
    var isMerged: Bool { state.lowercased() == "merged" }
    // GitHub returns "0001-01-01T00:00:00Z" (zero date) for closedAt on open PRs instead of null.
    var mergedAt: Date? { isMerged ? closedAt : nil }

    // Declared so the synthesized decoder skips provider/hostLabel and keeps decoding gh output as-is.
    enum CodingKeys: String, CodingKey {
        case url, title, createdAt, repository, state, closedAt
    }

    struct Repository: Decodable, Hashable {
        let nameWithOwner: String

        var owner: String { nameWithOwner.split(separator: "/").first.map(String.init) ?? "" }
    }
}

struct PRFetchResult {
    let prs: [PullRequest]
    // True when a service hit its result cap, meaning older PRs may have been dropped.
    let truncated: Bool

    static let empty = PRFetchResult(prs: [], truncated: false)
}
