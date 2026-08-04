import Foundation
import ClaudeUsageKit

/// Reads Codex rollout JSONL (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) and aggregates daily token use.
enum CodexSessionReader {

    static var codexHome: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static var defaultRoots: [URL] {
        let home = codexHome
        return [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: codexHome.path)
    }

    static func readUsage() -> CodexUsageResponse {
        readUsage(roots: defaultRoots, pricing: CodexPricing.fetchPricing())
    }

    static func readUsage(roots: [URL], pricing: [String: ModelPricing]) -> CodexUsageResponse {
        let scan = findRollouts(in: roots)
        guard !scan.files.isEmpty else {
            return CodexUsageResponse(
                daily: [], tokens: CodexTokens(), estimatedCost: 0,
                rateLimits: nil, skippedCompressedFiles: scan.compressedCount
            )
        }

        var seen = Set<String>()
        var buckets: [DayModelKey: CodexTokens] = [:]
        var latestLimits: CodexRateLimits?

        for file in scan.files {
            for event in events(in: file) {
                if let limits = event.rateLimits,
                   limits.capturedAt > (latestLimits?.capturedAt ?? .distantPast) {
                    latestLimits = limits
                }
                guard let tokens = event.tokens, seen.insert(event.dedupKey).inserted else { continue }
                let key = DayModelKey(date: event.dateString, model: event.model)
                buckets[key] = (buckets[key] ?? CodexTokens()) + tokens
            }
        }

        return buildResponse(
            from: buckets, pricing: pricing,
            rateLimits: latestLimits, skippedCompressedFiles: scan.compressedCount
        )
    }

    // MARK: - File discovery

    struct DayModelKey: Hashable {
        let date: String
        let model: String
    }

    struct ScanResult {
        let files: [URL]
        let compressedCount: Int
    }

    static func findRollouts(in roots: [URL]) -> ScanResult {
        let fm = FileManager.default
        var files: [URL] = []
        var compressed = 0

        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name.hasSuffix(".jsonl.zst") {
                    compressed += 1
                } else if name.hasSuffix(".jsonl") {
                    files.append(url)
                }
            }
        }
        return ScanResult(files: files.sorted { $0.path < $1.path }, compressedCount: compressed)
    }

    // MARK: - Line parsing

    struct ParsedEvent {
        let dateString: String
        let model: String
        let tokens: CodexTokens?
        let rateLimits: CodexRateLimits?
        let dedupKey: String
    }

    private static var eventCache: [String: (mtime: Date, events: [ParsedEvent])] = [:]
    private static let cacheLock = NSLock()

    static func resetCacheForTesting() {
        cacheLock.lock()
        eventCache = [:]
        cacheLock.unlock()
    }

    static func events(in file: URL) -> [ParsedEvent] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date

        cacheLock.lock()
        if let mtime, let cached = eventCache[file.path], cached.mtime == mtime {
            cacheLock.unlock()
            return cached.events
        }
        cacheLock.unlock()

        let parsed = parse(file: file)

        if let mtime {
            cacheLock.lock()
            eventCache[file.path] = (mtime, parsed)
            cacheLock.unlock()
        }
        return parsed
    }

    private static func parse(file: URL) -> [ParsedEvent] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        var events: [ParsedEvent] = []
        var model = "unknown"
        var runningTotal: CodexTokens?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { continue }

            switch envelope.type {
            case "turn_context":
                if let decoded = try? JSONDecoder().decode(TurnContextLine.self, from: data) {
                    model = decoded.payload.model
                }
            case "event_msg":
                guard let decoded = try? JSONDecoder().decode(EventMsgLine.self, from: data),
                      decoded.payload.type == "token_count",
                      let timestamp = envelope.timestamp.flatMap(parseTimestamp) else { continue }

                let total = decoded.payload.info?.total_token_usage?.tokens
                // Older Codex builds omit `last_token_usage`; diff the cumulative total instead.
                let turn = decoded.payload.info?.last_token_usage?.tokens ?? total.map { delta(from: runningTotal, to: $0) }
                if let total { runningTotal = total }

                let limits = decoded.payload.rate_limits?.snapshot(capturedAt: timestamp)
                guard turn != nil || limits != nil else { continue }

                events.append(ParsedEvent(
                    dateString: dateString(from: timestamp),
                    model: model,
                    tokens: turn.flatMap { $0.totalTokens > 0 ? $0 : nil },
                    rateLimits: limits,
                    dedupKey: "\(envelope.timestamp ?? "")|\(turn?.inputTokens ?? 0)|\(turn?.outputTokens ?? 0)"
                ))
            default:
                continue
            }
        }
        return events
    }

    private static func delta(from previous: CodexTokens?, to total: CodexTokens) -> CodexTokens {
        guard let previous else { return total }
        return CodexTokens(
            inputTokens: max(0, total.inputTokens - previous.inputTokens),
            cachedInputTokens: max(0, total.cachedInputTokens - previous.cachedInputTokens),
            outputTokens: max(0, total.outputTokens - previous.outputTokens),
            reasoningOutputTokens: max(0, total.reasoningOutputTokens - previous.reasoningOutputTokens)
        )
    }

    // MARK: - Aggregation

    static func buildResponse(
        from buckets: [DayModelKey: CodexTokens],
        pricing: [String: ModelPricing],
        rateLimits: CodexRateLimits?,
        skippedCompressedFiles: Int
    ) -> CodexUsageResponse {
        var byDate: [String: [(model: String, tokens: CodexTokens)]] = [:]
        for (key, tokens) in buckets {
            byDate[key.date, default: []].append((key.model, tokens))
        }

        var totalTokens = CodexTokens()
        var totalCost = 0.0

        let daily: [CodexDailyUsage] = byDate.keys.sorted().map { date in
            var dayTokens = CodexTokens()
            var dayCost = 0.0
            var breakdowns: [CodexModelBreakdown] = []

            for entry in byDate[date]!.sorted(by: { $0.model < $1.model }) {
                let resolved = CodexPricing.resolvePricing(for: entry.model, from: pricing)
                let cost = CodexPricing.cost(for: entry.tokens, pricing: resolved)
                dayTokens = dayTokens + entry.tokens
                dayCost += cost
                breakdowns.append(CodexModelBreakdown(
                    modelName: entry.model, tokens: entry.tokens, estimatedCost: cost
                ))
            }

            totalTokens = totalTokens + dayTokens
            totalCost += dayCost
            return CodexDailyUsage(
                date: date, tokens: dayTokens, estimatedCost: dayCost, modelBreakdowns: breakdowns
            )
        }

        return CodexUsageResponse(
            daily: daily, tokens: totalTokens, estimatedCost: totalCost,
            rateLimits: rateLimits, skippedCompressedFiles: skippedCompressedFiles
        )
    }

    // MARK: - Dates

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dateString(from date: Date) -> String { dayFormatter.string(from: date) }

    static func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

// MARK: - Rollout line shapes

private struct Envelope: Decodable {
    let timestamp: String?
    let type: String
}

private struct TurnContextLine: Decodable {
    struct Payload: Decodable { let model: String }
    let payload: Payload
}

private struct EventMsgLine: Decodable {
    let payload: TokenCountPayload
}

private struct TokenCountPayload: Decodable {
    let type: String
    let info: Info?
    let rate_limits: RateLimits?

    struct Info: Decodable {
        let total_token_usage: Usage?
        let last_token_usage: Usage?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let cached_input_tokens: Int?
        let output_tokens: Int?
        let reasoning_output_tokens: Int?

        var tokens: CodexTokens {
            CodexTokens(
                inputTokens: input_tokens ?? 0,
                cachedInputTokens: cached_input_tokens ?? 0,
                outputTokens: output_tokens ?? 0,
                reasoningOutputTokens: reasoning_output_tokens ?? 0
            )
        }
    }

    struct RateLimits: Decodable {
        let plan_type: String?
        let primary: Window?
        let secondary: Window?

        struct Window: Decodable {
            let used_percent: Double?
            let window_minutes: Int?
            let resets_at: Double?

            var window: CodexRateLimitWindow {
                CodexRateLimitWindow(
                    usedPercent: used_percent ?? 0,
                    windowMinutes: window_minutes,
                    resetsAt: resets_at.map { Date(timeIntervalSince1970: $0) }
                )
            }
        }

        func snapshot(capturedAt: Date) -> CodexRateLimits? {
            guard primary != nil || secondary != nil else { return nil }
            return CodexRateLimits(
                capturedAt: capturedAt,
                planType: plan_type,
                primary: primary?.window,
                secondary: secondary?.window
            )
        }
    }
}
