import SwiftUI

/// Add or edit one forge. The token is write-only: it goes to the Keychain and is never read back.
struct HostDetailView: View {
    @State private var editor: HostEditor
    private let onClose: () -> Void

    @FocusState private var hostFocused: Bool

    init(ext: PullRequestExtension, config: GitHostConfig, isNew: Bool, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _editor = State(initialValue: HostEditor(
            store: ext.hostStore,
            config: config,
            isNew: isNew,
            onCommit: { [weak ext] savedId in
                ext?.lastSavedHostId = savedId
                ext?.refresh()
            }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            fields
            Spacer(minLength: 12)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: onClose) {
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

            Text(editor.isNew ? "Add host" : editor.config.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if !editor.isNew {
                removeButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var removeButton: some View {
        Button {
            if editor.removeTapped() {
                onClose()
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { editor.cancelRemove() }
                }
            }
        } label: {
            Text(editor.confirmingRemove ? "Confirm remove?" : "Remove")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(editor.confirmingRemove ? Ember.dangerBright : Ember.danger)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: editor.confirmingRemove)
        .pointingHandCursor()
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(
                title: "Host URL",
                caption: editor.hostError ?? "Any GitHub-compatible host — Forgejo, Gitea, GHES, github.com.",
                isError: editor.hostError != nil
            ) {
                TextField("git.example.com", text: $editor.config.host)
                    .focused($hostFocused)
                    .onChange(of: hostFocused) { _, focused in
                        if !focused { editor.validateHost() }
                    }
                    .onChange(of: editor.config.host) { _, _ in editor.hostDidChange() }
            }

            field(
                title: "Repo owner",
                caption: editor.config.usesGitHubCLI
                    ? "The org or user that owns the repos. Leave empty for all of them."
                    : "The org or user that owns the repos, not your username."
            ) {
                TextField(editor.config.usesGitHubCLI ? "all" : "acme", text: $editor.config.org)
            }

            tokenSection
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var tokenSection: some View {
        switch editor.tokenState {
        case .cliManaged:
            labelled("Access token") {
                pill(icon: "terminal", text: "Authenticated via gh CLI", filled: false)
            }
        case .saved:
            labelled("Access token") {
                pill(icon: "checkmark", text: "Saved in Keychain", filled: true) {
                    Button("Replace") { editor.beginReplacingToken() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.accent)
                        .pointingHandCursor()
                }
            }
        case .entering:
            field(title: "Access token", caption: "Needs the read:issue scope.") {
                SecureField("paste token", text: $editor.tokenInput)
            }
        }
    }

    private func pill(
        icon: String, text: String, filled: Bool, @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: icon == "checkmark" ? 9 : 10, weight: .bold))
                .foregroundStyle(Ember.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Ember.caption)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            filled ? Ember.accent.opacity(0.08) : Ember.recess(0.3),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Ember.accent.opacity(filled ? 0.3 : 0.18), lineWidth: 1)
        )
    }

    private func field(
        title: String, caption: String?, isError: Bool = false, @ViewBuilder content: () -> some View
    ) -> some View {
        labelled(title) {
            VStack(alignment: .leading, spacing: 5) {
                content()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Ember.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Ember.recess(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isError ? Ember.danger.opacity(0.7) : Ember.accent.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isError ? Ember.danger : Ember.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Ember.label)
            content()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Cancel", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.caption)
                .pointingHandCursor()

            Button {
                if editor.save() { onClose() }
            } label: {
                Text("Save")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Ember.onAccent)
                    .frame(width: 62, height: 26)
                    .background(Ember.accent, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editor.canSave)
            .opacity(editor.canSave ? 1 : 0.4)
            .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
}
