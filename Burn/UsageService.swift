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

    private static let defaultCacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/usage-cache.json")
    }()

    private let cacheFile: URL

    init(settings: SettingsStore, cacheFile: URL? = nil) {
        self.settings = settings
        self.cacheFile = cacheFile ?? Self.defaultCacheFile
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

    private var typicalSamples: [TypicalPeriod.Sample] {
        (lastResponse?.daily ?? []).map {
            .init(date: $0.date, cost: $0.totalCost, tokens: $0.inputTokens + $0.outputTokens)
        }
    }

    var typicalDayCost: Double { TypicalPeriod.day(typicalSamples).cost }
    var typicalDayTokens: Int { TypicalPeriod.day(typicalSamples).tokens }
    var typicalWeekCost: Double { TypicalPeriod.week(typicalSamples).cost }
    var typicalWeekTokens: Int { TypicalPeriod.week(typicalSamples).tokens }
    var typicalMonthCost: Double { TypicalPeriod.month(typicalSamples).cost }
    var typicalMonthTokens: Int { TypicalPeriod.month(typicalSamples).tokens }

    func usageData(weekOffset: Int) -> UsageData {
        guard let response = lastResponse else { return .empty }
        return UsageData.from(response: response, weekOffset: weekOffset)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile),
              let response = try? JSONDecoder().decode(CCUsageResponse.self, from: data) else {
            return
        }
        lastResponse = response
        usageData = UsageData.from(response: response)
    }

    private func saveCache(_ response: CCUsageResponse) {
        let dir = cacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(response).write(to: cacheFile)
    }
}

extension UsageService {
    func day(_ date: String) -> DailyUsage? {
        lastResponse?.daily.first { $0.date == date }
    }
}
