import AppKit
import SwiftUI

@MainActor
struct MenuBarView: View {
    let service: UsageService
    let settings: SettingsStore
    let registry: ExtensionRegistry

    @State private var showSettings = ProcessInfo.processInfo.environment["BURN_SETTINGS"] != nil
    @State private var sessionID = UUID()

    var body: some View {
        let enabled = registry.enabledExtensions

        return VStack(spacing: 0) {
            if showSettings {
                SettingsPanel(settings: settings, registry: registry, onClose: { showSettings = false })
            } else if enabled.isEmpty {
                EmberEmptyState(
                    title: "No extensions enabled",
                    detail: "Turn one on to see something here.",
                    action: (label: "Open settings", perform: { showSettings = true })
                )
            } else {
                EmberStatusHeader(
                    status: activeExtension(enabled)?.statusLine(),
                    extensions: enabled,
                    activeId: activeExtension(enabled)?.id,
                    onSelect: { registry.activeTabId = $0 }
                )
                activeTabContent(enabled: enabled)
                    .environment(\.burnTabBarVisible, true)
                    .id("\(sessionID)-\(registry.activeTabId ?? "")")
            }

            EmberUtilityBar(
                updated: updatedLabel,
                isLoading: service.isLoading,
                onRefresh: { registry.refreshAll() },
                onSettings: { showSettings.toggle() }
            )
        }
        .frame(width: Ember.width)
        .background(Ember.surface)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .environment(\.openBurnSettings, { showSettings.toggle() })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow else { return }
            let className = String(describing: type(of: window))
            guard className.contains("MenuBarExtra") || className.contains("Popover") || className.contains("StatusBar") else { return }
            resetToHome(enabled: enabled)
        }
    }

    private var updatedLabel: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? BurnVersion.current
        // The bundle string already carries a "v" in some builds; don't double it.
        let version = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let refreshed = service.usageData.lastRefreshDate
        let stamp = refreshed == .distantPast ? "Never refreshed" : "Updated \(Formatters.clockTime(refreshed))"
        return "\(stamp) · v\(version)"
    }

    private func activeExtension(_ enabled: [any BurnExtension]) -> (any BurnExtension)? {
        enabled.first { $0.id == registry.activeTabId } ?? enabled.first
    }

    private func resetToHome(enabled: [any BurnExtension]) {
        showSettings = false
        if let first = enabled.first {
            registry.activeTabId = first.id
        }
        sessionID = UUID()
    }

    @ViewBuilder
    private func activeTabContent(enabled: [any BurnExtension]) -> some View {
        if let active = activeExtension(enabled) {
            active.popoverTab()
        }
    }
}
