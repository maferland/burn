import Foundation

/// Reads Claude Code JSONL session files directly, replacing the ccusage CLI dependency.
/// Scans ~/.claude/projects/**/*.jsonl, extracts assistant message usage data,
/// and aggregates into the same CCUsageResponse shape the app already consumes.
enum SessionReader {

    // MARK: - Pricing

    private static let litellmURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    struct ModelPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationCostPerToken: Double
        let cacheReadCostPerToken: Double
    }

    /// LiteLLM JSON entry shape (only fields we need)
    private struct LiteLLMEntry: Decodable {
        let input_cost_per_token: Double?
        let output_cost_per_token: Double?
        let cache_creation_input_token_cost: Double?
        let cache_read_input_token_cost: Double?
    }

    private static let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/litellm-pricing.json")
    }()

    private static let cacheTTL: TimeInterval = 24 * 60 * 60 // 1 day

    /// Fetch pricing from LiteLLM (with local cache). Returns model name -> pricing map.
    static func fetchPricing() -> [String: ModelPricing] {
        // Try cached file first
        if let cached = loadCachedPricing() {
            return cached
        }

        // Fetch from network (synchronous — called from background thread)
        if let fetched = fetchFromNetwork() {
            return fetched
        }

        // Fallback to hardcoded defaults
        return fallbackPricing
    }

    private static func loadCachedPricing() -> [String: ModelPricing]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheFile.path),
              let attrs = try? fm.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < cacheTTL,
              let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }
        return parseLiteLLM(data)
    }

    private static func fetchFromNetwork() -> [String: ModelPricing]? {
        var request = URLRequest(url: litellmURL)
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: ModelPricing]?

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            // Cache raw JSON
            let dir = cacheFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: cacheFile)
            result = parseLiteLLM(data)
        }
        task.resume()
        semaphore.wait()
        return result
    }

    private static func parseLiteLLM(_ data: Data) -> [String: ModelPricing]? {
        guard let raw = try? JSONDecoder().decode([String: LiteLLMEntry].self, from: data) else {
            return nil
        }

        var pricing: [String: ModelPricing] = [:]
        for (key, entry) in raw {
            // Only Claude models
            let lower = key.lowercased()
            guard lower.hasPrefix("claude-") || lower.hasPrefix("anthropic/claude-") || lower.hasPrefix("anthropic.claude-") else {
                continue
            }
            guard let input = entry.input_cost_per_token,
                  let output = entry.output_cost_per_token else { continue }

            // Normalize key: strip provider prefix
            let modelName: String
            if lower.hasPrefix("anthropic/") {
                modelName = String(key.dropFirst("anthropic/".count))
            } else if lower.hasPrefix("anthropic.") {
                modelName = String(key.dropFirst("anthropic.".count))
            } else {
                modelName = key
            }

            pricing[modelName] = ModelPricing(
                inputCostPerToken: input,
                outputCostPerToken: output,
                cacheCreationCostPerToken: entry.cache_creation_input_token_cost ?? input,
                cacheReadCostPerToken: entry.cache_read_input_token_cost ?? input
            )
        }
        return pricing.isEmpty ? nil : pricing
    }

    /// Hardcoded fallback (Opus 4.6, Sonnet 4.6, Haiku 4.5 rates)
    private static let fallbackPricing: [String: ModelPricing] = {
        var p: [String: ModelPricing] = [:]
        let opus = ModelPricing(inputCostPerToken: 5e-06, outputCostPerToken: 2.5e-05,
                                cacheCreationCostPerToken: 6.25e-06, cacheReadCostPerToken: 5e-07)
        let sonnet = ModelPricing(inputCostPerToken: 3e-06, outputCostPerToken: 1.5e-05,
                                  cacheCreationCostPerToken: 3.75e-06, cacheReadCostPerToken: 3e-07)
        let haiku = ModelPricing(inputCostPerToken: 1e-06, outputCostPerToken: 5e-06,
                                 cacheCreationCostPerToken: 1.25e-06, cacheReadCostPerToken: 1e-07)
        p["claude-opus-4-6"] = opus
        p["claude-sonnet-4-6"] = sonnet
        p["claude-haiku-4-5"] = haiku
        return p
    }()

    private static func resolvePricing(for model: String, from table: [String: ModelPricing]) -> ModelPricing {
        // Exact match
        if let p = table[model] { return p }

        // Fuzzy match by family
        let lower = model.lowercased()
        let family: String
        if lower.contains("opus") { family = "opus" }
        else if lower.contains("sonnet") { family = "sonnet" }
        else if lower.contains("haiku") { family = "haiku" }
        else { family = "opus" } // safe overestimate

        // Find best match: prefer latest version of the same family
        let candidates = table.filter { $0.key.lowercased().contains(family) }
        if let best = candidates.max(by: { $0.key < $1.key }) {
            return best.value
        }

        return fallbackPricing.values.first!
    }

    // MARK: - Timestamp handling

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// Convert ISO 8601 UTC timestamp to local date string (yyyy-MM-dd)
    private static func localDate(from timestamp: String) -> String? {
        guard let date = isoFormatter.date(from: timestamp)
                ?? isoFormatterNoFrac.date(from: timestamp) else {
            return nil
        }
        return localDateFormatter.string(from: date)
    }

    // MARK: - JSONL structures

    private struct Entry: Decodable {
        let type: String?
        let message: Message?
        let timestamp: String?
    }

    private struct Message: Decodable {
        let role: String?
        let model: String?
        let id: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    // MARK: - Aggregation types

    private struct DayModelKey: Hashable {
        let date: String
        let model: String
    }

    private struct TokenBucket {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0

        var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

        mutating func add(_ usage: Usage) {
            inputTokens += usage.input_tokens ?? 0
            outputTokens += usage.output_tokens ?? 0
            cacheCreationTokens += usage.cache_creation_input_tokens ?? 0
            cacheReadTokens += usage.cache_read_input_tokens ?? 0
        }

        func cost(for model: String, pricing: ModelPricing) -> Double {
            Double(inputTokens) * pricing.inputCostPerToken
                + Double(outputTokens) * pricing.outputCostPerToken
                + Double(cacheCreationTokens) * pricing.cacheCreationCostPerToken
                + Double(cacheReadTokens) * pricing.cacheReadCostPerToken
        }
    }

    // MARK: - Public API

    static func readUsage() throws -> CCUsageResponse {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            return CCUsageResponse(daily: [], totals: Totals(
                inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                cacheReadTokens: 0, totalTokens: 0, totalCost: 0
            ))
        }

        let pricingTable = fetchPricing()
        var buckets: [DayModelKey: TokenBucket] = [:]
        let decoder = JSONDecoder()
        let jsonlFiles = findJSONLFiles(in: claudeDir)

        for fileURL in jsonlFiles {
            try autoreleasepool {
                try processFile(fileURL, decoder: decoder, into: &buckets)
            }
        }

        return buildResponse(from: buckets, pricing: pricingTable)
    }

    // MARK: - File discovery

    private static func findJSONLFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files
    }

    // MARK: - File processing

    private static func processFile(
        _ url: URL,
        decoder: JSONDecoder,
        into buckets: inout [DayModelKey: TokenBucket]
    ) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? decoder.decode(Entry.self, from: lineData) else { continue }

            guard entry.type == "assistant",
                  let msg = entry.message,
                  msg.role == "assistant",
                  let usage = msg.usage,
                  let model = msg.model,
                  model != "<synthetic>",
                  let timestamp = entry.timestamp else { continue }

            guard let dateStr = localDate(from: timestamp) else { continue }

            let key = DayModelKey(date: dateStr, model: model)
            buckets[key, default: TokenBucket()].add(usage)
        }
    }

    // MARK: - Response building

    private static func buildResponse(
        from buckets: [DayModelKey: TokenBucket],
        pricing pricingTable: [String: ModelPricing]
    ) -> CCUsageResponse {
        var byDate: [String: [(model: String, bucket: TokenBucket)]] = [:]
        for (key, bucket) in buckets {
            byDate[key.date, default: []].append((key.model, bucket))
        }

        var totalBucket = TokenBucket()
        var totalCost = 0.0

        let daily: [DailyUsage] = byDate.keys.sorted().map { date in
            let entries = byDate[date]!
            var dayBucket = TokenBucket()
            var dayCost = 0.0
            var models: [String] = []
            var breakdowns: [ModelBreakdown] = []

            for (model, bucket) in entries.sorted(by: { $0.model < $1.model }) {
                let p = resolvePricing(for: model, from: pricingTable)
                let cost = bucket.cost(for: model, pricing: p)
                dayBucket.inputTokens += bucket.inputTokens
                dayBucket.outputTokens += bucket.outputTokens
                dayBucket.cacheCreationTokens += bucket.cacheCreationTokens
                dayBucket.cacheReadTokens += bucket.cacheReadTokens
                dayCost += cost
                models.append(model)
                breakdowns.append(ModelBreakdown(
                    modelName: model,
                    inputTokens: bucket.inputTokens,
                    outputTokens: bucket.outputTokens,
                    cacheCreationTokens: bucket.cacheCreationTokens,
                    cacheReadTokens: bucket.cacheReadTokens,
                    cost: cost
                ))
            }

            totalBucket.inputTokens += dayBucket.inputTokens
            totalBucket.outputTokens += dayBucket.outputTokens
            totalBucket.cacheCreationTokens += dayBucket.cacheCreationTokens
            totalBucket.cacheReadTokens += dayBucket.cacheReadTokens
            totalCost += dayCost

            return DailyUsage(
                date: date,
                inputTokens: dayBucket.inputTokens,
                outputTokens: dayBucket.outputTokens,
                cacheCreationTokens: dayBucket.cacheCreationTokens,
                cacheReadTokens: dayBucket.cacheReadTokens,
                totalTokens: dayBucket.totalTokens,
                totalCost: dayCost,
                modelsUsed: models,
                modelBreakdowns: breakdowns
            )
        }

        let totals = Totals(
            inputTokens: totalBucket.inputTokens,
            outputTokens: totalBucket.outputTokens,
            cacheCreationTokens: totalBucket.cacheCreationTokens,
            cacheReadTokens: totalBucket.cacheReadTokens,
            totalTokens: totalBucket.totalTokens,
            totalCost: totalCost
        )

        return CCUsageResponse(daily: daily, totals: totals)
    }
}
