import AppKit
import CoreImage
import Foundation

public enum QrCodeImage {
    /// Renders `sefirah://pair?data=...` (ASCII) via `CIQRCodeGenerator`.
    public static func make(_ string: String, scale: CGFloat = 8) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let data = string.data(using: .isoLatin1) ?? string.data(using: .utf8)
        guard let data, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard scaled.extent.width > 0, scaled.extent.height > 0,
              let cg = context.createCGImage(scaled, from: scaled.extent)
        else { return nil }
        let size = NSSize(width: scaled.extent.width, height: scaled.extent.height)
        return NSImage(cgImage: cg, size: size)
    }
}
