import SwiftUI

struct EmberSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isActive = option.value == selection
                Button { withAnimation(EmberMotion.pill) { selection = option.value } } label: {
                    Text(option.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isActive ? Ember.primary : Ember.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            // Same slide as the tab strip, so both 3-ways read as one control.
                            if isActive {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Ember.accent.opacity(0.26))
                                    .matchedGeometryEffect(id: "segment", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(2)
        .background(Ember.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct EmberToggle: View {
    @Binding var isOn: Bool

    /// The knob slides on an offset. Swapping the stack's alignment made it teleport instead.
    private var knobOffset: CGFloat { isOn ? 15 : 2 }

    var body: some View {
        Button { withAnimation(EmberMotion.pill) { isOn.toggle() } } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Ember.accent : Ember.fill(0.16))
                Circle()
                    .fill(isOn ? Ember.surface : Ember.fill(0.78))
                    .frame(width: 15, height: 15)
                    .offset(x: knobOffset)
            }
            .frame(width: 32, height: 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

struct EmberSettingRow<Content: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ember.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.label)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            content()
        }
    }
}

/// Inline configuration block under an enabled extension.
struct EmberConfigCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 6) {
            content()
        }
        .padding(10)
        .background(Ember.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct EmberFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .frame(width: 58, alignment: .leading)
            content()
                .font(.system(size: 11))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Ember.recess(0.35), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Ember.accent.opacity(0.16), lineWidth: 1)
                )
        }
    }
}

struct EmberStoredBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Ember.accent)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Ember.recess(0.35), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Ember.accent.opacity(0.16), lineWidth: 1)
        )
    }
}

/// One of the three Today/Week/Month tiles on the PR tab. Selecting a card both scopes the list
/// and sets what the hero above reads — the card row replaced the old segmented pill (Turn 11).
struct EmberScopeCard: View {
    let label: String
    let count: Int
    let costPerPR: Double?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Ember.primary : Ember.caption)
                Text("\(count)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(isSelected ? Ember.primary : Ember.text(0.7))
                    .monospacedDigit()
                Text(costPerPR.map { "\(Formatters.costRounded($0))/PR" } ?? "—")
                    .font(.system(size: 9.5))
                    .foregroundStyle(isSelected ? Ember.text(0.7) : Ember.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? Ember.accent.opacity(0.14) : Ember.fill(0.04),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Ember.accent.opacity(0.5) : Ember.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
