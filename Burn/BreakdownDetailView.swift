import SwiftUI

struct BreakdownDetailView: View {
    let data: BreakdownData
    let onBack: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            total
            rows
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ember.accent.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .background(Ember.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .pointingHandCursor()

            Text(data.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.primary)
            Spacer()
            Text(data.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(Ember.label)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var total: some View {
        EmberHero(cost: data.totalCost) {
            Text("across input, output and cache")
        }
        .padding(.bottom, 16)
    }

    private var rows: some View {
        EmberSection(title: "Where it went") {
            VStack(spacing: 10) {
                row("Input", tokens: data.inputTokens, cost: data.inputCost, emphasis: 1.0)
                row("Output", tokens: data.outputTokens, cost: data.outputCost, emphasis: 0.75)
                row("Cache write", tokens: data.cacheWriteTokens, cost: data.cacheWriteCost, emphasis: 0.5)
                row("Cache read", tokens: data.cacheReadTokens, cost: data.cacheReadCost, emphasis: 0.35)
            }
        }
    }

    private func row(_ label: String, tokens: Int, cost: Double, emphasis: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.primary)
                .frame(width: 82, alignment: .leading)
            Text(Formatters.tokensCompact(tokens))
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(Formatters.cost(cost))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(data.totalCost > 0 && cost / data.totalCost > 0.4 ? Ember.accent : Ember.primary)
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
        }
    }
}
