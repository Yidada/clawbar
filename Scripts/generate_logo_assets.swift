#!/usr/bin/env swift

import Foundation

struct IconAssetGenerator {
    let rootURL: URL

    var targetResourcesURL: URL {
        rootURL.appendingPathComponent("Sources/Clawbar/Resources", isDirectory: true)
    }

    var releaseResourcesURL: URL {
        rootURL.appendingPathComponent("Resources/Release", isDirectory: true)
    }

    var iconPreviewURL: URL {
        rootURL.appendingPathComponent("Artifacts/IconPreview", isDirectory: true)
    }

    var appSourceURL: URL {
        rootURL.appendingPathComponent("Resources/icons/ClawbarAppIconSource.png")
    }

    var menuBarOutlineReferenceURL: URL {
        rootURL.appendingPathComponent("Resources/icons/ClawbarMenuBarOutlineReference.png")
    }

    var menuBarGlyphSourceURL: URL {
        rootURL.appendingPathComponent("Resources/icons/ClawbarMenuBarGlyphSource.png")
    }

    func run() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: targetResourcesURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: releaseResourcesURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: iconPreviewURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        guard fileManager.fileExists(atPath: appSourceURL.path) else {
            throw GeneratorError("Missing app icon source at \(appSourceURL.path)")
        }
        guard fileManager.fileExists(atPath: menuBarOutlineReferenceURL.path) else {
            throw GeneratorError("Missing menu bar outline reference at \(menuBarOutlineReferenceURL.path)")
        }
        guard fileManager.fileExists(atPath: menuBarGlyphSourceURL.path) else {
            throw GeneratorError("Missing menu bar glyph source at \(menuBarGlyphSourceURL.path)")
        }

        let masterURL = targetResourcesURL.appendingPathComponent("ClawbarLogoMaster.png")
        let menuBar1xURL = targetResourcesURL.appendingPathComponent("ClawbarMenuBarTemplate18.png")
        let menuBar2xURL = targetResourcesURL.appendingPathComponent("ClawbarMenuBarTemplate36.png")
        let icnsURL = releaseResourcesURL.appendingPathComponent("Clawbar.icns")

        try runScript(
            named: "generate_app_icon_from_source.swift",
            arguments: [
                "--source", appSourceURL.path,
                "--master-output", masterURL.path,
                "--icns-output", icnsURL.path,
                "--preview", iconPreviewURL.appendingPathComponent("AppIconMasterPreview.png").path,
                "--padding", "48",
                "--background-top", "46B6F9",
                "--background-bottom", "0A2E78",
                "--flatten-alpha",
            ]
        )

        try runScript(
            named: "extract_status_bar_icon.swift",
            arguments: [
                "--source", menuBarGlyphSourceURL.path,
                "--output-1x", menuBar1xURL.path,
                "--output-2x", menuBar2xURL.path,
                "--preview", iconPreviewURL.appendingPathComponent("MenuBarTemplatePreview.png").path,
                "--padding-1x", "1",
                "--padding-2x", "2",
            ]
        )
    }

    private func runScript(named name: String, arguments: [String]) throws {
        let scriptURL = rootURL.appendingPathComponent("Scripts/\(name)")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw GeneratorError("Missing helper script at \(scriptURL.path)")
        }

        let process = Process()
        process.currentDirectoryURL = rootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", scriptURL.path] + arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GeneratorError("\(name) failed with exit status \(process.terminationStatus)")
        }
    }
}

struct GeneratorError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
guard FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Package.swift").path) else {
    throw GeneratorError("Run this script from the repository root.")
}

try IconAssetGenerator(rootURL: rootURL).run()
