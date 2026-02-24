import Foundation

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
}
