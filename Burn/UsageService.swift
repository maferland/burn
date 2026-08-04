import Foundation
import ClaudeUsageKit

@Observable
final class UsageService: @unchecked Sendable {
    var usageData: UsageData = .empty
    var isLoading = false
    var errorMessage: String?

    var lastResponse: CCUsageResponse?
    private var refreshTask: Task<Void, Never>?
    private let settings: SettingsStore

    private static let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/usage-cache.json")
    }()

    init(settings: SettingsStore) {
        self.settings = settings
        loadCache()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await Task.detached {
                    try SessionReader.readUsage()
                }.value
                let data = UsageData.from(response: response)
                await MainActor.run {
                    self.lastResponse = response
                    self.usageData = data
                    self.isLoading = false
                }
                self.saveCache(response)
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Disk cache

    /// Mean of the last 30 days with spend, today excluded so it stays a baseline.
    var typicalDayCost: Double {
        let today = UsageData.dateString(from: Date())
        let past = (lastResponse?.daily ?? [])
            .filter { $0.date != today && $0.totalCost > 0 }
            .suffix(30)
        guard !past.isEmpty else { return 0 }
        return past.reduce(0) { $0 + $1.totalCost } / Double(past.count)
    }

    func usageData(weekOffset: Int) -> UsageData {
        guard let response = lastResponse else { return .empty }
        return UsageData.from(response: response, weekOffset: weekOffset)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let response = try? JSONDecoder().decode(CCUsageResponse.self, from: data) else {
            return
        }
        lastResponse = response
        usageData = UsageData.from(response: response)
    }

    private func saveCache(_ response: CCUsageResponse) {
        let dir = Self.cacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(response).write(to: Self.cacheFile)
    }
}
