import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeImageView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = QRCodeRenderer.makeImage(from: payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Text("二维码生成失败")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}

private enum QRCodeRenderer {
    static func makeImage(from payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 9, y: 9))
        let context = CIContext()

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
    }
}
