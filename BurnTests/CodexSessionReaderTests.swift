import XCTest
@testable import Burn
import ClaudeUsageKit

final class CodexSessionReaderTests: XCTestCase {
    private var root: URL!

    private let pricing: [String: ModelPricing] = [
        "gpt-5.1-codex": ModelPricing(
            inputCostPerToken: 1e-06,
            outputCostPerToken: 1e-05,
            cacheCreationCostPerToken: 0,
            cacheReadCostPerToken: 1e-07
        )
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-reader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CodexSessionReader.resetCacheForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func write(_ lines: [String], name: String = "rollout-2026-07-30T09-00-00-abc.jsonl") throws {
        let dir = root.appendingPathComponent("2026/07/30")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8
        )
    }

    private func turnContext(model: String, at timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"turn_context","payload":{"cwd":"/tmp","approval_policy":"on-request","sandbox_policy":{"mode":"workspace-write"},"model":"\(model)"}}
        """
    }

    private func tokenCount(
        at timestamp: String,
        last: (input: Int, cached: Int, output: Int)?,
        total: (input: Int, cached: Int, output: Int)? = nil,
        rateLimits: String? = nil
    ) -> String {
        func usage(_ u: (input: Int, cached: Int, output: Int)) -> String {
            """
            {"input_tokens":\(u.input),"cached_input_tokens":\(u.cached),"cache_write_input_tokens":0,"output_tokens":\(u.output),"reasoning_output_tokens":0,"total_tokens":\(u.input + u.output)}
            """
        }
        var info = "null"
        if last != nil || total != nil {
            let totalPart = total.map(usage) ?? last.map(usage) ?? "null"
            let lastPart = last.map(usage) ?? "null"
            info = """
            {"total_token_usage":\(totalPart),"last_token_usage":\(lastPart),"model_context_window":272000}
            """
        }
        return """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":\(info),"rate_limits":\(rateLimits ?? "null")}}
        """
    }

    private func rateLimits(primary: Double, secondary: Double, plan: String = "pro") -> String {
        """
        {"limit_id":null,"limit_name":null,"primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1785000000},"secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1785600000},"credits":null,"individual_limit":null,"spend_control_reached":false,"plan_type":"\(plan)","rate_limit_reached_type":null}
        """
    }

    private func read() -> CodexUsageResponse {
        CodexSessionReader.readUsage(roots: [root], pricing: pricing)
    }

    private func expectedDay(_ timestamp: String) -> String {
        CodexSessionReader.dateString(from: CodexSessionReader.parseTimestamp(timestamp)!)
    }

    // MARK: - Aggregation

    func testSumsPerTurnUsageForOneDay() throws {
        let ts = "2026-07-30T14:00:00.000Z"
        try write([
            turnContext(model: "gpt-5.1-codex", at: ts),
            tokenCount(at: ts, last: (input: 1_000, cached: 400, output: 200)),
            tokenCount(at: "2026-07-30T14:05:00.000Z", last: (input: 2_000, cached: 1_000, output: 300))
        ])

        let response = read()

        XCTAssertEqual(response.daily.count, 1)
        let day = response.daily[0]
        XCTAssertEqual(day.date, expectedDay(ts))
        XCTAssertEqual(day.tokens.inputTokens, 3_000)
        XCTAssertEqual(day.tokens.cachedInputTokens, 1_400)
        XCTAssertEqual(day.tokens.outputTokens, 500)
        XCTAssertEqual(day.modelsUsed, ["gpt-5.1-codex"])
    }

    func testCostChargesCachedInputAtTheCacheRate() throws {
        let ts = "2026-07-30T14:00:00.000Z"
        try write([
            turnContext(model: "gpt-5.1-codex", at: ts),
            tokenCount(at: ts, last: (input: 1_000, cached: 400, output: 200))
        ])

        // 600 uncached @ 1e-6 + 400 cached @ 1e-7 + 200 out @ 1e-5 = 0.00064 + 0.00004 + 0.002
        XCTAssertEqual(read().estimatedCost, 0.00264, accuracy: 1e-9)
    }

    func testAttributesTokensToTheMostRecentTurnContextModel() throws {
        try write([
            tokenCount(at: "2026-07-30T14:00:00.000Z", last: (input: 100, cached: 0, output: 10)),
            turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:01:00.000Z"),
            tokenCount(at: "2026-07-30T14:02:00.000Z", last: (input: 200, cached: 0, output: 20))
        ])

        let breakdowns = read().daily[0].modelBreakdowns
        XCTAssertEqual(breakdowns.map(\.modelName), ["gpt-5.1-codex", "unknown"])
        XCTAssertEqual(breakdowns.first { $0.modelName == "unknown" }?.tokens.inputTokens, 100)
        XCTAssertEqual(breakdowns.first { $0.modelName == "gpt-5.1-codex" }?.tokens.inputTokens, 200)
    }

    func testCountsReplayedLinesOnceAcrossForkedRollouts() throws {
        let line = tokenCount(at: "2026-07-30T14:00:00.000Z", last: (input: 1_000, cached: 0, output: 100))
        try write([turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:00:00.000Z"), line])
        try write(
            [turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:00:00.000Z"), line],
            name: "rollout-2026-07-30T15-00-00-def.jsonl"
        )

        XCTAssertEqual(read().tokens.inputTokens, 1_000)
    }

    func testDiffsCumulativeTotalsWhenPerTurnUsageIsMissing() throws {
        try write([
            turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:00:00.000Z"),
            tokenCount(at: "2026-07-30T14:00:00.000Z", last: nil, total: (input: 1_000, cached: 0, output: 100)),
            tokenCount(at: "2026-07-30T14:05:00.000Z", last: nil, total: (input: 2_500, cached: 0, output: 250))
        ])

        let day = read().daily[0]
        XCTAssertEqual(day.tokens.inputTokens, 2_500)
        XCTAssertEqual(day.tokens.outputTokens, 250)
    }

    func testSplitsUsageAcrossDays() throws {
        try write([
            turnContext(model: "gpt-5.1-codex", at: "2026-07-29T14:00:00.000Z"),
            tokenCount(at: "2026-07-29T14:00:00.000Z", last: (input: 100, cached: 0, output: 10)),
            tokenCount(at: "2026-07-31T14:00:00.000Z", last: (input: 300, cached: 0, output: 30))
        ])

        let response = read()
        XCTAssertEqual(response.daily.count, 2)
        XCTAssertEqual(response.daily.map(\.date), [
            expectedDay("2026-07-29T14:00:00.000Z"),
            expectedDay("2026-07-31T14:00:00.000Z")
        ])
    }

    // MARK: - Rate limits

    func testKeepsTheNewestRateLimitSnapshot() throws {
        try write([
            tokenCount(
                at: "2026-07-30T14:00:00.000Z", last: (input: 10, cached: 0, output: 1),
                rateLimits: rateLimits(primary: 12.5, secondary: 40)
            ),
            tokenCount(
                at: "2026-07-30T18:00:00.000Z", last: (input: 10, cached: 0, output: 1),
                rateLimits: rateLimits(primary: 61.25, secondary: 47.5)
            )
        ])

        let limits = try XCTUnwrap(read().rateLimits)
        XCTAssertEqual(limits.primary?.usedPercent, 61.25)
        XCTAssertEqual(limits.secondary?.usedPercent, 47.5)
        XCTAssertEqual(limits.primary?.windowMinutes, 300)
        XCTAssertEqual(limits.planType, "pro")
        XCTAssertEqual(limits.capturedAt, CodexSessionReader.parseTimestamp("2026-07-30T18:00:00.000Z"))
    }

    func testRateLimitOnlyEventsAddNoTokens() throws {
        try write([
            tokenCount(at: "2026-07-30T14:00:00.000Z", last: nil, rateLimits: rateLimits(primary: 5, secondary: 5))
        ])

        let response = read()
        XCTAssertTrue(response.daily.isEmpty)
        XCTAssertNotNil(response.rateLimits)
    }

    // MARK: - File discovery

    func testCountsCompressedRolloutsItCannotRead() throws {
        try write([
            turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:00:00.000Z"),
            tokenCount(at: "2026-07-30T14:00:00.000Z", last: (input: 100, cached: 0, output: 10))
        ])
        let dir = root.appendingPathComponent("2026/07/29")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: dir.appendingPathComponent("rollout-old.jsonl.zst"))

        let response = read()
        XCTAssertEqual(response.skippedCompressedFiles, 1)
        XCTAssertEqual(response.daily.count, 1)
    }

    func testMissingSessionsDirectoryYieldsEmptyResponse() {
        let missing = root.appendingPathComponent("nope")
        let response = CodexSessionReader.readUsage(roots: [missing], pricing: pricing)

        XCTAssertTrue(response.isEmpty)
        XCTAssertNil(response.rateLimits)
        XCTAssertEqual(response.estimatedCost, 0)
    }

    func testSkipsUnparseableLinesWithoutLosingTheFile() throws {
        try write([
            turnContext(model: "gpt-5.1-codex", at: "2026-07-30T14:00:00.000Z"),
            "{not json at all",
            #"{"timestamp":"2026-07-30T14:01:00.000Z","type":"response_item","payload":{"type":"message"}}"#,
            tokenCount(at: "2026-07-30T14:02:00.000Z", last: (input: 100, cached: 0, output: 10))
        ])

        XCTAssertEqual(read().tokens.inputTokens, 100)
    }

    // MARK: - Pricing resolution

    func testResolvesTheLongestMatchingModelPrefix() {
        let table: [String: ModelPricing] = [
            "gpt-5": ModelPricing(inputCostPerToken: 1, outputCostPerToken: 1, cacheCreationCostPerToken: 0, cacheReadCostPerToken: 0),
            "gpt-5.1-codex": ModelPricing(inputCostPerToken: 2, outputCostPerToken: 2, cacheCreationCostPerToken: 0, cacheReadCostPerToken: 0)
        ]

        XCTAssertEqual(CodexPricing.resolvePricing(for: "gpt-5.1-codex-max", from: table).inputCostPerToken, 2)
        XCTAssertEqual(CodexPricing.resolvePricing(for: "gpt-5-mini", from: table).inputCostPerToken, 1)
    }

    func testFallsBackToTheCodexFamilyForUnknownModels() {
        let table: [String: ModelPricing] = [
            "gpt-5.1-codex": ModelPricing(inputCostPerToken: 2, outputCostPerToken: 2, cacheCreationCostPerToken: 0, cacheReadCostPerToken: 0)
        ]

        XCTAssertEqual(CodexPricing.resolvePricing(for: "o9-codex-preview", from: table).inputCostPerToken, 2)
    }

    func testParsesOnlyOpenAIEntriesFromLiteLLM() throws {
        let json = """
        {
          "claude-opus-4-6": {"input_cost_per_token": 5e-06, "output_cost_per_token": 2.5e-05, "litellm_provider": "anthropic"},
          "gpt-5.1-codex": {"input_cost_per_token": 1.25e-06, "output_cost_per_token": 1e-05, "cache_read_input_token_cost": 1.25e-07, "litellm_provider": "openai"},
          "gpt-5-chat": {"input_cost_per_token": 1.25e-06, "output_cost_per_token": 1e-05, "litellm_provider": "openai"}
        }
        """
        let table = try XCTUnwrap(CodexPricing.parseLiteLLM(Data(json.utf8)))

        XCTAssertEqual(Set(table.keys), ["gpt-5.1-codex", "gpt-5-chat"])
        XCTAssertEqual(table["gpt-5.1-codex"]?.cacheReadCostPerToken, 1.25e-07)
    }

    // MARK: - Response helpers

    func testWeekAndMonthTotalsUseTheResponseDays() {
        let end = CodexSessionReader.parseTimestamp("2026-07-30T12:00:00.000Z")!
        let calendar = Calendar.current
        func day(_ offset: Int, cost: Double) -> CodexDailyUsage {
            let date = calendar.date(byAdding: .day, value: offset, to: end)!
            return CodexDailyUsage(
                date: CodexSessionReader.dateString(from: date),
                tokens: CodexTokens(), estimatedCost: cost, modelBreakdowns: []
            )
        }
        let response = CodexUsageResponse(
            daily: [day(-30, cost: 100), day(-3, cost: 5), day(0, cost: 2)],
            tokens: CodexTokens(), estimatedCost: 107, rateLimits: nil, skippedCompressedFiles: 0
        )

        XCTAssertEqual(response.cost(inLast: 7, endingAt: end), 7)
        XCTAssertEqual(response.last7Days(endingAt: end).count, 7)
        XCTAssertEqual(response.last7Days(endingAt: end).last?.estimatedCost, 2)
    }
}
