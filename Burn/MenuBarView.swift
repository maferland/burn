import AppKit
import SwiftUI

struct MenuBarView: View {
    let service: UsageService
    let settings: SettingsStore
    let registry: ExtensionRegistry

    @State private var showSettings = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        let enabled = registry.enabledExtensions
        let showsTabBar = enabled.count >= 2

        return VStack(spacing: 0) {
            if showsTabBar {
                tabBar(enabled: enabled)
                Divider()
            }
            activeTabContent(enabled: enabled)
                .environment(\.burnTabBarVisible, showsTabBar)

            Divider()
            footerSection
            Divider()

            VStack(spacing: 0) {
                settingsSection
                Divider()
            }
            .frame(maxHeight: showSettings ? .infinity : 0)
            .clipped()

            supportSection
            Divider()
            quitSection
            versionLabel
        }
        .frame(width: 300)
        .environment(\.openBurnSettings, { showSettings.toggle() })
        .onAppear {
            showSettings = false
        }
    }

    private func tabBar(enabled: [any BurnExtension]) -> some View {
        HStack(spacing: 6) {
            ForEach(enabled, id: \.id) { ext in
                tabChip(ext: ext, isActive: ext.id == (registry.activeTabId ?? enabled.first?.id))
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gear").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tabChip(ext: any BurnExtension, isActive: Bool) -> some View {
        Button {
            registry.activeTabId = ext.id
        } label: {
            Text(ext.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    @ViewBuilder
    private func activeTabContent(enabled: [any BurnExtension]) -> some View {
        if let active = enabled.first(where: { $0.id == registry.activeTabId }) ?? enabled.first {
            active.popoverTab()
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No extensions enabled")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open settings") { showSettings = true }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Chrome

    private var footerSection: some View {
        HStack {
            Text(Formatters.relativeTime(service.usageData.lastRefreshDate))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                registry.refreshAll()
            } label: {
                if service.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsRow("Refresh interval") {
                Picker("", selection: Binding(
                    get: { settings.refreshIntervalMinutes },
                    set: { newValue in
                        settings.refreshIntervalMinutes = newValue
                        registry.restartAutoRefresh(intervalMinutes: newValue)
                    }
                )) {
                    ForEach(SettingsStore.availableIntervals, id: \.self) { interval in
                        Text("\(interval) min").tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }

            settingsRow("Menu bar") {
                Picker("", selection: Binding(
                    get: { settings.menuBarDisplay },
                    set: { settings.menuBarDisplay = $0 }
                )) {
                    Text("Icon").tag(MenuBarDisplay.icon)
                    Text("Amount").tag(MenuBarDisplay.amount)
                    Text("Both").tag(MenuBarDisplay.both)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            settingsRow("Display") {
                Picker("", selection: Binding(
                    get: { settings.displayMode },
                    set: { settings.displayMode = $0 }
                )) {
                    Text("Cost").tag(DisplayMode.cost)
                    Text("Tokens").tag(DisplayMode.tokens)
                    Text("Both").tag(DisplayMode.both)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            settingsRow("Start at Login") {
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            LaunchAtLogin.enable()
                        } else {
                            LaunchAtLogin.disable()
                        }
                    }
            }

            if !registry.extensions.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Extensions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(registry.orderedExtensions, id: \.id) { ext in
                    settingsRow(ext.displayName) {
                        Toggle("", isOn: Binding(
                            get: { registry.isEnabled(ext.id) },
                            set: { registry.setEnabled(ext.id, $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    if registry.isEnabled(ext.id), let sub = ext.settingsView() {
                        sub
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            content()
        }
    }

    private var supportSection: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/maferland")!)
        } label: {
            HStack {
                Label("Support", systemImage: "heart")
                Spacer()
                Text("☕")
            }
        }
        .buttonStyle(MenuButtonStyle())
        .pointingHandCursor()
    }

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Label("Quit", systemImage: "xmark.circle")
                Spacer()
                Text("\u{2318}Q").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(MenuButtonStyle())
        .keyboardShortcut("q")
        .pointingHandCursor()
    }

    private var versionLabel: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? BurnVersion.current
        return Text(version)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 6)
    }
}

struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
    }
}
