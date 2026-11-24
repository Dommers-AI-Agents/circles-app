import Testing
import UIKit
@testable import Circles_iOS

/// The "Me" tab and chips wear a round thumbnail of your profile picture.
struct MeAvatarTests {

    private func solid(_ colour: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// RGBA of the pixel at a point (in points) of a rendered image.
    private func pixel(of image: UIImage, at point: CGPoint) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let scale = image.scale
        context.translateBy(x: -point.x * scale, y: -(image.size.height - point.y) * scale + 1)
        context.draw(image.cgImage!, in: CGRect(x: 0, y: 0,
                                                 width: image.size.width * scale,
                                                 height: image.size.height * scale))
        return data
    }

    @Test func thumbnailIsTheAskedSizeWhateverThePhotoShape() {
        for size in [CGSize(width: 400, height: 100), CGSize(width: 90, height: 600), CGSize(width: 8, height: 8)] {
            let thumb = MeAvatar.circular(solid(.red, size: size), diameter: 26)
            #expect(thumb.size == CGSize(width: 26, height: 26))
        }
    }

    @Test func thumbnailKeepsItsColoursInATabBar() {
        // A template image would be tinted into a flat disc
        #expect(MeAvatar.circular(solid(.red, size: CGSize(width: 50, height: 50)), diameter: 26)
            .renderingMode == .alwaysOriginal)
    }

    @Test func photoFillsTheCircleAndTheCornersAreClear() {
        // A wide photo must fill the circle (aspect-fill), not letterbox
        let thumb = MeAvatar.circular(solid(.red, size: CGSize(width: 400, height: 100)), diameter: 26)
        let top = pixel(of: thumb, at: CGPoint(x: 13, y: 2))
        #expect(top[0] > 200 && top[3] > 200)
        let corner = pixel(of: thumb, at: CGPoint(x: 0.5, y: 0.5))
        #expect(corner[3] == 0)
    }

    @Test func selectedThumbnailWearsARing() {
        let thumb = MeAvatar.circular(solid(.red, size: CGSize(width: 50, height: 50)),
                                      diameter: 26, ring: .blue)
        #expect(thumb.size == CGSize(width: 26, height: 26))
        let edge = pixel(of: thumb, at: CGPoint(x: 13, y: 0.75))
        #expect(edge[2] > 150 && edge[0] < 100)
        let centre = pixel(of: thumb, at: CGPoint(x: 13, y: 13))
        #expect(centre[0] > 200 && centre[2] < 60)
    }

    @Test func chipAvatarFitsWhereTheGlyphWas() {
        #expect(MeAvatar.chipDiameter <= 16)
    }
}
