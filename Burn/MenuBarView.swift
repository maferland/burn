import AppKit
import SwiftUI

@MainActor
struct MenuBarView: View {
    let service: UsageService
    let settings: SettingsStore
    let registry: ExtensionRegistry
    let providers: ProviderStore

    @State private var showSettings = ProcessInfo.processInfo.environment["BURN_SETTINGS"] != nil
    @State private var sessionID = UUID()
    @State private var detail: AnyView?

    var body: some View {
        let enabled = registry.enabledExtensions

        return VStack(spacing: 0) {
            if showSettings {
                if let detail {
                    detail
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SettingsPanel(
                        settings: settings, registry: registry,
                        providers: providers, onClose: closeSettings
                    )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            } else if enabled.isEmpty {
                EmberEmptyState(
                    title: "No extensions enabled",
                    detail: "Turn one on to see something here.",
                    action: (label: "Open settings", perform: { showSettings = true })
                )
            } else {
                EmberStatusHeader(
                    status: activeExtension(enabled)?.statusLine(),
                    state: activeExtension(enabled)?.state ?? .dormant,
                    extensions: enabled,
                    activeId: activeExtension(enabled)?.id,
                    onSelect: { registry.activeTabId = $0 }
                )
                activeTabContent(enabled: enabled)
                    .environment(\.burnTabBarVisible, true)
                    .id("\(sessionID)-\(registry.activeTabId ?? "")")
                    // Overlaps the pill slide slightly, so switching tabs doesn't feel sequential.
                    .transition(.opacity.animation(EmberMotion.crossfade))
            }

            EmberUtilityBar(
                updated: updatedLabel,
                isLoading: service.isLoading,
                signature: refreshSignature(enabled),
                onRefresh: { registry.refreshAll() },
                onSettings: { showSettings.toggle() }
            )
        }
        .frame(width: Ember.width)
        .background(Ember.surface)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .environment(\.openBurnSettings, { showSettings.toggle() })
        .environment(\.burnPushDetail, { view in
            withAnimation(.easeOut(duration: 0.22)) { detail = view }
        })
        .environment(\.burnPopDetail, {
            withAnimation(.easeOut(duration: 0.2)) { detail = nil }
        })
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

    /// What the refresh icon watches. The status line is the tab's own headline number.
    private func refreshSignature(_ enabled: [any BurnExtension]) -> String {
        activeExtension(enabled)?.statusLine() ?? ""
    }

    private func closeSettings() {
        detail = nil
        showSettings = false
    }

    private func resetToHome(enabled: [any BurnExtension]) {
        detail = nil
        showSettings = false
        if let first = enabled.first {
            registry.activeTabId = first.id
        }
        for ext in enabled { ext.resetBrowsing() }
        sessionID = UUID()
    }

    @ViewBuilder
    private func activeTabContent(enabled: [any BurnExtension]) -> some View {
        if let active = activeExtension(enabled) {
            active.popoverTab()
        }
    }
}
