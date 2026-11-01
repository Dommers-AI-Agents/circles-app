import UIKit

/// The backdrop behind a first-run screen (2026-11-01): a soft brand-blue
/// wash down the page and, when there is one, the place's photo across the
/// top fading into it, so the step after the App Clip still looks like the
/// store the person just saved. Never a flat black or white page.
final class FirstRunBackdropView: UIView {

    /// How tall the photo band is before it has faded out
    static let photoHeight: CGFloat = 300

    private let wash = GradientView()
    private let photo = UIImageView()
    /// The photo itself turns transparent toward its bottom, so it melts
    /// into the wash beneath instead of ending on a line
    private let photoMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = Constants.Colors.background
        clipsToBounds = true

        // Brand blue at the top, teal through the middle, the page below
        wash.colors = [Constants.Colors.primary.withAlphaComponent(0.30),
                       Constants.Colors.accent.withAlphaComponent(0.12),
                       Constants.Colors.background]
        wash.locations = [0, 0.45, 1]

        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.alpha = 0

        photoMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor]
        photoMask.locations = [0, 0.4, 0.72, 1]
        photo.layer.mask = photoMask

        for v in [wash, photo] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            wash.topAnchor.constraint(equalTo: topAnchor),
            wash.leadingAnchor.constraint(equalTo: leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: trailingAnchor),
            wash.bottomAnchor.constraint(equalTo: bottomAnchor),
            photo.topAnchor.constraint(equalTo: topAnchor),
            photo.leadingAnchor.constraint(equalTo: leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: trailingAnchor),
            photo.heightAnchor.constraint(equalToConstant: Self.photoHeight)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        photoMask.frame = photo.bounds
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Fades the photo in; no URL (or a failed load) leaves the wash alone
    func showPhoto(from urlString: String?) {
        guard let urlString, !urlString.isEmpty else { return }
        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, let image else { return }
                self.photo.image = image
                UIView.animate(withDuration: 0.4) { self.photo.alpha = 1 }
            }
        }
    }

    /// Scrolled `offset` points: the photo drifts up at half speed and fades
    func follow(scrollOffset offset: CGFloat) {
        let y = max(0, offset)
        photo.transform = CGAffineTransform(translationX: 0, y: -y * 0.5)
        photo.alpha = photo.image == nil ? 0 : max(0, 1 - y / Self.photoHeight)
    }
}

/// A view whose layer is a vertical gradient of dynamic colors, re-resolved
/// when light/dark mode changes
final class GradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    var colors: [UIColor] = [] { didSet { applyColors() } }
    var locations: [NSNumber]? { didSet { gradient.locations = locations } }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? true { applyColors() }
    }

    private func applyColors() {
        gradient.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}
