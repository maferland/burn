import SwiftUI

/// The same drill-in shape the host detail screen uses, pointed at a provider instead of a forge.
struct ProviderDetailView: View {
    let store: ProviderStore
    let provider: Provider
    var onChange: () -> Void = {}

    @Environment(\.burnPopDetail) private var popDetail

    @State private var homePath: String = ""
    @State private var confirmingDisconnect = false
    @FocusState private var pathFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.isConnected(provider) {
                fields
            } else {
                notConnected
            }
            Spacer(minLength: 12)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { homePath = store.settings[provider.rawValue]?.homeOverride ?? "" }
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

            Circle().fill(provider.accent).frame(width: 7, height: 7)
            Text(provider.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.primary)
            Spacer(minLength: 8)
            if store.isConnected(provider) { disconnectButton }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Inline confirm rather than a system alert, matching every other destructive action here.
    private var disconnectButton: some View {
        Button {
            if confirmingDisconnect {
                store.disconnect(provider)
                onChange()
                popDetail()
            } else {
                withAnimation(.easeOut(duration: 0.12)) { confirmingDisconnect = true }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { confirmingDisconnect = false }
                }
            }
        } label: {
            Text(confirmingDisconnect ? "Confirm disconnect?" : "Disconnect")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(confirmingDisconnect ? Ember.dangerBright : Ember.danger)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 13) {
            labelled("Data source") {
                VStack(alignment: .leading, spacing: 5) {
                    TextField(provider.defaultHome.path, text: $homePath)
                        .focused($pathFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Ember.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Ember.recess(0.3), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(sourceBorder, lineWidth: 1)
                        )
                        .onChange(of: pathFocused) { _, focused in
                            guard !focused else { return }
                            store.setHome(provider, path: homePath)
                            onChange()
                        }
                    Text(sourceCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(store.isDetectable(provider) ? Ember.label : Ember.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            labelled("Plan & cap") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(planLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ember.primary)
                        Text("Read from the account this login belongs to")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Ember.text(0.4))
                    }
                    Spacer(minLength: 6)
                }
            }

            HStack(spacing: 10) {
                Text("Include in \"All providers\" total")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ember.primary)
                Spacer(minLength: 8)
                EmberToggle(isOn: Binding(
                    get: { store.includesInTotal(provider) },
                    set: {
                        store.setIncludedInTotal(provider, $0)
                        onChange()
                    }
                ))
            }
        }
        .padding(.horizontal, 16)
    }

    private var notConnected: some View {
        EmberEmptyState(
            title: "\(provider.displayName) isn't connected",
            detail: store.isDetectable(provider)
                ? "Its logs are on this machine and ready to read."
                : "Sign in with the \(provider.displayName) CLI first, then connect it here.",
            action: (label: "Connect", perform: {
                store.connect(provider)
                onChange()
            })
        )
    }

    private var sourceBorder: Color {
        store.isDetectable(provider) ? Ember.accent.opacity(0.18) : Ember.danger.opacity(0.7)
    }

    private var sourceCaption: String {
        guard store.isDetectable(provider) else {
            return "No signed-in \(provider.displayName) login here. Set \(provider.homeEnvironmentVariable) or point this at the right folder."
        }
        return "Leave empty for \(provider.defaultHome.path). Set it when the CLI lives elsewhere."
    }

    private var planLabel: String {
        let identity = LimitsAccountStore.identity(
            provider: provider, home: store.home(for: provider), isDefaultHome: true
        )
        return identity.planLabel ?? identity.email ?? "Not reported"
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Ember.text(0.42))
            content()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Close", action: popDetail)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.caption)
                .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }
}
