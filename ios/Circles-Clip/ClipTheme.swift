import UIKit

// The clip's look, matching the App Clip cards and the App Store header
// (Wes, 2026-10-31): the store's photo full screen and bright, or charcoal
// with a faint street map, a dashed route through three map pins, and the
// serif hook with its second line in gold. Fixed colours in light and dark
// mode, like the cards.
enum ClipTheme {
    static let charcoal = UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)     // #2E333B
    static let ink = UIColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1)         // #111317
    static let gold = UIColor(red: 0.965, green: 0.788, blue: 0.271, alpha: 1)      // #F6C945
    static let pinRed = UIColor(red: 0.784, green: 0.267, blue: 0.184, alpha: 1)    // #C8442F
    static let pinGold = UIColor(red: 0.851, green: 0.651, blue: 0.180, alpha: 1)   // #D9A62E
    static let pinGreen = UIColor(red: 0.416, green: 0.561, blue: 0.235, alpha: 1)  // #6A8F3C

    /// Apple's serif (New York), bold: the cards' Gelasio without bundling a font
    static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The two-line hook: white first line, gold second
    static func hookText(_ first: String, _ second: String, size: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 0.95
        let text = NSMutableAttributedString(string: first + "\n", attributes: [
            .font: serif(size), .foregroundColor: UIColor.white, .paragraphStyle: paragraph
        ])
        text.append(NSAttributedString(string: second, attributes: [
            .font: serif(size), .foregroundColor: gold, .paragraphStyle: paragraph
        ]))
        return text
    }

    static func label(_ font: UIFont, color: UIColor = .white, lines: Int = 0) -> UILabel {
        let label = UILabel()
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
        label.adjustsFontForContentSizeCategory = false
        return label
    }

    /// Soft shadow so white words read over any photo
    static func lift(_ view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.55
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    static func brandMarkView(side: CGFloat) -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: "BrandMark"))
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = side * 0.22 // app-icon curvature
        imageView.layer.masksToBounds = true
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: side).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: side).isActive = true
        return imageView
    }

    /// The icon with "FavCircles", what it's for and the road line, top left of each screen
    static func brandHeader(mark: UIImageView) -> UIStackView {
        let name = label(.systemFont(ofSize: 17, weight: .bold), lines: 1)
        name.text = "FavCircles"
        let tagline = label(.systemFont(ofSize: 13, weight: .medium), color: UIColor.white.withAlphaComponent(0.85))
        tagline.text = "Save your favorite places. Build your own map."
        let road = label(serif(13).withTraits(.traitItalic), color: gold)
        road.text = "It's your road, the road less traveled. Save it."
        let words = UIStackView(arrangedSubviews: [name, tagline, road])
        words.axis = .vertical
        words.spacing = 1
        let header = UIStackView(arrangedSubviews: [mark, words])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        [name, tagline, road].forEach(lift)
        return header
    }

    /// Gold call to action with dark words
    static func primaryButton(_ title: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = gold
        config.baseForegroundColor = ink
        config.cornerStyle = .large
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    /// Frosted glass button with white words, for the second choice
    static func glassButton(_ title: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.background.strokeColor = UIColor.white.withAlphaComponent(0.35)
        config.background.strokeWidth = 1
        config.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        return button
    }

    /// Plain text link (Resend code, Sign out)
    static func linkButton(_ title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.85)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
        return UIButton(configuration: config)
    }

    /// A frosted text field on the dark backdrop
    static func field(placeholder: String, contentType: UITextContentType) -> UITextField {
        let field = UITextField()
        field.textContentType = contentType
        field.textColor = .white
        field.tintColor = gold
        field.font = .systemFont(ofSize: 18)
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.55)
        ])
        field.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        field.layer.cornerRadius = 14
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.rightViewMode = .always
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return field
    }

    // Staggered entrance: fade + rise, one element after another
    static func animateIn(_ views: [UIView], baseDelay: TimeInterval = 0.05) {
        for (index, view) in views.enumerated() {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 18)
            UIView.animate(withDuration: 0.55,
                           delay: baseDelay + Double(index) * 0.08,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.4,
                           options: [.curveEaseOut]) {
                view.alpha = 1
                view.transform = .identity
            }
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Full-screen backdrop: the store's photo (bright, shaded only toward the
/// words at the bottom) or charcoal with a faint street map, plus the dashed
/// route through three pins in the upper right.
final class ClipBackdropView: UIView {

    private let gradient = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let photoView = UIImageView()
    private let shade = CAGradientLayer()
    private let grid = CAShapeLayer()
    private let avenues = CAShapeLayer()
    private let route = CAShapeLayer()
    private var pins: [CAShapeLayer] = []
    private let showsRoute: Bool

    init(showsRoute: Bool = true) {
        self.showsRoute = showsRoute
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false

        gradient.colors = [ClipTheme.charcoal.cgColor, ClipTheme.ink.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)

        for line in [grid, avenues] {
            line.strokeColor = UIColor.white.withAlphaComponent(0.05).cgColor
            line.fillColor = nil
            layer.addSublayer(line)
        }
        grid.lineWidth = 1
        avenues.lineWidth = 5

        glow.type = .radial
        glow.colors = [UIColor(red: 0.19, green: 0.51, blue: 0.81, alpha: 0.22).cgColor, UIColor.clear.cgColor]
        glow.startPoint = CGPoint(x: 0.8, y: 0.25)
        glow.endPoint = CGPoint(x: 1.5, y: 0.95)
        layer.addSublayer(glow)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.alpha = 0
        addSubview(photoView)

        // A little dark behind the header, bright in the middle, darker toward the words
        shade.colors = [UIColor.black.withAlphaComponent(0.45).cgColor,
                        UIColor.black.withAlphaComponent(0.05).cgColor,
                        UIColor.black.withAlphaComponent(0.25).cgColor,
                        UIColor(white: 0.04, alpha: 0.82).cgColor]
        shade.locations = [0, 0.16, 0.45, 1]
        shade.opacity = 0
        layer.addSublayer(shade)

        route.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        route.fillColor = nil
        route.lineWidth = 2.5
        route.lineDashPattern = [8, 7]
        route.lineCap = .round
        route.isHidden = !showsRoute
        layer.addSublayer(route)
        for color in [ClipTheme.pinRed, ClipTheme.pinGold, ClipTheme.pinGreen] {
            let pin = CAShapeLayer()
            pin.fillColor = color.cgColor
            pin.fillRule = .evenOdd
            pin.shadowColor = UIColor.black.cgColor
            pin.shadowOpacity = 0.45
            pin.shadowRadius = 6
            pin.shadowOffset = CGSize(width: 0, height: 3)
            pin.isHidden = !showsRoute
            layer.addSublayer(pin)
            pins.append(pin)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the store's photo over the map (fades in once it has loaded)
    func setPhoto(_ image: UIImage?) {
        photoView.image = image
        let showing = image != nil
        UIView.animate(withDuration: 0.5) { self.photoView.alpha = showing ? 1 : 0 }
        shade.opacity = showing ? 1 : 0
    }

    /// Loads a photo URL in the background; failures leave the map showing
    func loadPhoto(from url: URL?) {
        guard let url else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run { self?.setPhoto(image) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        glow.frame = bounds
        photoView.frame = bounds
        shade.frame = bounds
        drawMap()
        drawRoute()
        CATransaction.commit()
    }

    // Same seeded skewed grid as the App Clip card header
    private func drawMap() {
        let w = bounds.width, h = bounds.height, k = max(w, h) / 1200
        var seed: Int = 7
        func rnd() -> CGFloat {
            seed = (seed * 16807) % 2147483647
            return CGFloat(seed) / 2147483647
        }
        let lines = UIBezierPath()
        var x = -200 * k
        while x < w + 200 * k {
            lines.move(to: CGPoint(x: x, y: -50 * k))
            lines.addLine(to: CGPoint(x: x + 260 * k, y: h + 50 * k))
            x += (70 + rnd() * 60) * k
        }
        var y = -100 * k
        while y < h + 200 * k {
            lines.move(to: CGPoint(x: -50 * k, y: y))
            lines.addLine(to: CGPoint(x: w + 50 * k, y: y - 220 * k))
            y += (60 + rnd() * 70) * k
        }
        grid.path = lines.cgPath
        let big = UIBezierPath()
        big.move(to: CGPoint(x: -20, y: h * 0.42))
        big.addLine(to: CGPoint(x: w + 20, y: h * 0.18))
        big.move(to: CGPoint(x: w * 0.3, y: -20))
        big.addLine(to: CGPoint(x: w * 0.62, y: h + 20))
        avenues.path = big.cgPath
    }

    // Three saved spots joined by a dashed route, clear of the words below
    private func drawRoute() {
        guard showsRoute else { return }
        let w = bounds.width, h = bounds.height
        let a = CGPoint(x: w * 0.40, y: h * 0.32)
        let b = CGPoint(x: w * 0.63, y: h * 0.27)
        let c = CGPoint(x: w * 0.84, y: h * 0.21)
        let path = UIBezierPath()
        path.move(to: a)
        path.addCurve(to: b, controlPoint1: CGPoint(x: a.x + w * 0.08, y: a.y - h * 0.02), controlPoint2: CGPoint(x: b.x - w * 0.12, y: b.y + h * 0.05))
        path.addCurve(to: c, controlPoint1: CGPoint(x: b.x + w * 0.1, y: b.y - h * 0.04), controlPoint2: CGPoint(x: c.x - w * 0.06, y: c.y + h * 0.05))
        route.path = path.cgPath
        for (pin, (point, scale)) in zip(pins, [(a, 0.85), (b, 0.85), (c, 1.1)] as [(CGPoint, CGFloat)]) {
            pin.path = Self.pinPath(tipAt: point, scale: scale).cgPath
        }
    }

    /// A map pin with its tip on `tip` and a dark hole (even-odd fill)
    private static func pinPath(tipAt tip: CGPoint, scale: CGFloat) -> UIBezierPath {
        let r = 15 * scale
        let center = CGPoint(x: tip.x, y: tip.y - r * 2.1)
        let path = UIBezierPath()
        path.move(to: tip)
        path.addCurve(to: CGPoint(x: center.x - r, y: center.y),
                      controlPoint1: CGPoint(x: tip.x - r * 0.35, y: tip.y - r * 0.6),
                      controlPoint2: CGPoint(x: center.x - r, y: center.y + r * 0.75))
        path.addArc(withCenter: center, radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: tip,
                      controlPoint1: CGPoint(x: center.x + r, y: center.y + r * 0.75),
                      controlPoint2: CGPoint(x: tip.x + r * 0.35, y: tip.y - r * 0.6))
        path.close()
        path.append(UIBezierPath(arcCenter: CGPoint(x: center.x, y: center.y), radius: r * 0.36, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        path.usesEvenOddFillRule = true
        return path
    }
}
