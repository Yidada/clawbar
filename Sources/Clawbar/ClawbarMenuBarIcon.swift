import AppKit

enum ClawbarMenuBarIcon {
    private static let logicalSize = NSSize(width: 18, height: 18)
    private static let resourceName1x = "ClawbarMenuBarTemplate18"
    private static let resourceName2x = "ClawbarMenuBarTemplate36"
    private static let fallbackSymbolName = "hand.wave.fill"

    /// Finds the SPM resource bundle in both packaged `.app` and `swift run` contexts.
    ///
    /// SPM's generated `Bundle.module` uses `Bundle.main.bundleURL` which resolves to
    /// the `.app` root directory. macOS codesign forbids placing bundles at the app root
    /// ("unsealed contents"), so the packaging script copies them to `Contents/Resources/`.
    /// This helper checks `Bundle.main.resourceURL` (Contents/Resources/) first, then
    /// falls back to `Bundle.main.bundleURL` (works for `swift run` where SPM places
    /// the bundle next to the executable).
    private static let resourceBundle: Bundle? = {
        let bundleName = "clawbar_Clawbar.bundle"
        let searchURLs: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for case let base? in searchURLs {
            let url = base.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }()

    @MainActor
    static var templateImage: NSImage {
        if let image = loadTemplateImage() {
            return image
        }

        let fallback = NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: "Clawbar"
        ) ?? NSImage(size: logicalSize)
        fallback.isTemplate = true
        return fallback
    }

    @MainActor
    private static func loadTemplateImage() -> NSImage? {
        let image = NSImage(size: logicalSize)
        var hasRepresentation = false

        if let representation = loadRepresentation(named: resourceName1x) {
            representation.size = logicalSize
            image.addRepresentation(representation)
            hasRepresentation = true
        }

        if let representation = loadRepresentation(named: resourceName2x) {
            representation.size = logicalSize
            image.addRepresentation(representation)
            hasRepresentation = true
        }

        guard hasRepresentation else {
            return nil
        }

        image.size = logicalSize
        image.isTemplate = true
        return image
    }

    private static func loadRepresentation(named resourceName: String) -> NSBitmapImageRep? {
        guard let url = resourceBundle?.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImageRep(contentsOf: url) as? NSBitmapImageRep
    }
}
