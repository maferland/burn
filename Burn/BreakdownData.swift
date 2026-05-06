import Foundation
import ClaudeUsageKit

struct BreakdownData: Codable, Hashable {
    let title: String
    let subtitle: String
    let totalCost: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let inputCost: Double
    let outputCost: Double
    let cacheWriteCost: Double
    let cacheReadCost: Double

    static func empty(title: String, subtitle: String) -> BreakdownData {
        BreakdownData(
            title: title, subtitle: subtitle, totalCost: 0,
            inputTokens: 0, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0,
            inputCost: 0, outputCost: 0, cacheWriteCost: 0, cacheReadCost: 0
        )
    }

    static func compute(title: String, subtitle: String, days: [DailyUsage]) -> BreakdownData {
        let pricing = PricingService.fetchPricing()
        var input = 0, output = 0, cw = 0, cr = 0
        var inputCost = 0.0, outputCost = 0.0, cwCost = 0.0, crCost = 0.0
        var totalCost = 0.0
        for day in days {
            input  += day.inputTokens
            output += day.outputTokens
            cw     += day.cacheCreationTokens
            cr     += day.cacheReadTokens
            totalCost += day.totalCost
            for mb in day.modelBreakdowns {
                let p = PricingService.resolvePricing(for: mb.modelName, from: pricing)
                inputCost  += Double(mb.inputTokens)         * p.inputCostPerToken
                outputCost += Double(mb.outputTokens)        * p.outputCostPerToken
                cwCost     += Double(mb.cacheCreationTokens) * p.cacheCreationCostPerToken
                crCost     += Double(mb.cacheReadTokens)     * p.cacheReadCostPerToken
            }
        }
        return BreakdownData(
            title: title, subtitle: subtitle, totalCost: totalCost,
            inputTokens: input, outputTokens: output,
            cacheWriteTokens: cw, cacheReadTokens: cr,
            inputCost: inputCost, outputCost: outputCost,
            cacheWriteCost: cwCost, cacheReadCost: crCost
        )
    }
}
