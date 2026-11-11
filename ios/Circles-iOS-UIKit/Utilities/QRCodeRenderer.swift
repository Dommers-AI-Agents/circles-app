import UIKit
import CoreImage

/// QR codes drawn as bitmaps (a CIImage-backed UIImage shows on screen but
/// draws as nothing into a renderer, which once made shared and printed QRs
/// blank). Shared by the profile, the store's codes and Scan Actions.
enum QRCodeRenderer {
    /// `correction` "M" for a code shown on a screen, "H" when a logo covers
    /// its middle or it's printed
    static func image(for string: String, correction: String = "M", scale: CGFloat = 12) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correction, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        // Whole-module scaling keeps the edges crisp
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// The QR with the FavCircles mark (three circles on white) in its
    /// middle. Make the code with "H" correction so it still scans.
    static func withLogo(_ qrImage: UIImage) -> UIImage {
        let size = qrImage.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            qrImage.draw(in: CGRect(origin: .zero, size: size))
            let logoSize = size.width * 0.25
            let logoRect = CGRect(x: (size.width - logoSize) / 2, y: (size.height - logoSize) / 2,
                                  width: logoSize, height: logoSize)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: logoRect.insetBy(dx: -5, dy: -5)).fill()
            Constants.Colors.primary.setFill()
            let circleSize = logoSize * 0.3
            let offset = circleSize * 0.3
            UIBezierPath(ovalIn: CGRect(x: logoRect.midX - circleSize / 2, y: logoRect.minY + offset,
                                        width: circleSize, height: circleSize)).fill()
            UIBezierPath(ovalIn: CGRect(x: logoRect.midX - circleSize - offset / 2, y: logoRect.midY,
                                        width: circleSize, height: circleSize)).fill()
            UIBezierPath(ovalIn: CGRect(x: logoRect.midX + offset / 2, y: logoRect.midY,
                                        width: circleSize, height: circleSize)).fill()
        }
    }
}
