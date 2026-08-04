import SwiftUI

/// Settings → Extensions → Limits: the accounts we read quota from, same list-and-drill-in as hosts.
struct LimitsSettingsView: View {
    let ext: LimitsExtension

    @Environment(\.burnPushDetail) private var pushDetail
    @Environment(\.burnPopDetail) private var popDetail

    @State private var hoveredId: String?

    private var store: LimitsAccountStore { ext.service.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EmberSettingRow(label: "Show in menu bar", detail: "Least headroom across accounts") {
                EmberToggle(isOn: Binding(
                    get: { ext.showsInMenuBar },
                    set: { ext.showsInMenuBar = $0 }
                ))
            }
            .padding(.bottom, 6)

            ForEach(store.accounts) { account in
                row(account)
            }
            addRow
        }
        .animation(.easeInOut(duration: 0.18), value: store.accounts)
    }

    private func row(_ account: LimitsAccount) -> some View {
        Button {
            guard !account.isAutoDetected else { return }
            open(account)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(Ember.accent).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(account))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ember.text(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if account.isAutoDetected {
                    Text("detected")
                        .font(.system(size: 10))
                        .foregroundStyle(Ember.label)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ember.text(hoveredId == account.id ? 0.5 : 0.35))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                hoveredId == account.id && !account.isAutoDetected
                    ? Ember.accent.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(account.isAutoDetected)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredId = hovering ? account.id : (hoveredId == account.id ? nil : hoveredId)
            }
        }
    }

    private func subtitle(_ account: LimitsAccount) -> String {
        let home = account.homePath ?? account.provider.defaultHome.path
        return "\(account.provider.displayName) · \((home as NSString).abbreviatingWithTildeInPath)"
    }

    private var addRow: some View {
        Button {
            open(nil)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ember.accent)
                    .frame(width: 16, height: 16)
                    .background(Ember.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                Text("Add account")
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

    private func open(_ account: LimitsAccount?) {
        pushDetail(AnyView(
            LimitsAccountDetailView(ext: ext, account: account, onClose: popDetail)
        ))
    }
}
