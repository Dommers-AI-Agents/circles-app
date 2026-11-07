import UIKit

/// Photos on their way to the server (Wes, 2026-11-07: a profile photo at
/// sign-up failed with "Image too large: 1.07 MB").
///
/// Sizes are real pixels. A `UIGraphicsImageRenderer` built with only a size
/// draws at the screen's scale, so "800" came out 2,400 px on a 3× phone and
/// the JPEG blew past `upload/image`'s limit (1 MB of base64, about 750 KB of
/// JPEG). Every upload resize goes through here.
enum ImageUpload {

    /// What `upload/image` accepts once base64 is added (1 MB of base64)
    static let maxJPEGBytes = 740_000

    /// The image at most `maxPixels` on its long side, drawn at 1 pixel per
    /// point; never scaled up.
    static func scaled(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let factor = min(1, maxPixels / max(width, height, 1))
        let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// A JPEG at most `maxPixels` on its long side that always fits under
    /// `maxBytes`: lower quality first, then smaller, until it does.
    static func jpeg(_ image: UIImage, maxPixels: CGFloat, quality: CGFloat = 0.8,
                     maxBytes: Int = maxJPEGBytes) -> Data? {
        var pixels = maxPixels
        var best: Data?
        for _ in 0..<6 {
            let scaledImage = scaled(image, maxPixels: pixels)
            for q in [quality, 0.7, 0.6, 0.5] where q <= quality {
                guard let data = scaledImage.jpegData(compressionQuality: q) else { continue }
                best = data
                if data.count <= maxBytes { return data }
            }
            pixels *= 0.75
        }
        return best
    }

    /// Already-encoded image data brought under `maxBytes` (unchanged when it fits).
    static func fitting(_ data: Data, maxPixels: CGFloat = 1600, maxBytes: Int = maxJPEGBytes) -> Data {
        guard data.count > maxBytes, let image = UIImage(data: data) else { return data }
        return jpeg(image, maxPixels: maxPixels, maxBytes: maxBytes) ?? data
    }
}
