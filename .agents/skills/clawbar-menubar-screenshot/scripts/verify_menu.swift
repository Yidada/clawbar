import AppKit
import ApplicationServices
import Foundation

struct VerifyConfig {
    let appName: String
    let itemTitle: String
    let expectedTitles: [String]
    let timeout: TimeInterval
}

enum VerifyError: Error, LocalizedError {
    case accessibilityUnavailable
    case appNotRunning(String)
    case itemNotFound(String, String)
    case menuNotFound(String)
    case missingExpectedTitles([String], [String])

    var errorDescription: String? {
        switch self {
        case .accessibilityUnavailable:
            "Accessibility permission is required to inspect the Clawbar menu."
        case let .appNotRunning(appName):
            "App is not running: \(appName)"
        case let .itemNotFound(appName, itemTitle):
            "Could not find menu bar item '\(itemTitle)' in app '\(appName)'."
        case let .menuNotFound(appName):
            "Could not find an open menu for app '\(appName)'."
        case let .missingExpectedTitles(missing, available):
            "Missing expected menu titles: \(missing.joined(separator: ", ")). Available titles: \(available.joined(separator: " | "))"
        }
    }
}

func parseConfig() -> VerifyConfig {
    var appName = "Clawbar"
    var itemTitle = "Clawbar"
    var expectedTitles: [String] = []
    var timeout: TimeInterval = 2

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--app-name":
            if let value = iterator.next() { appName = value }
        case "--item-title":
            if let value = iterator.next() { itemTitle = value }
        case "--expect":
            if let value = iterator.next() { expectedTitles.append(value) }
        case "--timeout":
            if let value = iterator.next(), let parsed = TimeInterval(value) {
                timeout = parsed
            }
        default:
            break
        }
    }

    return VerifyConfig(
        appName: appName,
        itemTitle: itemTitle,
        expectedTitles: expectedTitles,
        timeout: timeout
    )
}

func attributeValue(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else { return nil }
    return value
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

func menuItems(for statusItem: AXUIElement) -> [String] {
    guard let children = attributeValue(statusItem, kAXChildrenAttribute as String) as? [AXUIElement] else {
        return []
    }

    let menus = children.filter {
        (attributeValue($0, kAXRoleAttribute as String) as? String) == kAXMenuRole as String
    }

    for menu in menus {
        if let items = attributeValue(menu, kAXChildrenAttribute as String) as? [AXUIElement] {
            let titles = items.compactMap { attributeValue($0, kAXTitleAttribute as String) as? String }
            if !titles.isEmpty {
                return titles
            }
        }
    }

    return []
}

func verifyMenu(config: VerifyConfig) throws {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw VerifyError.accessibilityUnavailable
    }

    let runningApps = NSWorkspace.shared.runningApplications
        .filter { $0.localizedName == config.appName }

    guard !runningApps.isEmpty else {
        throw VerifyError.appNotRunning(config.appName)
    }

    let deadline = Date().addingTimeInterval(config.timeout)
    var lastTitles: [String] = []
    var sawMatchingItem = false

    while Date() < deadline {
        for app in runningApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let item = findStatusItem(in: appElement, title: config.itemTitle) else {
                continue
            }

            sawMatchingItem = true
            let titles = menuItems(for: item)
            if titles.isEmpty {
                continue
            }

            lastTitles = titles
            let missing = config.expectedTitles.filter { !titles.contains($0) }
            if missing.isEmpty {
                for title in titles {
                    print(title)
                }
                return
            }
        }

        Thread.sleep(forTimeInterval: 0.05)
    }

    guard sawMatchingItem else {
        throw VerifyError.itemNotFound(config.appName, config.itemTitle)
    }

    guard !lastTitles.isEmpty else {
        throw VerifyError.menuNotFound(config.appName)
    }

    let missing = config.expectedTitles.filter { !lastTitles.contains($0) }
    throw VerifyError.missingExpectedTitles(missing, lastTitles)
}

do {
    try verifyMenu(config: parseConfig())
} catch {
    fputs((error.localizedDescription + "\n"), stderr)
    exit(1)
}
