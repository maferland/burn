import Foundation

/// Mirrors Codex's `TokenUsage`. `inputTokens` already includes `cachedInputTokens`, so never add the two.
struct CodexTokens: Codable, Hashable {
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var reasoningOutputTokens = 0

    var uncachedInputTokens: Int { max(0, inputTokens - cachedInputTokens) }
    var totalTokens: Int { inputTokens + outputTokens }

    static func + (lhs: CodexTokens, rhs: CodexTokens) -> CodexTokens {
        CodexTokens(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens
        )
    }
}

struct CodexModelBreakdown: Codable, Hashable {
    let modelName: String
    let tokens: CodexTokens
    /// API-rate estimate: Codex plan users pay a flat subscription, so this is never billed spend.
    let estimatedCost: Double
}

struct CodexDailyUsage: Codable, Hashable, Identifiable {
    let date: String
    let tokens: CodexTokens
    let estimatedCost: Double
    let modelBreakdowns: [CodexModelBreakdown]

    var id: String { date }
    var modelsUsed: [String] { modelBreakdowns.map(\.modelName) }
}

/// One side of a Codex quota: the rolling 5-hour window (`primary`) or the weekly allowance (`secondary`).
struct CodexRateLimitWindow: Codable, Hashable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
}

/// Codex only reports limits while it runs, so this snapshot goes stale — `capturedAt` says how stale.
struct CodexRateLimits: Codable, Hashable {
    let capturedAt: Date
    let planType: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct CodexUsageResponse: Codable, Hashable {
    let daily: [CodexDailyUsage]
    let tokens: CodexTokens
    let estimatedCost: Double
    let rateLimits: CodexRateLimits?
    /// Rollouts Codex compressed to `.jsonl.zst`; we can't read zstd, so their tokens are missing here.
    let skippedCompressedFiles: Int

    static let empty = CodexUsageResponse(
        daily: [], tokens: CodexTokens(), estimatedCost: 0,
        rateLimits: nil, skippedCompressedFiles: 0
    )

    var isEmpty: Bool { daily.isEmpty }
}
