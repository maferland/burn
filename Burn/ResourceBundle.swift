import AppKit

/// Custom resource bundle accessor that finds Burn_Burn.bundle in Contents/Resources/
/// (where macOS codesign requires it) instead of the app root (where SPM's generated
/// Bundle.module looks).
enum BurnResources {
    static let bundle: Bundle = {
        let bundleName = "Burn_Burn"

        // macOS .app: Contents/Resources/
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle")) {
            return bundle
        }

        // SPM default: alongside the executable
        if let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle")) {
            return bundle
        }

        fatalError("could not load resource bundle: \(bundleName).bundle")
    }()

    /// Loads a bundled PNG as a template image (macOS tints it per context) at the given point
    /// size. Shared by the menu bar label and the tab-strip glyphs.
    static func templateIcon(named name: String, size: CGFloat) -> NSImage {
        guard let url = bundle.url(forResource: "\(name)@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: name)
                ?? NSImage(size: NSSize(width: size, height: size))
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}
