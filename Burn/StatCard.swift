import SwiftUI

struct StatCard: View {
    let label: String
    let value: String
    let subtitle: String?
    let isSelected: Bool
    let onTap: (() -> Void)?

    init(label: String, value: String, subtitle: String? = nil, isSelected: Bool = false, onTap: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .modifier(TapModifier(onTap: onTap))
    }

    private var background: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        }
        return AnyShapeStyle(.quaternary.opacity(0.4))
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
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TapModifier: ViewModifier {
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onTap {
            content
                .onTapGesture(perform: onTap)
                .pointingHandCursor()
        } else {
            content
        }
    }
}
