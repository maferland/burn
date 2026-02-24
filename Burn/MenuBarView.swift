import AppKit
import SwiftUI

struct MenuBarView: View {
    let service: UsageService
    let settings: SettingsStore
    @State private var showSettings = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            heroSection
            Divider()
            chartSection
            Divider()
            monthSection
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
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(nsImage: MenuBarLabel.loadMenuBarIcon())
                .resizable()
                .frame(width: 20, height: 20)
            Text("Burn")
                .font(.headline)
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var heroSection: some View {
        VStack(spacing: 4) {
            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(formatCost(service.usageData.todayCost))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Today's spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 Days")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            if service.usageData.last7Days.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                BarChartView(days: service.usageData.last7Days)
                    .frame(height: 80)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 8)
    }

    private var monthSection: some View {
        HStack {
            Text("This Month")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatCost(service.usageData.currentMonthTotal))
                .font(.system(.body, design: .rounded).bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerSection: some View {
        HStack {
            Text(lastRefreshText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                service.refresh()
            } label: {
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Refresh interval")
                    .font(.caption)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.refreshIntervalMinutes },
                    set: { newValue in
                        settings.refreshIntervalMinutes = newValue
                        service.restartAutoRefresh()
                    }
                )) {
                    ForEach(SettingsStore.availableIntervals, id: \.self) { interval in
                        Text("\(interval) min").tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }

            HStack {
                Text("Menu bar")
                    .font(.caption)
                Spacer()
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

            HStack {
                Text("Start at Login")
                    .font(.caption)
                Spacer()
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
    }

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Label("Quit", systemImage: "xmark.circle")
                Spacer()
                Text("\u{2318}Q")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(MenuButtonStyle())
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var versionLabel: some View {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            Text(version)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Helpers

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }

    private var lastRefreshText: String {
        let date = service.usageData.lastRefreshDate
        guard date != .distantPast else { return "Never refreshed" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: date))"
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
