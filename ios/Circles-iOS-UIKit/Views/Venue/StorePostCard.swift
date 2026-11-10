import UIKit

/// The picture a store shares on Instagram for a new offer, announcement or
/// event: the store's photo (brand blue when it has none) under a dark wash,
/// the headline, one detail line, and the FavCircles footer. Rendered at
/// Instagram's own pixel sizes so nothing is resampled.
enum StorePostCard {

    enum Format: CaseIterable {
        case story, post

        var size: CGSize {
            switch self {
            case .story: return CGSize(width: 1080, height: 1920)
            case .post: return CGSize(width: 1080, height: 1350)
            }
        }
    }

    static let brandBlue = UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1)

    static func render(_ format: Format, photo: UIImage?, storeName: String, headline: String, detail: String,
                       footer: String) -> UIImage {
        let size = format.size
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        return UIGraphicsImageRenderer(size: size, format: rendererFormat).image { ctx in
            let bounds = CGRect(origin: .zero, size: size)
            brandBlue.setFill()
            ctx.fill(bounds)
            if let photo { drawFilling(photo, in: bounds) }

            // A dark wash that deepens toward the words
            let colors = [UIColor.black.withAlphaComponent(0.15).cgColor, UIColor.black.withAlphaComponent(0.78).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height * 0.3),
                                                 end: CGPoint(x: 0, y: size.height), options: [])
            }

            let margin: CGFloat = 72
            let width = size.width - 2 * margin
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping

            let footerText = NSAttributedString(string: footer, attributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9), .paragraphStyle: paragraph
            ])
            let footerHeight = footerText.boundingRect(with: CGSize(width: width, height: 200), options: .usesLineFragmentOrigin, context: nil).height
            var y = size.height - margin - footerHeight
            footerText.draw(in: CGRect(x: margin, y: y, width: width, height: footerHeight))

            let detailText = NSAttributedString(string: detail, attributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.95), .paragraphStyle: paragraph
            ])
            let detailHeight = min(detailText.boundingRect(with: CGSize(width: width, height: 400), options: .usesLineFragmentOrigin, context: nil).height, 400)
            y -= 28 + detailHeight
            detailText.draw(in: CGRect(x: margin, y: y, width: width, height: detailHeight))

            let headlineFont = UIFont(name: "Georgia-Bold", size: 96) ?? UIFont.systemFont(ofSize: 96, weight: .bold)
            let headlineText = NSAttributedString(string: headline, attributes: [
                .font: headlineFont, .foregroundColor: UIColor.white, .paragraphStyle: paragraph
            ])
            let headlineHeight = min(headlineText.boundingRect(with: CGSize(width: width, height: 700), options: .usesLineFragmentOrigin, context: nil).height, 700)
            y -= 24 + headlineHeight
            headlineText.draw(in: CGRect(x: margin, y: y, width: width, height: headlineHeight))

            let storeText = NSAttributedString(string: storeName.uppercased(), attributes: [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold), .kern: 4,
                .foregroundColor: UIColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph
            ])
            let storeHeight = storeText.boundingRect(with: CGSize(width: width, height: 120), options: .usesLineFragmentOrigin, context: nil).height
            y -= 20 + storeHeight
            storeText.draw(in: CGRect(x: margin, y: y, width: width, height: storeHeight))
        }
    }

    /// Scale-to-fill, centered
    private static func drawFilling(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
    }
}
