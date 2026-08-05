import Foundation

@Observable
final class CodexUsageService: @unchecked Sendable {
    var response: CodexUsageResponse = .empty
    var isLoading = false
    var errorMessage: String?
    var lastRefreshDate: Date = .distantPast

    private var refreshTask: Task<Void, Never>?

    private static let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/codex-usage-cache.json")
    }()

    init() {
        loadCache()
    }

    var isInstalled: Bool { CodexSessionReader.isInstalled }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let parsed = await Task.detached { CodexSessionReader.readUsage() }.value
            if Task.isCancelled {
                await MainActor.run { self.isLoading = false }
                return
            }
            await MainActor.run {
                self.response = parsed
                self.lastRefreshDate = Date()
                self.isLoading = false
            }
            self.saveCache(parsed)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let cached = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else { return }
        response = cached
    }

    private func saveCache(_ response: CodexUsageResponse) {
        let dir = Self.cacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(response).write(to: Self.cacheFile)
    }
}

extension CodexUsageResponse {
    func day(_ date: String) -> CodexDailyUsage? {
        daily.first { $0.date == date }
    }

    var todayCost: Double {
        day(CodexSessionReader.dateString(from: Date()))?.estimatedCost ?? 0
    }

    /// Seven entries ending today, zero-filled so the chart keeps a stable shape.
    func last7Days(endingAt end: Date = Date()) -> [CodexDailyUsage] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset -> CodexDailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = CodexSessionReader.dateString(from: date)
            return day(key) ?? CodexDailyUsage(
                date: key, tokens: CodexTokens(), estimatedCost: 0, modelBreakdowns: []
            )
        }
    }

    func cost(inLast days: Int, endingAt end: Date = Date()) -> Double {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return 0 }
        let startKey = CodexSessionReader.dateString(from: start)
        let endKey = CodexSessionReader.dateString(from: end)
        return daily.filter { $0.date >= startKey && $0.date <= endKey }.reduce(0) { $0 + $1.estimatedCost }
    }

    func monthCost(endingAt end: Date = Date()) -> Double {
        let prefix = String(CodexSessionReader.dateString(from: end).prefix(7))
        return daily.filter { $0.date.hasPrefix(prefix) }.reduce(0) { $0 + $1.estimatedCost }
    }
}

extension CodexUsageService {
    /// Mean of the days with spend, today excluded, matching how the Claude baseline is built.
    var typicalDayCost: Double {
        let past = baselineDays
        guard !past.isEmpty else { return 0 }
        return past.reduce(0) { $0 + $1.estimatedCost } / Double(past.count)
    }

    var typicalDayTokens: Int {
        let past = baselineDays
        guard !past.isEmpty else { return 0 }
        return past.reduce(0) { $0 + $1.tokens.uncachedInputTokens + $1.tokens.outputTokens } / past.count
    }

    private var baselineDays: ArraySlice<CodexDailyUsage> {
        let today = CodexSessionReader.dateString(from: Date())
        return response.daily.filter { $0.date != today && $0.estimatedCost > 0 }.suffix(30)
    }
}
