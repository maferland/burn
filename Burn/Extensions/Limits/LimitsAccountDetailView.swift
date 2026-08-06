import SwiftUI

/// Add or edit one extra login. Credentials stay where the CLI put them; this only stores a path.
struct LimitsAccountDetailView: View {
    @State private var editor: LimitsAccountEditor
    private let onClose: () -> Void

    @FocusState private var pathFocused: Bool

    init(ext: LimitsExtension, account: LimitsAccount?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _editor = State(initialValue: LimitsAccountEditor(
            store: ext.service.store,
            account: account,
            onCommit: { [weak ext] in ext?.service.refresh(force: true) }
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

            Text(editor.isNew ? "Add account" : (editor.existing?.label ?? "Account"))
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

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelled("Provider") {
                EmberSegmented(
                    options: [("Claude", Provider.claude), ("Codex", .codex)],
                    selection: $editor.provider
                )
            }

            field(
                title: "Config home",
                caption: editor.pathError
                    ?? "The \(editor.provider.homeEnvironmentVariable) this login uses.",
                isError: editor.pathError != nil
            ) {
                TextField(editor.provider.homeExample, text: $editor.homePath)
                    .focused($pathFocused)
                    .onChange(of: pathFocused) { _, focused in
                        if !focused { editor.validatePath() }
                    }
            }

            field(title: "Name", caption: "Optional. Defaults to the email found in that folder.") {
                TextField("personal", text: $editor.label)
            }
        }
        .padding(.horizontal, 16)
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
