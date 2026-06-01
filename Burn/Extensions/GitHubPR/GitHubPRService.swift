import Foundation

struct GitHubPR: Decodable, Identifiable, Hashable {
    let url: String
    let title: String
    let createdAt: Date
    let repository: Repository

    var id: String { url }

    struct Repository: Decodable, Hashable {
        let nameWithOwner: String
    }
}

enum GitHubPRError: LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated(stderr: String)
    case ghFailed(stderr: String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "gh CLI not found. Install via brew install gh."
        case .ghNotAuthenticated(let stderr):
            return "gh not authenticated. Run gh auth login.\n\(stderr)"
        case .ghFailed(let stderr):
            return "gh failed: \(stderr)"
        case .decodeFailed(let detail):
            return "Failed to parse gh output: \(detail)"
        }
    }
}

struct GitHubPRFetchResult {
    let prs: [GitHubPR]
    // True when gh returned exactly the request limit, meaning older PRs may have been dropped.
    let truncated: Bool
}

enum GitHubPRService {
    // GitHub's search API caps results at 1000; request the max so a busy month isn't silently clipped.
    static let fetchLimit = 1000

    // GitHub search's `--created=` filter is UTC-only. Query one day earlier than `since` and let the caller filter by local timezone.
    static func fetchPRsOpened(since: Date, owners: [String] = []) async throws -> GitHubPRFetchResult {
        let cal = Calendar.current
        let queryStartDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: since))!
        let queryStart = isoDayFormatter.string(from: queryStartDate)
        var args = [
            "search", "prs",
            "--author=@me",
            "--created=>=\(queryStart)",
            "--json", "url,title,createdAt,repository",
            "--limit", "\(fetchLimit)",
        ]
        for owner in owners {
            args.append("--owner=\(owner)")
        }
        let output = try await runGH(args: args)
        guard let data = output.data(using: .utf8) else {
            throw GitHubPRError.decodeFailed("non-utf8 output")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([GitHubPR].self, from: data)
            return GitHubPRFetchResult(
                prs: decoded.filter { $0.createdAt >= since },
                truncated: decoded.count >= fetchLimit
            )
        } catch {
            throw GitHubPRError.decodeFailed(String(describing: error))
        }
    }

    // MARK: - Process plumbing

    private static func runGH(args: [String]) async throws -> String {
        let url = try resolveGHExecutable()
        let process = Process()
        process.executableURL = url
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdoutString)
                } else if stderrString.localizedCaseInsensitiveContains("not logged") ||
                          stderrString.localizedCaseInsensitiveContains("auth") {
                    continuation.resume(throwing: GitHubPRError.ghNotAuthenticated(stderr: stderrString))
                } else {
                    continuation.resume(throwing: GitHubPRError.ghFailed(stderr: stderrString))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitHubPRError.ghNotInstalled)
            }
        }
    }

    private static func resolveGHExecutable() throws -> URL {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw GitHubPRError.ghNotInstalled
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()
}
