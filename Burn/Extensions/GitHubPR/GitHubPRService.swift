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

enum GitHubPRService {
    /// Returns all PRs the authenticated user opened on the given local-day date.
    static func fetchPRsOpened(on date: Date) async throws -> [GitHubPR] {
        let dateString = isoDayFormatter.string(from: date)
        let args = [
            "search", "prs",
            "--author=@me",
            "--created=\(dateString)",
            "--json", "url,title,createdAt,repository",
            "--limit", "200",
        ]
        let output = try await runGH(args: args)
        guard let data = output.data(using: .utf8) else {
            throw GitHubPRError.decodeFailed("non-utf8 output")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([GitHubPR].self, from: data)
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
