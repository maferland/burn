import SwiftUI

@MainActor
struct SettingsPanel: View {
    let settings: SettingsStore
    let registry: ExtensionRegistry
    let onClose: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            general
            if !registry.configurableExtensions.isEmpty {
                Rectangle()
                    .fill(Ember.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                extensions
            }
        }
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

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var general: some View {
        VStack(spacing: 13) {
            EmberSettingRow(label: "Menu bar shows", detail: "Icon, amount, or both") {
                EmberSegmented(
                    options: [("Icon", MenuBarDisplay.icon), ("$", .amount), ("Both", .both)],
                    selection: Binding(
                        get: { settings.menuBarDisplay },
                        set: { settings.menuBarDisplay = $0 }
                    )
                )
            }
            EmberSettingRow(label: "Measure in", detail: "Dollars, tokens, or both") {
                EmberSegmented(
                    options: [("Cost", DisplayMode.cost), ("Tokens", .tokens), ("Both", .both)],
                    selection: Binding(
                        get: { settings.displayMode },
                        set: { settings.displayMode = $0 }
                    )
                )
            }
            EmberSettingRow(label: "Refresh every") {
                Menu {
                    ForEach(SettingsStore.availableIntervals, id: \.self) { interval in
                        Button("\(interval) min") {
                            settings.refreshIntervalMinutes = interval
                            registry.restartAutoRefresh(intervalMinutes: interval)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("\(settings.refreshIntervalMinutes) min")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Ember.label)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Ember.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
            }
            EmberSettingRow(label: "Start at login") {
                EmberToggle(isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        newValue ? LaunchAtLogin.enable() : LaunchAtLogin.disable()
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var extensions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extensions")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Ember.label)

            ForEach(registry.configurableExtensions, id: \.id) { ext in
                EmberSettingRow(label: ext.displayName, detail: ext.settingsSubtitle) {
                    EmberToggle(isOn: Binding(
                        get: { registry.isEnabled(ext.id) },
                        set: { registry.setEnabled(ext.id, $0) }
                    ))
                }
                if registry.isEnabled(ext.id), let sub = ext.settingsView() {
                    sub
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 16)
    }
}
