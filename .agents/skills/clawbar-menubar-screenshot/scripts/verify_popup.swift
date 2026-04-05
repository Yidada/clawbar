import AppKit
import ApplicationServices
import Foundation

struct VerifyConfig {
    let appName: String
    let expectedTexts: [String]
    let timeout: TimeInterval
}

enum VerifyError: Error, LocalizedError {
    case accessibilityUnavailable
    case appNotRunning(String)
    case popupNotFound(String)
    case missingExpectedTexts([String], [String])

    var errorDescription: String? {
        switch self {
        case .accessibilityUnavailable:
            "Accessibility permission is required to inspect the Clawbar popup."
        case let .appNotRunning(appName):
            "App is not running: \(appName)"
        case let .popupNotFound(appName):
            "Could not find an open popup window for app '\(appName)'."
        case let .missingExpectedTexts(missing, available):
            "Missing expected popup text: \(missing.joined(separator: ", ")). Available text: \(available.joined(separator: " | "))"
        }
    }
}

func parseConfig() -> VerifyConfig {
    var appName = "Clawbar"
    var expectedTexts: [String] = []
    var timeout: TimeInterval = 2

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--app-name":
            if let value = iterator.next() { appName = value }
        case "--expect":
            if let value = iterator.next() { expectedTexts.append(value) }
        case "--timeout":
            if let value = iterator.next(), let parsed = TimeInterval(value) {
                timeout = parsed
            }
        default:
            break
        }
    }

    return VerifyConfig(appName: appName, expectedTexts: expectedTexts, timeout: timeout)
}

func attributeValue(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else { return nil }
    return value
}

func childElements(of element: AXUIElement) -> [AXUIElement] {
    let keys = [
        kAXChildrenAttribute as String,
        kAXContentsAttribute as String,
        kAXVisibleChildrenAttribute as String,
    ]

    var children: [AXUIElement] = []
    for key in keys {
        if let values = attributeValue(element, key) as? [AXUIElement] {
            children.append(contentsOf: values)
        }
    }
    return children
}

func stringValues(for element: AXUIElement) -> [String] {
    let keys = [
        kAXTitleAttribute as String,
        kAXValueAttribute as String,
        kAXDescriptionAttribute as String,
        kAXHelpAttribute as String,
    ]

    return keys.compactMap { key in
        guard let value = attributeValue(element, key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

func collectStrings(from element: AXUIElement, depth: Int = 0, visited: inout Set<String>) -> [String] {
    if depth > 12 { return [] }

    let role = attributeValue(element, kAXRoleAttribute as String) as? String
    var values = stringValues(for: element)

    if role == kAXStaticTextRole as String || role == kAXButtonRole as String || role == kAXWindowRole as String {
        for value in values {
            visited.insert(value)
        }
    }

    for child in childElements(of: element) {
        values.append(contentsOf: collectStrings(from: child, depth: depth + 1, visited: &visited))
    }

    return values
}

func visibleWindows(for appElement: AXUIElement) -> [AXUIElement] {
    guard let windows = attributeValue(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
        return []
    }

    return windows.filter { window in
        let minimized = attributeValue(window, kAXMinimizedAttribute as String) as? Bool
        return minimized != true
    }
}

func verifyPopup(config: VerifyConfig) throws {
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
    var lastStrings: [String] = []
    var sawWindow = false

    while Date() < deadline {
        for app in runningApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = visibleWindows(for: appElement)
            guard !windows.isEmpty else {
                continue
            }

            sawWindow = true

            var uniqueStrings: Set<String> = []
            for window in windows {
                _ = collectStrings(from: window, visited: &uniqueStrings)
            }

            let strings = uniqueStrings.sorted()
            if strings.isEmpty {
                continue
            }

            lastStrings = strings
            let missing = config.expectedTexts.filter { expected in
                !strings.contains(where: { $0.contains(expected) })
            }
            if missing.isEmpty {
                for value in strings {
                    print(value)
                }
                return
            }
        }

        Thread.sleep(forTimeInterval: 0.05)
    }

    guard sawWindow else {
        throw VerifyError.popupNotFound(config.appName)
    }

    let missing = config.expectedTexts.filter { expected in
        !lastStrings.contains(where: { $0.contains(expected) })
    }
    throw VerifyError.missingExpectedTexts(missing, lastStrings)
}

do {
    try verifyPopup(config: parseConfig())
} catch {
    fputs((error.localizedDescription + "\n"), stderr)
    exit(1)
}
