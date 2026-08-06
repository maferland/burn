import SwiftUI

/// Connecting is explicit. Detection only decides whether a row promises to work.
struct ProviderConnectView: View {
    let store: ProviderStore
    var onChange: () -> Void = {}

    @Environment(\.burnPopDetail) private var popDetail

    @State private var hovered: Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.connectable.isEmpty {
                EmberEmptyState(
                    title: "Everything is connected",
                    detail: "More providers arrive as their CLIs start reporting usage locally."
                )
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(store.connectable) { provider in
                        row(provider)
                    }
                    comingSoon
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: popDetail) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ember.text(0.5))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .pointingHandCursor()

            Text("Connect a provider")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func row(_ provider: Provider) -> some View {
        let ready = store.isDetectable(provider)
        return Button {
            store.connect(provider)
            onChange()
            popDetail()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Ember.text(ready ? 0.4 : 0.25), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Ember.primary)
                    Text(ready
                        ? provider.sourceDescription
                        : "Not signed in yet. Connect anyway and point it at a folder.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.text(0.42))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("Connect")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ember.accent)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(
                hovered == provider ? Ember.accent.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(EmberMotion.hover) {
                hovered = hovering ? provider : (hovered == provider ? nil : hovered)
            }
        }
    }

    /// Named rather than hidden, so the shape of what's coming is visible without a roadmap page.
    private var comingSoon: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Ember.text(0.25), lineWidth: 1.5)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gemini CLI")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Ember.text(0.6))
                Text("Coming soon")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Ember.text(0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
    }
}
