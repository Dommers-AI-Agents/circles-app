import UIKit

/// The place page's row of a store's social links: one button per link the
/// store has set, like the Directions / Call / Website row above it. With no
/// links the row has no buttons and the page gives it no height and no gap.
final class PlaceSocialLinksRowView: UIStackView {
    static let rowHeight: CGFloat = 44

    /// A button was tapped: open this address
    var onOpen: ((URL) -> Void)?
    private var urls: [URL] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal
        distribution = .fillEqually
        spacing = 10
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// How many buttons the row is showing
    var buttonCount: Int { arrangedSubviews.count }

    func configure(_ links: PlaceSocialLinks?) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        let buttons = links?.buttons ?? []
        urls = buttons.map(\.url)
        for (index, item) in buttons.enumerated() {
            let button = UIButton.rowButton(title: item.network.title, systemName: "link")
            button.setImage(SocialGlyph.image(for: item.network), for: .normal)
            button.tag = index
            button.accessibilityLabel = "\(item.network.title) page"
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addArrangedSubview(button)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard urls.indices.contains(sender.tag) else { return }
        onOpen?(urls[sender.tag])
    }
}

/// Small one-colour marks for the three networks, drawn here (SF Symbols has
/// no brand marks) and tinted like any button image.
enum SocialGlyph {
    static func image(for network: PlaceSocialLinks.Network, side: CGFloat = 17) -> UIImage {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setStroke()
            UIColor.black.setFill()
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            switch network {
            case .instagram:
                // A rounded square, a lens, and the dot in its corner
                let body = UIBezierPath(roundedRect: box, cornerRadius: side * 0.28)
                body.lineWidth = 1.6
                body.stroke()
                let lens = UIBezierPath(ovalIn: box.insetBy(dx: side * 0.24, dy: side * 0.24))
                lens.lineWidth = 1.6
                lens.stroke()
                let dot: CGFloat = side * 0.13
                UIBezierPath(ovalIn: CGRect(x: box.maxX - side * 0.3, y: box.minY + side * 0.17, width: dot, height: dot)).fill()
            case .facebook:
                // A lowercase f in a disc
                UIBezierPath(ovalIn: box).fill()
                letter("f", font: .systemFont(ofSize: side * 0.82, weight: .bold), colour: .white, in: box, blend: .clear,
                       nudge: CGPoint(x: side * 0.03, y: side * 0.06))
            case .twitter:
                letter("\u{1D54F}", font: .systemFont(ofSize: side * 0.98, weight: .semibold), colour: .black, in: box, blend: .normal,
                       nudge: .zero)
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func letter(_ text: String, font: UIFont, colour: UIColor, in box: CGRect, blend: CGBlendMode, nudge: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let measured = (text as NSString).size(withAttributes: attributes)
        UIGraphicsGetCurrentContext()?.setBlendMode(blend)
        (text as NSString).draw(at: CGPoint(x: box.midX - measured.width / 2 + nudge.x,
                                            y: box.midY - measured.height / 2 + nudge.y), withAttributes: attributes)
        UIGraphicsGetCurrentContext()?.setBlendMode(.normal)
    }
}
