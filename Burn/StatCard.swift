import SwiftUI

struct StatCard: View {
    let label: String
    let value: String
    let subtitle: String?
    let onTap: (() -> Void)?

    init(label: String, value: String, subtitle: String? = nil, onTap: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.subtitle = subtitle
        self.onTap = onTap
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .pointingHandCursor()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
