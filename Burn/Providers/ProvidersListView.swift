import SwiftUI

/// Settings → Providers. One row per provider, connected or not, so adding one is discoverable
/// without a separate catalog screen.
struct ProvidersListView: View {
    let store: ProviderStore
    var onChange: () -> Void = {}

    @Environment(\.burnPushDetail) private var pushDetail
    @Environment(\.burnPopDetail) private var popDetail

    @State private var hovered: Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Provider.allCases) { provider in
                    row(provider)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)

            Rectangle()
                .fill(Ember.accent.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            connectRow
            Spacer(minLength: 8)
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

            Text("Providers")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func row(_ provider: Provider) -> some View {
        let connected = store.isConnected(provider)
        return Button {
            open(provider)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor(for: provider))
                    .strokeBorder(connected ? .clear : Ember.text(0.25), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.system(size: 12.5, weight: connected ? .semibold : .medium))
                        .foregroundStyle(connected ? Ember.primary : Ember.text(0.5))
                    Text(subtitle(provider))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.text(connected ? 0.42 : 0.35))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ember.text(hovered == provider ? 0.5 : 0.35))
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
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

    /// One dot per row: green once it reads, red when connected but unreachable, hollow otherwise.
    /// Health used to get a second dot of its own; the subtitle already names the problem in words.
    private func dotColor(for provider: Provider) -> Color {
        switch store.health(provider) {
        case .ok:           return Ember.healthy
        case .unreachable:  return Ember.accentDeep
        case .disconnected: return .clear
        }
    }

    private func subtitle(_ provider: Provider) -> String {
        guard store.isConnected(provider) else { return "Not connected" }
        var parts = [provider.sourceDescription]
        let identity = LimitsAccountStore.identity(
            provider: provider, home: store.home(for: provider), isDefaultHome: true
        )
        if let plan = identity.planLabel { parts.append(plan) }
        if let caption = store.health(provider).caption { parts.append(caption) }
        return parts.joined(separator: " · ")
    }

    private var connectRow: some View {
        Button {
            pushDetail(AnyView(ProviderConnectView(store: store, onChange: onChange)))
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ember.accent)
                    .frame(width: 14, height: 14)
                    .background(Ember.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                Text("Connect a provider")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Ember.accent.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func open(_ provider: Provider) {
        pushDetail(AnyView(
            ProviderDetailView(store: store, provider: provider, onChange: onChange)
        ))
    }
}
