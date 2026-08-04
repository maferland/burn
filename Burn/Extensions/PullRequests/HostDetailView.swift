import SwiftUI

/// Add or edit one forge. The token is write-only: it goes to the Keychain and is never read back.
struct HostDetailView: View {
    let ext: PullRequestExtension
    let isNew: Bool
    let onClose: () -> Void

    @State private var config: GitHostConfig
    @State private var tokenInput = ""
    @State private var replacingToken = false
    @State private var hostError: String?
    @State private var confirmingRemove = false
    @State private var isSaving = false
    @FocusState private var hostFocused: Bool

    init(ext: PullRequestExtension, config: GitHostConfig, isNew: Bool, onClose: @escaping () -> Void) {
        self.ext = ext
        self.isNew = isNew
        self.onClose = onClose
        _config = State(initialValue: config)
        _replacingToken = State(initialValue: isNew)
    }

    private var store: GitHostStore { ext.hostStore }

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
            Button(action: close) {
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

            Text(isNew ? "Add host" : config.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if !isNew {
                removeButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Inline confirm rather than a system alert: an alert over a popover this size reads as a crash.
    private var removeButton: some View {
        Button {
            if confirmingRemove {
                store.remove(config.id)
                ext.refresh()
                close()
            } else {
                withAnimation(.easeOut(duration: 0.12)) { confirmingRemove = true }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.15)) { confirmingRemove = false }
                }
            }
        } label: {
            Text(confirmingRemove ? "Confirm remove?" : "Remove")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(confirmingRemove ? Ember.dangerBright : Ember.danger)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(
                title: "Host URL",
                caption: hostError ?? "Any GitHub-compatible host — Forgejo, Gitea, GHES, github.com.",
                isError: hostError != nil
            ) {
                TextField("git.example.com", text: $config.host)
                    .focused($hostFocused)
                    .onChange(of: hostFocused) { _, focused in
                        if !focused { validateHost() }
                    }
                    .onChange(of: config.host) { _, host in
                        config.kind = GitHostConfig.isGitHubDotCom(host) ? .github : .selfHosted
                        hostError = nil
                    }
            }

            field(title: "Org or user", caption: config.usesGitHubCLI ? "Leave empty for every org." : nil) {
                TextField(config.usesGitHubCLI ? "all" : "acme", text: $config.org)
            }

            tokenSection
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var tokenSection: some View {
        if config.usesGitHubCLI {
            labelled("Access token") {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Ember.accent)
                    Text("Authenticated via gh CLI")
                        .font(.system(size: 12))
                        .foregroundStyle(Ember.caption)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Ember.accent.opacity(0.18), lineWidth: 1)
                )
            }
        } else if store.hasToken(config), !replacingToken {
            labelled("Access token") {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ember.accent)
                    Text("Saved in Keychain")
                        .font(.system(size: 12))
                        .foregroundStyle(Ember.caption)
                    Spacer(minLength: 0)
                    Button("Replace") { replacingToken = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.accent)
                        .pointingHandCursor()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Ember.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Ember.accent.opacity(0.3), lineWidth: 1)
                )
            }
        } else {
            field(title: "Access token", caption: "Needs the read:issue scope.") {
                SecureField("paste token", text: $tokenInput)
            }
        }
    }

    private func field(
        title: String, caption: String?, isError: Bool = false, @ViewBuilder content: () -> some View
    ) -> some View {
        labelled(title) {
            VStack(alignment: .leading, spacing: 5) {
                content()
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
            Button("Cancel", action: close)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.caption)
                .pointingHandCursor()

            Button(action: save) {
                Group {
                    if isSaving {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    } else {
                        Text("Save").font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(Ember.onAccent)
                .frame(width: 62, height: 26)
                .background(Ember.accent, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!config.isSaveable || isSaving)
            .opacity(config.isSaveable ? 1 : 0.4)
            .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func validateHost() {
        let trimmed = config.host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let parsed = URL(string: withScheme)
        hostError = (parsed?.host?.contains(".") ?? false) ? nil : "That doesn't look like a host name."
    }

    private func save() {
        validateHost()
        guard hostError == nil, config.isSaveable else { return }
        isSaving = true
        config.host = config.host.trimmingCharacters(in: .whitespaces)
        config.org = config.org.trimmingCharacters(in: .whitespaces)
        store.upsert(config)
        if !config.usesGitHubCLI, !tokenInput.isEmpty {
            store.setToken(tokenInput, for: config)
        }
        ext.lastSavedHostId = config.id
        ext.refresh()
        isSaving = false
        close()
    }

    private func close() {
        onClose()
    }
}
