import AppKit
import SwiftUI

enum BurnVersion {
    static let current = "1.13.1"
}

@main
struct BurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                service: appDelegate.service,
                settings: appDelegate.settings,
                registry: appDelegate.registry
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
        guard let url = BurnResources.bundle.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "Burn")
                ?? NSImage(size: NSSize(width: 18, height: 18))
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    lazy var service = UsageService(settings: settings)
    lazy var codexService = CodexUsageService()
    // Codex only reports quota while it runs, so Limits reuses the snapshot the Codex tab already parsed.
    lazy var limitsService = LimitsService(rolloutLimits: { [weak self] in self?.codexService.response.rateLimits })
    lazy var registry: ExtensionRegistry = {
        let r = ExtensionRegistry()
        r.register(UsageExtension(service: service, settings: settings))
        r.register(CodexExtension(service: codexService, settings: settings))
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
        registry.startAutoRefresh(intervalMinutes: settings.refreshIntervalMinutes)
    }
}
