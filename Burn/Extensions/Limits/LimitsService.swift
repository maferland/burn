import Foundation

@Observable
@MainActor
final class LimitsService {
    /// `/api/oauth/usage` rate-limits, and the registry can tick every minute — so the service keeps
    /// its own floor and ignores the extra ticks.
    static let minimumInterval: TimeInterval = 600

    var response: LimitsResponse = .empty
    var isLoading = false
    var lastRefreshDate: Date = .distantPast

    let store: LimitsAccountStore

    init(
        store: LimitsAccountStore? = nil,
        claude: ClaudeLimitsClient = ClaudeLimitsClient(),
        codex: CodexLimitsClient = CodexLimitsClient(),
        rolloutLimits: @escaping @Sendable @MainActor () -> CodexRateLimits? = { nil },
        cacheFile: URL? = nil
    ) {
        self.store = store ?? LimitsAccountStore()
        self.claude = claude
        self.codex = codex
        self.rolloutLimits = rolloutLimits
        self.cacheFile = cacheFile ?? Self.defaultCacheFile
        loadCache()
    }

    private let claude: ClaudeLimitsClient
    private let codex: CodexLimitsClient
    private let rolloutLimits: @Sendable @MainActor () -> CodexRateLimits?
    private let cacheFile: URL
    private var refreshTask: Task<Void, Never>?

    var accounts: [LimitsAccount] { store.accounts }

    func refresh(force: Bool = false) {
        guard !isLoading else { return }
        if !force, Date().timeIntervalSince(lastRefreshDate) < Self.minimumInterval { return }

        let accounts = store.accounts
        guard !accounts.isEmpty else {
            response = .empty
            lastRefreshDate = Date()
            return
        }

        isLoading = true
        let fallback = rolloutLimits()
        let previous = response.accounts
        let claude = claude
        let codex = codex

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let fresh = await Self.fetch(
                accounts: accounts, claude: claude, codex: codex, rolloutLimits: fallback
            )
            guard let self, !Task.isCancelled else { return }
            let merged = Self.merge(fresh: fresh, previous: previous)
            self.response = LimitsResponse(accounts: merged)
            self.lastRefreshDate = Date()
            self.isLoading = false
            self.saveCache()
        }
    }

    nonisolated static func fetch(
        accounts: [LimitsAccount],
        claude: ClaudeLimitsClient,
        codex: CodexLimitsClient,
        rolloutLimits: CodexRateLimits?
    ) async -> [AccountSnapshot] {
        await withTaskGroup(of: (Int, AccountSnapshot).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    switch account.provider {
                    case .claude:
                        return (index, await claude.snapshot(for: account))
                    case .codex:
                        return (index, await codex.snapshot(for: account, rolloutLimits: rolloutLimits))
                    }
                }
            }
            var collected: [(Int, AccountSnapshot)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// A failed refresh keeps the last good numbers and flags them stale — a 429 shouldn't blank the tab.
    nonisolated static func merge(
        fresh: [AccountSnapshot], previous: [AccountSnapshot]
    ) -> [AccountSnapshot] {
        fresh.map { snapshot in
            guard snapshot.failure != nil, !snapshot.hasData,
                  let old = previous.first(where: { $0.id == snapshot.id }), old.hasData else {
                return snapshot
            }
            var kept = old
            kept.failure = snapshot.failure
            return kept
        }
    }

    // MARK: - Cache

    private static let defaultCacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/limits-cache.json")
    }()

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(LimitsResponse.self, from: data) else { return }
        response = cached
    }

    private func saveCache() {
        let dir = cacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(response).write(to: cacheFile)
    }
}
