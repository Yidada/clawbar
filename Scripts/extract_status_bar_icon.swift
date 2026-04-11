#!/usr/bin/env swift

import AppKit
import Foundation

struct ExtractStatusBarIconCommand {
    let sourceURL: URL
    let output1xURL: URL
    let output2xURL: URL
    let previewURL: URL?
    let output1xSize: Int
    let output2xSize: Int
    let padding1x: Int
    let padding2x: Int

    func run() throws {
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw CommandError("Unable to load source image at \(sourceURL.path)")
        }

        let sourcePixels = try PixelImage(image: sourceImage)
        let glyphBounds = try IconDetector(source: sourcePixels).detectGlyphBounds()
        guard glyphBounds.count >= 2 else {
            throw CommandError("Expected at least two menu bar glyph candidates in \(sourceURL.lastPathComponent).")
        }

        let rendered1x = try IconRenderer(
            source: sourcePixels,
            glyphBounds: glyphBounds[0],
            outputSize: output1xSize,
            padding: padding1x
        ).makePNGData()

        let rendered2x = try IconRenderer(
            source: sourcePixels,
            glyphBounds: glyphBounds[1],
            outputSize: output2xSize,
            padding: padding2x
        ).makePNGData()

        try FileManager.default.createDirectory(
            at: output1xURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try rendered1x.write(to: output1xURL)
        try rendered2x.write(to: output2xURL)

        if let previewURL {
            try FileManager.default.createDirectory(
                at: previewURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let preview = try PreviewComposer(
                asset1xData: rendered1x,
                asset2xData: rendered2x
            ).makePNGData()
            try preview.write(to: previewURL)
        }
    }
}

struct IconDetector {
    struct Component {
        let bounds: CGRect
        let pixelCount: Int
    }

    let source: PixelImage

    func detectGlyphBounds() throws -> [CGRect] {
        let pixelCountThreshold = max((source.width * source.height) / 1_500, 1_500)
        let widthThreshold = max(source.width / 24, 40)
        let heightThreshold = max(source.height / 8, 90)
        var visited = [UInt8](repeating: 0, count: source.width * source.height)
        var candidates: [Component] = []

        for y in 0..<source.height {
            for x in 0..<source.width {
                let flatIndex = (y * source.width) + x
                if visited[flatIndex] == 1 || !source.isForeground(x: x, y: y) {
                    visited[flatIndex] = 1
                    continue
                }

                let component = floodFill(fromX: x, y: y, visited: &visited)
                if component.pixelCount >= pixelCountThreshold,
                   component.bounds.width >= CGFloat(widthThreshold),
                   component.bounds.height >= CGFloat(heightThreshold) {
                    candidates.append(component)
                }
            }
        }

        let topComponents = candidates
            .sorted(by: { $0.pixelCount > $1.pixelCount })
            .prefix(3)
            .sorted(by: { $0.bounds.minX < $1.bounds.minX })

        guard topComponents.count >= 2 else {
            throw CommandError("Unable to detect optimized menu bar glyphs in source image.")
        }

        return topComponents.map { expand($0.bounds, by: 8) }
    }

    private func floodFill(fromX startX: Int, y startY: Int, visited: inout [UInt8]) -> Component {
        var queue: [(Int, Int)] = []
        queue.reserveCapacity(4_096)
        queue.append((startX, startY))
        visited[(startY * source.width) + startX] = 1

        var readIndex = 0
        var minX = startX
        var minY = startY
        var maxX = startX
        var maxY = startY
        var pixelCount = 0

        while readIndex < queue.count {
            let (x, y) = queue[readIndex]
            readIndex += 1
            pixelCount += 1
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)

            for nextY in max(0, y - 1)...min(source.height - 1, y + 1) {
                for nextX in max(0, x - 1)...min(source.width - 1, x + 1) {
                    let flatIndex = (nextY * source.width) + nextX
                    if visited[flatIndex] == 1 {
                        continue
                    }
                    visited[flatIndex] = 1
                    if source.isForeground(x: nextX, y: nextY) {
                        queue.append((nextX, nextY))
                    }
                }
            }
        }

        return Component(
            bounds: CGRect(
                x: minX,
                y: minY,
                width: (maxX - minX) + 1,
                height: (maxY - minY) + 1
            ),
            pixelCount: pixelCount
        )
    }

    private func expand(_ bounds: CGRect, by inset: Int) -> CGRect {
        let minX = max(Int(bounds.minX) - inset, 0)
        let minY = max(Int(bounds.minY) - inset, 0)
        let maxX = min(Int(bounds.maxX) + inset, source.width - 1)
        let maxY = min(Int(bounds.maxY) + inset, source.height - 1)
        return CGRect(
            x: minX,
            y: minY,
            width: (maxX - minX) + 1,
            height: (maxY - minY) + 1
        )
    }
}

struct IconRenderer {
    let source: PixelImage
    let glyphBounds: CGRect
    let outputSize: Int
    let padding: Int

    func makePNGData() throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outputSize,
            pixelsHigh: outputSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CommandError("Unable to allocate output bitmap.")
        }

        guard let bitmapData = rep.bitmapData else {
            throw CommandError("Unable to access output bitmap data.")
        }

        bitmapData.initialize(repeating: 0, count: rep.bytesPerRow * outputSize)

        let destination = aspectFitRect(
            sourceSize: glyphBounds.size,
            outputSize: outputSize,
            padding: padding
        )

        for destY in 0..<destination.height {
            for destX in 0..<destination.width {
                let normalizedX = (Double(destX) + 0.5) / Double(destination.width)
                let normalizedY = (Double(destY) + 0.5) / Double(destination.height)
                let sampleX = sampleCoordinate(
                    min: Int(glyphBounds.minX),
                    length: Int(glyphBounds.width),
                    normalized: normalizedX,
                    upperBound: source.width - 1
                )
                let sampleY = sampleCoordinate(
                    min: Int(glyphBounds.minY),
                    length: Int(glyphBounds.height),
                    normalized: normalizedY,
                    upperBound: source.height - 1
                )

                guard source.isForeground(x: sampleX, y: sampleY) else {
                    continue
                }

                let writeX = destination.x + destX
                let writeY = destination.y + destY
                let offset = (writeY * rep.bytesPerRow) + (writeX * 4)
                bitmapData[offset] = 0
                bitmapData[offset + 1] = 0
                bitmapData[offset + 2] = 0
                bitmapData[offset + 3] = 255
            }
        }

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CommandError("Unable to encode output PNG.")
        }
        return data
    }

    private func sampleCoordinate(min: Int, length: Int, normalized: Double, upperBound: Int) -> Int {
        let span = max(length - 1, 1)
        let sampled = min + Int((normalized * Double(span)).rounded(.down))
        return Swift.max(0, Swift.min(sampled, upperBound))
    }

    private func aspectFitRect(sourceSize: CGSize, outputSize: Int, padding: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let availableWidth = max(outputSize - (padding * 2), 1)
        let availableHeight = max(outputSize - (padding * 2), 1)
        let scale = min(
            Double(availableWidth) / max(Double(sourceSize.width), 1),
            Double(availableHeight) / max(Double(sourceSize.height), 1)
        )
        let fittedWidth = max(Int((Double(sourceSize.width) * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let fittedHeight = max(Int((Double(sourceSize.height) * scale).rounded(.toNearestOrAwayFromZero)), 1)
        return (
            x: (outputSize - fittedWidth) / 2,
            y: (outputSize - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }
}

struct PreviewComposer {
    let asset1xData: Data
    let asset2xData: Data

    func makePNGData() throws -> Data {
        guard
            let asset1x = NSImage(data: asset1xData),
            let asset2x = NSImage(data: asset2xData),
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 320,
                pixelsHigh: 180,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let graphicsContext = NSGraphicsContext(bitmapImageRep: rep)
        else {
            throw CommandError("Unable to allocate preview bitmap.")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.setFillColor(NSColor.white.cgColor)
        graphicsContext.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        graphicsContext.imageInterpolation = .none

        asset1x.draw(
            in: CGRect(x: 32, y: 40, width: 108, height: 108),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        asset2x.draw(
            in: CGRect(x: 180, y: 40, width: 108, height: 108),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CommandError("Unable to encode preview PNG.")
        }
        return data
    }
}

struct PixelImage {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    init(image: NSImage) throws {
        let cgImage = try image.cgImage()
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

    func isForeground(x: Int, y: Int) -> Bool {
        let offset = ((y * width) + x) * 4
        let red = Double(pixels[offset]) / 255.0
        let green = Double(pixels[offset + 1]) / 255.0
        let blue = Double(pixels[offset + 2]) / 255.0
        let alpha = Double(pixels[offset + 3]) / 255.0
        let brightness = (red + green + blue) / 3.0
        return alpha > 0.2 && brightness < 0.92
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

func parseArguments() throws -> ExtractStatusBarIconCommand {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var sourcePath: String?
    var output1xPath = "Sources/Clawbar/Resources/ClawbarMenuBarTemplate18.png"
    var output2xPath = "Sources/Clawbar/Resources/ClawbarMenuBarTemplate36.png"
    var previewPath: String? = "Artifacts/IconPreview/MenuBarTemplatePreview.png"
    var output1xSize = 18
    var output2xSize = 36
    var padding1x = 1
    var padding2x = 2

    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--source":
            index += 1
            sourcePath = arguments[safe: index]
        case "--output-1x":
            index += 1
            output1xPath = arguments[safe: index] ?? output1xPath
        case "--output-2x":
            index += 1
            output2xPath = arguments[safe: index] ?? output2xPath
        case "--preview":
            index += 1
            previewPath = arguments[safe: index] ?? previewPath
        case "--output-size-1x":
            index += 1
            output1xSize = Int(arguments[safe: index] ?? "") ?? output1xSize
        case "--output-size-2x":
            index += 1
            output2xSize = Int(arguments[safe: index] ?? "") ?? output2xSize
        case "--padding-1x":
            index += 1
            padding1x = Int(arguments[safe: index] ?? "") ?? padding1x
        case "--padding-2x":
            index += 1
            padding2x = Int(arguments[safe: index] ?? "") ?? padding2x
        default:
            throw CommandError("Unknown argument: \(arguments[index])")
        }
        index += 1
    }

    guard let sourcePath else {
        throw CommandError("Missing required --source <path> argument.")
    }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return ExtractStatusBarIconCommand(
        sourceURL: URL(fileURLWithPath: sourcePath, relativeTo: currentDirectory).standardizedFileURL,
        output1xURL: URL(fileURLWithPath: output1xPath, relativeTo: currentDirectory).standardizedFileURL,
        output2xURL: URL(fileURLWithPath: output2xPath, relativeTo: currentDirectory).standardizedFileURL,
        previewURL: previewPath.map { URL(fileURLWithPath: $0, relativeTo: currentDirectory).standardizedFileURL },
        output1xSize: output1xSize,
        output2xSize: output2xSize,
        padding1x: padding1x,
        padding2x: padding2x
    )
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

try parseArguments().run()
