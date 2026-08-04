import SwiftUI

struct EmberSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isActive = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : Ember.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isActive ? Ember.accent.opacity(0.26) : .clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
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

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Ember.accent : Color.white.opacity(0.16))
                Circle()
                    .fill(isOn ? Ember.surface : Color.white.opacity(0.78))
                    .frame(width: 15, height: 15)
                    .padding(2)
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
                    .foregroundStyle(.white)
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
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
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
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Ember.accent.opacity(0.16), lineWidth: 1)
        )
    }
}
