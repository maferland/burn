import SwiftUI

struct BreakdownDetailView: View {
    let data: BreakdownData
    let onBack: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            panel
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text("Back").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .pointingHandCursor()

            Spacer()
            Text(data.title)
                .font(.headline)
            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var panel: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.title).font(.caption.bold())
                    Text(data.subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(Formatters.cost(data.totalCost))
                    .font(.system(.body, design: .rounded).bold())
            }
            VStack(spacing: 4) {
                row("Input",       tokens: data.inputTokens,      cost: data.inputCost)
                row("Output",      tokens: data.outputTokens,     cost: data.outputCost)
                row("Cache write", tokens: data.cacheWriteTokens, cost: data.cacheWriteCost)
                row("Cache read",  tokens: data.cacheReadTokens,  cost: data.cacheReadCost)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func row(_ label: String, tokens: Int, cost: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(Formatters.tokensCompact(tokens))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(Formatters.cost(cost))
                .font(.caption.monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
    }
}
