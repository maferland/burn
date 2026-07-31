import Foundation
import ClaudeUsageKit

/// OpenAI rates from LiteLLM, cached on disk. Separate from `PricingService`, which filters to `claude-*`.
enum CodexPricing {
    private static let litellmURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    static let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.burn/openai-pricing.json")
    }()

    private struct LiteLLMEntry: Decodable {
        let input_cost_per_token: Double?
        let output_cost_per_token: Double?
        let cache_read_input_token_cost: Double?
        let litellm_provider: String?
    }

    static func fetchPricing() -> [String: ModelPricing] {
        if let cached = loadCached() { return cached }
        if let fetched = fetchFromNetwork() { return fetched }
        return fallbackPricing
    }

    static func resolvePricing(for model: String, from table: [String: ModelPricing]) -> ModelPricing {
        if let exact = table[model] { return exact }

        let lower = model.lowercased()
        // "gpt-5.1-codex-max" resolves against "gpt-5.1-codex" before "gpt-5".
        let prefixMatches = table.keys
            .filter { lower.hasPrefix($0.lowercased()) }
            .sorted { $0.count > $1.count }
        if let best = prefixMatches.first, let pricing = table[best] { return pricing }

        let family = table.keys
            .filter { lower.contains("codex") ? $0.contains("codex") : $0.hasPrefix("gpt-5") }
            .sorted()
            .last
        if let family, let pricing = table[family] { return pricing }

        return fallbackPricing["gpt-5.1-codex"]!
    }

    private static func loadCached() -> [String: ModelPricing]? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: cacheFile.path),
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
            try? FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: .atomic)
            result = parseLiteLLM(data)
        }
        task.resume()
        semaphore.wait()
        return result
    }

    static func parseLiteLLM(_ data: Data) -> [String: ModelPricing]? {
        guard let raw = try? JSONDecoder().decode([String: LiteLLMEntry].self, from: data) else { return nil }

        var pricing: [String: ModelPricing] = [:]
        for (key, entry) in raw {
            guard entry.litellm_provider == "openai" || entry.litellm_provider == nil else { continue }
            let lower = key.lowercased()
            guard lower.hasPrefix("gpt-5") || lower.hasPrefix("codex-") || lower.contains("-codex") else { continue }
            guard let input = entry.input_cost_per_token, let output = entry.output_cost_per_token else { continue }

            pricing[key] = ModelPricing(
                inputCostPerToken: input,
                outputCostPerToken: output,
                cacheCreationCostPerToken: 0,
                cacheReadCostPerToken: entry.cache_read_input_token_cost ?? input
            )
        }
        return pricing.isEmpty ? nil : pricing
    }

    /// Used only when LiteLLM is unreachable and uncached; GPT-5 family rates.
    static let fallbackPricing: [String: ModelPricing] = [
        "gpt-5.1-codex": ModelPricing(
            inputCostPerToken: 1.25e-06,
            outputCostPerToken: 1.0e-05,
            cacheCreationCostPerToken: 0,
            cacheReadCostPerToken: 1.25e-07
        )
    ]

    static func cost(for tokens: CodexTokens, pricing: ModelPricing) -> Double {
        Double(tokens.uncachedInputTokens) * pricing.inputCostPerToken
            + Double(tokens.cachedInputTokens) * pricing.cacheReadCostPerToken
            + Double(tokens.outputTokens) * pricing.outputCostPerToken
    }
}
