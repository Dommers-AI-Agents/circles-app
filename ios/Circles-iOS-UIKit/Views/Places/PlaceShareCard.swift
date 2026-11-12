import UIKit

/// The picture in a shared place's bubble (Wes, 2026-11-12): the photo on
/// top, then what it is, its name, when to go and where, on the brand blue.
/// The facts live on the card so the bubble needs no text beside it; the
/// link opens the place in FavCircles.
enum PlaceShareCard {
    static let size = CGSize(width: 600, height: 500)
    private static let photoHeight: CGFloat = 200
    private static let brandBlue = UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1)   // #3182CE

    static func image(for content: PlaceShareContent, photo: UIImage?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            brandBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let top = CGRect(x: 0, y: 0, width: size.width, height: photoHeight)
            if let photo {
                drawFilling(photo, in: top, ctx: ctx.cgContext)
            } else {
                UIColor(red: 0.16, green: 0.42, blue: 0.68, alpha: 1).setFill()
                ctx.fill(top)
                let config = UIImage.SymbolConfiguration(pointSize: 84, weight: .semibold)
                if let symbol = UIImage(systemName: content.symbol, withConfiguration: config)?
                    .withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) {
                    let side: CGFloat = 96
                    let scale = min(side / symbol.size.width, side / symbol.size.height)
                    let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                    symbol.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (photoHeight - drawn.height) / 2,
                                           width: drawn.width, height: drawn.height))
                }
            }

            let inset: CGFloat = 32
            let width = size.width - inset * 2
            var y = photoHeight + 22

            y = draw(content.kicker.uppercased(), font: .systemFont(ofSize: 17, weight: .bold),
                     color: .white.withAlphaComponent(0.8), x: inset, y: y, width: width, maxLines: 1, kern: 1.2) + 6
            y = draw(content.title, font: .systemFont(ofSize: 34, weight: .bold),
                     color: .white, x: inset, y: y, width: width, maxLines: 2) + 10
            if let when = content.when {
                y = draw("🗓  " + when, font: .systemFont(ofSize: 21, weight: .semibold),
                         color: .white, x: inset, y: y, width: width, maxLines: 2, hangingPrefix: "🗓  ") + 6
            }
            if let place = content.whereLine {
                y = draw("📍  " + place, font: .systemFont(ofSize: 20, weight: .regular),
                         color: .white.withAlphaComponent(0.92), x: inset, y: y, width: width, maxLines: 2, hangingPrefix: "📍  ") + 6
            }

            // The extra and the brand share the bottom line
            let footerY = size.height - 40
            if let extra = content.extra {
                _ = draw(extra, font: .systemFont(ofSize: 19, weight: .bold),
                         color: .white, x: inset, y: footerY, width: width / 2, maxLines: 1)
            }
            let brand = NSAttributedString(string: "FavCircles", attributes: [
                .font: UIFont.systemFont(ofSize: 19, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ])
            let brandWidth = brand.size().width
            brand.draw(at: CGPoint(x: size.width - inset - brandWidth, y: footerY))
        }
    }

    /// Aspect-fill, cropped to the rect
    private static func drawFilling(_ image: UIImage, in rect: CGRect, ctx: CGContext) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ctx.saveGState()
        ctx.clip(to: rect)
        image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
        ctx.restoreGState()
    }

    /// Draws wrapped text and returns the y just below it
    private static func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat,
                             width: CGFloat, maxLines: Int, kern: CGFloat = 0, hangingPrefix: String? = nil) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // A wrapped line starts under the text, not under the emoji
        if let hangingPrefix {
            paragraph.headIndent = ceil(NSAttributedString(string: hangingPrefix, attributes: [.font: font]).size().width)
        }
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern
        ])
        let maxHeight = ceil(font.lineHeight * CGFloat(maxLines)) + 2
        let bounds = string.boundingRect(with: CGSize(width: width, height: maxHeight),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        let height = min(ceil(bounds.height), maxHeight)
        string.draw(with: CGRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return y + height
    }
}
