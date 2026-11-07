import Testing
import UIKit
@testable import Circles_iOS

/// Photos sent to the server are sized in real pixels and always fit under
/// upload/image's limit (2026-11-07: a sign-up profile photo came out 2,400 px
/// on a 3× phone and was refused at 1.07 MB).
struct ImageUploadTests {

    /// A noisy photo-sized image at 3× scale, the hard case for JPEG
    private func noisyPhoto(points: CGSize = CGSize(width: 1400, height: 1000), scale: CGFloat = 3) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: points, format: format).image { ctx in
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<4000 {
                UIColor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                        blue: .random(in: 0...1, using: &generator), alpha: 1).setFill()
                ctx.fill(CGRect(x: .random(in: 0..<points.width), y: .random(in: 0..<points.height),
                                width: .random(in: 2...40), height: .random(in: 2...40)))
            }
        }
    }

    @Test func scalesInPixelsNotPoints() {
        let scaled = ImageUpload.scaled(noisyPhoto(), maxPixels: 800)
        #expect(scaled.scale == 1)
        #expect(max(scaled.size.width, scaled.size.height) == 800)
    }

    @Test func neverScalesUp() {
        let small = noisyPhoto(points: CGSize(width: 100, height: 50), scale: 1)
        #expect(ImageUpload.scaled(small, maxPixels: 800).size == CGSize(width: 100, height: 50))
    }

    @Test func alwaysFitsTheUploadLimit() throws {
        let data = try #require(ImageUpload.jpeg(noisyPhoto(), maxPixels: 4000))
        #expect(data.count <= ImageUpload.maxJPEGBytes)
        // base64 of it stays under the server's 1 MB
        #expect(data.base64EncodedString().utf8.count <= 1024 * 1024)
    }

    @Test func fittingLeavesSmallDataAlone() throws {
        let data = try #require(noisyPhoto(points: CGSize(width: 40, height: 40), scale: 1).jpegData(compressionQuality: 0.8))
        #expect(ImageUpload.fitting(data) == data)
    }
}
