import AppKit
import SwiftUI

enum BurnVersion {
    static let current = "1.9.0"
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
        let segments = registry.enabledExtensions.compactMap { $0.menuBarSegment() }
        if segments.isEmpty {
            Image(nsImage: Self.loadMenuBarIcon())
        } else {
            HStack(spacing: 4) {
                ForEach(0..<segments.count, id: \.self) { i in
                    segments[i]
                    if i < segments.count - 1 {
                        Text("|").foregroundStyle(.tertiary)
                    }
                }
            }
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
    lazy var registry: ExtensionRegistry = {
        let r = ExtensionRegistry()
        r.register(UsageExtension(service: service, settings: settings))
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
        _ = registry  // force lazy init so the registry is populated before MenuBarExtra renders
        service.startAutoRefresh()
    }
}
