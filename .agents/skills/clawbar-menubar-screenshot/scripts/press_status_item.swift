import AppKit
import ApplicationServices
import Foundation

struct Config {
    let appName: String
    let itemTitle: String
}

enum PressError: Error, LocalizedError {
    case accessibilityUnavailable
    case appNotRunning(String)
    case itemNotFound(String, String)
    case actionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityUnavailable:
            "Accessibility permission is required to press the Clawbar status item."
        case let .appNotRunning(appName):
            "App is not running: \(appName)"
        case let .itemNotFound(appName, itemTitle):
            "Could not find menu bar item '\(itemTitle)' in app '\(appName)'."
        case let .actionFailed(appName, error):
            "Failed to press menu bar item in \(appName): \(error.rawValue)"
        }
    }
}

func parseConfig() -> Config {
    var appName = "Clawbar"
    var itemTitle = "Clawbar"

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--app-name":
            if let value = iterator.next() { appName = value }
        case "--item-title":
            if let value = iterator.next() { itemTitle = value }
        default:
            break
        }
    }

    return Config(appName: appName, itemTitle: itemTitle)
}

func attributeValue(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else { return nil }
    return value
}

func cgPointValue(_ value: AnyObject?) -> CGPoint? {
    guard let value else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

func cgSizeValue(_ value: AnyObject?) -> CGSize? {
    guard let value else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

func centerPoint(of element: AXUIElement) -> CGPoint? {
    guard
        let origin = cgPointValue(attributeValue(element, kAXPositionAttribute as String)),
        let size = cgSizeValue(attributeValue(element, kAXSizeAttribute as String))
    else {
        return nil
    }

    return CGPoint(x: origin.x + (size.width / 2), y: origin.y + (size.height / 2))
}

func clickElementCenter(_ element: AXUIElement) -> Bool {
    guard let center = centerPoint(of: element) else { return false }

    guard
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left),
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
    else {
        return false
    }

    move.post(tap: .cghidEventTap)
    usleep(40_000)
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
    return true
}

func findStatusItem(in element: AXUIElement, title: String, depth: Int = 0) -> AXUIElement? {
    if depth > 6 { return nil }

    if let extras = attributeValue(element, kAXExtrasMenuBarAttribute as String) {
        let extrasElement = unsafeBitCast(extras, to: AXUIElement.self)
        if let found = findStatusItem(in: extrasElement, title: title, depth: depth + 1) {
            return found
        }
    }

    let role = attributeValue(element, kAXRoleAttribute as String) as? String
    let currentTitle = attributeValue(element, kAXTitleAttribute as String) as? String
    if role == kAXMenuBarItemRole as String, currentTitle == title {
        return element
    }

    if let children = attributeValue(element, kAXChildrenAttribute as String) as? [AXUIElement] {
        for child in children {
            if let found = findStatusItem(in: child, title: title, depth: depth + 1) {
                return found
            }
        }
    }

    return nil
}

func pressStatusItem(config: Config) throws {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw PressError.accessibilityUnavailable
    }

    let runningApps = NSWorkspace.shared.runningApplications
        .filter { $0.localizedName == config.appName }

    guard !runningApps.isEmpty else {
        throw PressError.appNotRunning(config.appName)
    }

    var sawMatchingItem = false

    for app in runningApps {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let item = findStatusItem(in: appElement, title: config.itemTitle) else {
            continue
        }

        sawMatchingItem = true
        let center = centerPoint(of: item)

        let error = AXUIElementPerformAction(item, kAXPressAction as CFString)
        if error == .success {
            if let center {
                print("\(Int(center.x.rounded())) \(Int(center.y.rounded()))")
            }
            return
        }

        if clickElementCenter(item) {
            if let center {
                print("\(Int(center.x.rounded())) \(Int(center.y.rounded()))")
            }
            return
        }
    }

    guard sawMatchingItem else {
        throw PressError.itemNotFound(config.appName, config.itemTitle)
    }

    throw PressError.actionFailed(config.appName, .cannotComplete)
}

do {
    try pressStatusItem(config: parseConfig())
} catch {
    fputs((error.localizedDescription + "\n"), stderr)
    exit(1)
}
