import UIKit

/// The picture in a shared tab's bubble: brand blue, the tab's symbol, its
/// name and one line on what it is. Minimal on purpose — the link does the
/// pitching once it's tapped (same rule as the widget share cards).
enum HomeTabShareCard {
    static let size = CGSize(width: 600, height: 340)

    static func image(for segment: HomeContentSegment) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1).setFill()   // #3182CE, the brand blue
            ctx.fill(bounds)

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 96, weight: .semibold)
            if let symbol = UIImage(systemName: segment.shareSymbolName, withConfiguration: symbolConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let side: CGFloat = 110
                let scale = min(side / symbol.size.width, side / symbol.size.height)
                let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: 44, width: drawn.width, height: drawn.height))
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping

            let title = NSAttributedString(string: HomeTabShareLink.title(for: segment), attributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ])
            title.draw(in: CGRect(x: 32, y: 176, width: size.width - 64, height: 52))

            let blurb = NSAttributedString(string: segment.shareBlurb, attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .paragraphStyle: paragraph
            ])
            blurb.draw(in: CGRect(x: 48, y: 236, width: size.width - 96, height: 80))
        }
    }
}
