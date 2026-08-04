import SwiftUI

/// Settings → Extensions → Pull requests: the list of connected forges, one row each.
struct HostsListView: View {
    let ext: PullRequestExtension

    @Environment(\.burnPushDetail) private var pushDetail
    @Environment(\.burnPopDetail) private var popDetail

    @State private var hoveredId: UUID?
    @State private var flashedId: UUID?

    private var store: GitHostStore { ext.hostStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.hosts.isEmpty {
                Text("Connect GitHub or a self-hosted Forgejo, Gitea or GHES instance to see PRs here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Ember.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            ForEach(store.hosts) { host in
                row(host)
            }
            addRow
        }
        .animation(.easeInOut(duration: 0.18), value: store.hosts)
        .onAppear {
            // Screenshot knob, same family as BURN_ACTIVE_TAB and BURN_SETTINGS.
            guard ProcessInfo.processInfo.environment["BURN_HOST_DETAIL"] != nil,
                  let last = store.hosts.last else { return }
            open(last)
        }
        .onChange(of: ext.lastSavedHostId) { _, saved in
            guard let saved else { return }
            flashedId = saved
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeOut(duration: 0.3)) { flashedId = nil }
            }
        }
    }

    private func row(_ host: GitHostConfig) -> some View {
        Button {
            open(host)
        } label: {
            HStack(spacing: 9) {
                statusDot(host)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(host))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.text(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ember.text(hoveredId == host.id ? 0.5 : 0.35))
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(background(for: host), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredId = hovering ? host.id : (hoveredId == host.id ? nil : hoveredId)
            }
        }
    }

    /// Filled dot means we can authenticate; a hollow ring means the row will fail until fixed.
    @ViewBuilder
    private func statusDot(_ host: GitHostConfig) -> some View {
        if host.usesGitHubCLI || store.hasToken(host) {
            Circle().fill(Ember.accent).frame(width: 7, height: 7)
        } else {
            Circle()
                .strokeBorder(Ember.accent.opacity(0.5), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }

    private func background(for host: GitHostConfig) -> Color {
        if flashedId == host.id { return Ember.accent.opacity(0.18) }
        return hoveredId == host.id ? Ember.accent.opacity(0.09) : .clear
    }

    private func subtitle(_ host: GitHostConfig) -> String {
        let org = host.org.trimmingCharacters(in: .whitespaces)
        let scope = org.isEmpty ? "all orgs" : org
        if host.usesGitHubCLI { return "\(scope) · via gh CLI" }
        return "\(scope) · \(store.hasToken(host) ? "token saved" : "no token")"
    }

    private var addRow: some View {
        Button {
            open(GitHostConfig(host: "", org: ""), isNew: true)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ember.accent)
                    .frame(width: 16, height: 16)
                    .background(Ember.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                Text("Add host")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func open(_ host: GitHostConfig, isNew: Bool = false) {
        pushDetail(AnyView(
            HostDetailView(ext: ext, config: host, isNew: isNew, onClose: popDetail)
        ))
    }
}
