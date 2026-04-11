#!/usr/bin/env swift

import AppKit
import Foundation
import simd

struct GenerateAppIconCommand {
    let sourceURL: URL
    let masterOutputURL: URL
    let icnsOutputURL: URL
    let previewURL: URL?
    let canvasSize: Int
    let padding: Int
    let background: IconBackground?
    let flattenAlpha: Bool

    func run() throws {
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw CommandError("Unable to load source image at \(sourceURL.path)")
        }

        let source = try PixelImage(image: sourceImage)
        let extracted = try source.extractForeground()
        let isolated = try extracted.isolateLargestComponent()
        let bounds = try isolated.detectOpaqueBounds()

        let masterData = try IconComposer(
            foreground: isolated,
            bounds: bounds,
            canvasSize: canvasSize,
            padding: padding,
            background: background,
            flattenAlpha: flattenAlpha
        ).makePNGData()

        try FileManager.default.createDirectory(
            at: masterOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try masterData.write(to: masterOutputURL)

        if let previewURL {
            try FileManager.default.createDirectory(
                at: previewURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try masterData.write(to: previewURL)
        }

        try writeICNS(from: isolated, bounds: bounds, to: icnsOutputURL)
    }

    private func writeICNS(from image: PixelImage, bounds: CGRect, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let tempIconsetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawbar-app-icon-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempIconsetURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: tempIconsetURL) }

        let iconsetEntries: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        for (name, pixelSize) in iconsetEntries {
            let data = try IconComposer(
                foreground: image,
                bounds: bounds,
                canvasSize: pixelSize,
                padding: scaledPadding(for: pixelSize),
                background: background,
                flattenAlpha: flattenAlpha
            ).makePNGData()
            try data.write(to: tempIconsetURL.appendingPathComponent(name))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = [
            "-c", "icns",
            tempIconsetURL.path,
            "-o", destinationURL.path,
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError("iconutil failed with exit status \(process.terminationStatus)")
        }
    }

    private func scaledPadding(for pixelSize: Int) -> Int {
        max(Int((Double(pixelSize) / Double(canvasSize) * Double(padding)).rounded()), pixelSize >= 128 ? 8 : 1)
    }
}

struct IconComposer {
    let foreground: PixelImage
    let bounds: CGRect
    let canvasSize: Int
    let padding: Int
    let background: IconBackground?
    let flattenAlpha: Bool

    func makePNGData() throws -> Data {
        let bitmapInfo: UInt32 = flattenAlpha
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: canvasSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw CommandError("Unable to create app icon bitmap context.")
        }

        let destination = aspectFitRect(
            sourceSize: bounds.size,
            canvasSize: CGSize(width: canvasSize, height: canvasSize),
            padding: CGFloat(padding)
        )

        let cropped = try foreground.makeCGImage(croppingTo: bounds)

        let canvasRect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        if let background {
            try background.draw(in: context, rect: canvasRect)
        } else {
            context.clear(canvasRect)
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: destination)

        guard let image = context.makeImage() else {
            throw CommandError("Unable to build rendered app icon image.")
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CommandError("Unable to encode app icon PNG.")
        }
        return data
    }

    private func aspectFitRect(sourceSize: CGSize, canvasSize: CGSize, padding: CGFloat) -> CGRect {
        let availableWidth = max(canvasSize.width - (padding * 2), 1)
        let availableHeight = max(canvasSize.height - (padding * 2), 1)
        let scale = min(
            availableWidth / max(sourceSize.width, 1),
            availableHeight / max(sourceSize.height, 1)
        )
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(
            x: ((canvasSize.width - width) / 2).rounded(.down),
            y: ((canvasSize.height - height) / 2).rounded(.down),
            width: width,
            height: height
        )
    }
}

struct IconBackground {
    let topColor: NSColor
    let bottomColor: NSColor

    func draw(in context: CGContext, rect: CGRect) throws {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            throw CommandError("Unable to create app icon background gradient.")
        }

        context.saveGState()
        context.setFillColor(bottomColor.cgColor)
        context.fill(rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
        context.restoreGState()
    }
}

struct PixelImage {
    struct RGBA {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    let width: Int
    let height: Int
    private let pixels: [UInt8]

    init(image: NSImage) throws {
        let cgImage = try image.cgImage()
        self = try Self(cgImage: cgImage)
    }

    init(cgImage: CGImage) throws {
        width = cgImage.width
        height = cgImage.height

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            throw CommandError("Unable to allocate source bitmap.")
        }

        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
            throw CommandError("Unable to create source bitmap context.")
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let bitmapData = rep.bitmapData else {
            throw CommandError("Unable to access source bitmap data.")
        }

        pixels = Array(UnsafeBufferPointer(start: bitmapData, count: width * height * 4))
    }

    func extractForeground() throws -> PixelImage {
        if hasMeaningfulTransparency() {
            return self
        }

        var output = pixels
        let backgroundMask = backgroundConnectedMaskForCheckerboard()

        for flatIndex in 0..<(width * height) where backgroundMask[flatIndex] == 1 {
            output[(flatIndex * 4) + 3] = 0
        }

        return try PixelImage(width: width, height: height, pixels: output)
    }

    func hasMeaningfulTransparency() -> Bool {
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] < 250 {
            return true
        }
        return false
    }

    func detectOpaqueBounds(alphaThreshold: UInt8 = 14) throws -> CGRect {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[indexFor(x: x, y: y) + 3]
                if alpha > alphaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            throw CommandError("Unable to detect app icon foreground bounds.")
        }

        return CGRect(
            x: max(0, minX - 4),
            y: max(0, minY - 4),
            width: min(width - 1, maxX + 4) - max(0, minX - 4) + 1,
            height: min(height - 1, maxY + 4) - max(0, minY - 4) + 1
        )
    }

    func isolateLargestComponent(alphaThreshold: UInt8 = 14) throws -> PixelImage {
        let pixelCount = width * height
        var visited = [UInt8](repeating: 0, count: pixelCount)
        var largestComponent: [Int] = []
        var queue: [Int] = []
        queue.reserveCapacity(4096)

        for y in 0..<height {
            for x in 0..<width {
                let flatIndex = y * width + x
                if visited[flatIndex] == 1 { continue }
                visited[flatIndex] = 1

                let alpha = pixels[indexFor(x: x, y: y) + 3]
                if alpha <= alphaThreshold { continue }

                var component: [Int] = []
                component.reserveCapacity(4096)
                queue.removeAll(keepingCapacity: true)
                queue.append(flatIndex)
                var readIndex = 0

                while readIndex < queue.count {
                    let current = queue[readIndex]
                    readIndex += 1
                    component.append(current)

                    let currentX = current % width
                    let currentY = current / width

                    for (nextX, nextY) in neighbors(x: currentX, y: currentY) {
                        let nextFlatIndex = nextY * width + nextX
                        if visited[nextFlatIndex] == 1 { continue }
                        visited[nextFlatIndex] = 1
                        let nextAlpha = pixels[indexFor(x: nextX, y: nextY) + 3]
                        if nextAlpha > alphaThreshold {
                            queue.append(nextFlatIndex)
                        }
                    }
                }

                if component.count > largestComponent.count {
                    largestComponent = component
                }
            }
        }

        guard !largestComponent.isEmpty else {
            throw CommandError("Unable to isolate app icon foreground component.")
        }

        var output = pixels
        var keep = [UInt8](repeating: 0, count: pixelCount)
        for index in largestComponent {
            keep[index] = 1
        }

        for flatIndex in 0..<pixelCount where keep[flatIndex] == 0 {
            output[(flatIndex * 4) + 3] = 0
        }

        return try PixelImage(width: width, height: height, pixels: output)
    }

    func makeCGImage(croppingTo rect: CGRect) throws -> CGImage {
        let cropX = Int(rect.origin.x.rounded(.down))
        let cropY = Int(rect.origin.y.rounded(.down))
        let cropWidth = Int(rect.width.rounded(.up))
        let cropHeight = Int(rect.height.rounded(.up))
        let bytesPerRow = cropWidth * 4

        var output = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)

        for destY in 0..<cropHeight {
            let sourceY = cropY + destY
            for destX in 0..<cropWidth {
                let sourceX = cropX + destX
                guard sourceX >= 0, sourceX < width, sourceY >= 0, sourceY < height else { continue }

                let sourceOffset = indexFor(x: sourceX, y: sourceY)
                let destOffset = (destY * cropWidth + destX) * 4
                output[destOffset] = pixels[sourceOffset]
                output[destOffset + 1] = pixels[sourceOffset + 1]
                output[destOffset + 2] = pixels[sourceOffset + 2]
                output[destOffset + 3] = pixels[sourceOffset + 3]
            }
        }

        let provider = CGDataProvider(data: Data(output) as CFData)
        guard let provider else {
            throw CommandError("Unable to create app icon data provider.")
        }

        guard let image = CGImage(
            width: cropWidth,
            height: cropHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw CommandError("Unable to build cropped app icon image.")
        }

        return image
    }

    private init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard pixels.count == width * height * 4 else {
            throw CommandError("Unexpected pixel buffer size.")
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    private func pixelAt(x: Int, y: Int) -> RGBA {
        let offset = indexFor(x: x, y: y)
        return RGBA(
            r: pixels[offset],
            g: pixels[offset + 1],
            b: pixels[offset + 2],
            a: pixels[offset + 3]
        )
    }

    private func backgroundConnectedMaskForCheckerboard() -> [UInt8] {
        let pixelCount = width * height
        var visited = [UInt8](repeating: 0, count: pixelCount)
        var mask = [UInt8](repeating: 0, count: pixelCount)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        func enqueueIfBackground(x: Int, y: Int, hard: Bool) {
            let flatIndex = y * width + x
            if visited[flatIndex] == 1 { return }
            visited[flatIndex] = 1

            let pixel = pixelAt(x: x, y: y)
            if isLikelyCheckerboardBackground(pixel, hard: hard) {
                queue.append(flatIndex)
                mask[flatIndex] = 1
            }
        }

        for x in 0..<width {
            enqueueIfBackground(x: x, y: 0, hard: true)
            enqueueIfBackground(x: x, y: height - 1, hard: true)
        }
        for y in 0..<height {
            enqueueIfBackground(x: 0, y: y, hard: true)
            enqueueIfBackground(x: width - 1, y: y, hard: true)
        }

        var readIndex = 0
        while readIndex < queue.count {
            let current = queue[readIndex]
            readIndex += 1
            let currentX = current % width
            let currentY = current / width

            for (nextX, nextY) in neighbors(x: currentX, y: currentY) {
                let nextFlatIndex = nextY * width + nextX
                if visited[nextFlatIndex] == 1 { continue }
                visited[nextFlatIndex] = 1

                let pixel = pixelAt(x: nextX, y: nextY)
                if isLikelyCheckerboardBackground(pixel, hard: false) {
                    queue.append(nextFlatIndex)
                    mask[nextFlatIndex] = 1
                }
            }
        }

        return mask
    }

    private func isLikelyCheckerboardBackground(_ pixel: RGBA, hard: Bool) -> Bool {
        let red = Double(pixel.r) / 255.0
        let green = Double(pixel.g) / 255.0
        let blue = Double(pixel.b) / 255.0
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let brightness = (red + green + blue) / 3.0
        let saturation = maxChannel - minChannel

        if hard {
            return brightness >= 0.74 && saturation <= 0.08
        }

        return brightness >= 0.66 && saturation <= 0.12
    }

    private func neighbors(x: Int, y: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        result.reserveCapacity(8)

        for offsetY in -1...1 {
            for offsetX in -1...1 {
                if offsetX == 0 && offsetY == 0 { continue }
                let nextX = x + offsetX
                let nextY = y + offsetY
                if nextX >= 0, nextX < width, nextY >= 0, nextY < height {
                    result.append((nextX, nextY))
                }
            }
        }

        return result
    }

    private func indexFor(x: Int, y: Int) -> Int {
        ((height - 1 - y) * width + x) * 4
    }

}

struct CommandError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

extension NSImage {
    func cgImage() throws -> CGImage {
        var proposed = CGRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw CommandError("Unable to decode NSImage into CGImage.")
        }
        return cgImage
    }
}

extension NSColor {
    convenience init(hexString: String) throws {
        let sanitized = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            throw CommandError("Expected a 6-digit RGB hex color, got '\(hexString)'.")
        }

        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}

func parseArguments() throws -> GenerateAppIconCommand {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var sourcePath: String?
    var masterPath = "Sources/Clawbar/Resources/ClawbarLogoMaster.png"
    var icnsPath = "Resources/Release/Clawbar.icns"
    var previewPath: String? = "Artifacts/IconPreview/AppIconMasterPreview.png"
    var canvasSize = 1024
    var padding = 72
    var backgroundTopHex: String?
    var backgroundBottomHex: String?
    var flattenAlpha = false

    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--source":
            index += 1
            sourcePath = arguments[safe: index]
        case "--master-output":
            index += 1
            masterPath = arguments[safe: index] ?? masterPath
        case "--icns-output":
            index += 1
            icnsPath = arguments[safe: index] ?? icnsPath
        case "--preview":
            index += 1
            previewPath = arguments[safe: index] ?? previewPath
        case "--canvas-size":
            index += 1
            canvasSize = Int(arguments[safe: index] ?? "") ?? canvasSize
        case "--padding":
            index += 1
            padding = Int(arguments[safe: index] ?? "") ?? padding
        case "--background-top":
            index += 1
            backgroundTopHex = arguments[safe: index]
        case "--background-bottom":
            index += 1
            backgroundBottomHex = arguments[safe: index]
        case "--flatten-alpha":
            flattenAlpha = true
        default:
            throw CommandError("Unknown argument: \(arguments[index])")
        }
        index += 1
    }

    guard let sourcePath else {
        throw CommandError("Missing required --source <path> argument.")
    }

    let background: IconBackground?
    switch (backgroundTopHex, backgroundBottomHex) {
    case let (top?, bottom?):
        background = try IconBackground(
            topColor: NSColor(hexString: top),
            bottomColor: NSColor(hexString: bottom)
        )
    case (nil, nil):
        background = nil
    default:
        throw CommandError("Provide both --background-top and --background-bottom, or neither.")
    }

    if flattenAlpha && background == nil {
        throw CommandError("Use --flatten-alpha together with an opaque background.")
    }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return GenerateAppIconCommand(
        sourceURL: URL(fileURLWithPath: sourcePath, relativeTo: currentDirectory).standardizedFileURL,
        masterOutputURL: URL(fileURLWithPath: masterPath, relativeTo: currentDirectory).standardizedFileURL,
        icnsOutputURL: URL(fileURLWithPath: icnsPath, relativeTo: currentDirectory).standardizedFileURL,
        previewURL: previewPath.map { URL(fileURLWithPath: $0, relativeTo: currentDirectory).standardizedFileURL },
        canvasSize: canvasSize,
        padding: padding,
        background: background,
        flattenAlpha: flattenAlpha
    )
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

try parseArguments().run()
