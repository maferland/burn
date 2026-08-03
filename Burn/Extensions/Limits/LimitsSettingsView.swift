import SwiftUI

struct LimitsSettingsView: View {
    let ext: LimitsExtension

    @State private var provider: LimitsProvider = .claude
    @State private var labelInput = ""
    @State private var pathInput = ""

    private var store: LimitsAccountStore { ext.service.store }

    var body: some View {
        EmberConfigCard {
            EmberSettingRow(label: "Show in menu bar", detail: "Least headroom across accounts") {
                EmberToggle(isOn: Binding(
                    get: { ext.showsInMenuBar },
                    set: { ext.showsInMenuBar = $0 }
                ))
            }

            ForEach(store.accounts) { account in
                accountRow(account)
            }

            EmberFieldRow(label: "Add") {
                TextField("label", text: $labelInput)
            }
            EmberFieldRow(label: "Home") {
                TextField(provider.homeExample, text: $pathInput)
                    .onSubmit(commit)
            }
            HStack(spacing: 8) {
                EmberSegmented(
                    options: [("Claude", LimitsProvider.claude), ("Codex", .codex)],
                    selection: $provider
                )
                Spacer(minLength: 4)
                Button("Add account", action: commit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pathInput.isEmpty ? Ember.label : Ember.accent)
                    .disabled(pathInput.isEmpty)
                    .pointingHandCursor()
            }
        }
    }

    private func accountRow(_ account: LimitsAccount) -> some View {
        HStack(spacing: 8) {
            Text(account.provider.displayName)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .frame(width: 58, alignment: .leading)
            Text(account.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if account.isAutoDetected {
                Text("detected")
                    .font(.system(size: 10))
                    .foregroundStyle(Ember.label)
            } else {
                Button {
                    store.remove(id: account.id)
                    ext.service.refresh(force: true)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Ember.text(0.45))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(account.label)")
                .pointingHandCursor()
            }
        }
    }

    private func commit() {
        guard !pathInput.isEmpty else { return }
        store.add(provider: provider, label: labelInput, homePath: pathInput)
        labelInput = ""
        pathInput = ""
        ext.service.refresh(force: true)
    }
}
