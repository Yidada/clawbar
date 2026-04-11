import AppKit

enum ClawbarMenuBarIcon {
    private static let logicalSize = NSSize(width: 18, height: 18)
    private static let resourceName1x = "ClawbarMenuBarTemplate18"
    private static let resourceName2x = "ClawbarMenuBarTemplate36"
    private static let fallbackSymbolName = "hand.wave.fill"

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
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImageRep(contentsOf: url) as? NSBitmapImageRep
    }
}
