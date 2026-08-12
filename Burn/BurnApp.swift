import AppKit
import SwiftUI

@main
struct BurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                service: appDelegate.service,
                settings: appDelegate.settings,
                registry: appDelegate.registry,
                providers: appDelegate.providers
            )
        } label: {
            MenuBarLabel(registry: appDelegate.registry)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let registry: ExtensionRegistry

    var body: some View {
        let texts = registry.enabledExtensions.compactMap { $0.menuBarSegment() }
        if texts.isEmpty {
            Image(nsImage: Self.loadMenuBarIcon())
        } else {
            texts.dropFirst().reduce(texts[0]) { $0 + Text(" · ") + $1 }
        }
    }

    static func loadMenuBarIcon() -> NSImage {
        BurnResources.templateIcon(named: "MenuBarIcon", size: 18)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let providers = ProviderStore()
    lazy var service = UsageService(settings: settings)
    lazy var codexService = CodexUsageService()
    // Codex only reports quota while it runs, so Limits reuses the snapshot the Codex tab already parsed.
    lazy var limitsService = LimitsService(rolloutLimits: { [weak self] in self?.codexService.response.rateLimits })
    lazy var registry: ExtensionRegistry = {
        let r = ExtensionRegistry()
        r.register(UsageExtension(
            service: service, codexService: codexService, settings: settings, providers: providers
        ))
        // Codex lives inside Usage now, behind the provider chip. CodexExtension is kept, not
        // deleted: re-register it here to get the standalone tab back.
        r.register(LimitsExtension(service: limitsService))
        r.register(PullRequestExtension(usageService: service))
        return r
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let idx = CommandLine.arguments.firstIndex(of: "--screenshot") {
            let output = CommandLine.arguments.dropFirst(idx + 1).first ?? "burn-screenshot.png"
            ScreenshotGenerator.generate(outputPath: output)
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        settings.appearance.apply()
        registry.startAutoRefresh(intervalMinutes: settings.refreshIntervalMinutes)
    }
}
