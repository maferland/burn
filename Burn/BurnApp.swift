import AppKit
import SwiftUI

@main
struct BurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: appDelegate.service, settings: appDelegate.settings)
        } label: {
            MenuBarLabel(service: appDelegate.service, settings: appDelegate.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let service: UsageService
    let settings: SettingsStore

    private var hasData: Bool {
        service.usageData.lastRefreshDate != .distantPast
    }

    private var menuBarIcon: some View {
        Image(nsImage: Self.loadMenuBarIcon())
    }

    var body: some View {
        if !hasData {
            menuBarIcon
        } else {
            let cost = service.usageData.todayCost
            let amount = String(format: "$%.2f", cost)

            switch settings.menuBarDisplay {
            case .icon:
                menuBarIcon
            case .amount:
                Text(amount)
            case .both:
                HStack(spacing: 4) {
                    menuBarIcon
                    Text(amount)
                }
            }
        }
    }

    static func loadMenuBarIcon() -> NSImage {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "Burn")
                ?? NSImage(size: NSSize(width: 18, height: 18))
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    lazy var service = UsageService(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        service.startAutoRefresh()
    }
}
