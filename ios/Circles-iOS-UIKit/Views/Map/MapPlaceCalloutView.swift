import UIKit
import MapKit

/// The card a tapped map place opens (Wes, 2026-11-12: "make this bubble
/// prettier and better"), in place of the system action sheet: the place's
/// own Apple Maps icon, its name, what it is and how far, then Add Place and
/// Directions. It points at the place and follows it while the map moves.
final class MapPlaceCalloutView: UIView {
    struct Model {
        let name: String
        /// "Restaurant · 0.4 mi"
        let detail: String?
        let icon: UIImage?
        let iconColor: UIColor?
        /// Already one of theirs: the card says so and opens it instead
        let isSaved: Bool
    }

    var onPrimary: (() -> Void)?
    var onDirections: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var coordinate: CLLocationCoordinate2D
    private weak var mapView: MKMapView?
    private let card = UIView()
    private let arrow = CAShapeLayer()
    private let arrowSize = CGSize(width: 22, height: 11)
    private var pointsDown = true

    private static let cardColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : .white
    }

    init(model: Model, coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init(frame: .zero)
        build(model)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Showing

    func show(on mapView: MKMapView) {
        self.mapView = mapView
        // Beside the map, not inside it: the map's own gestures would take a
        // tap on the card for a tap on the map and let the place go
        (mapView.superview ?? mapView).addSubview(self)
        reposition()
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4) {
            self.alpha = 1
            self.transform = .identity
        }
        UIAccessibility.post(notification: .layoutChanged, argument: self)
    }

    func dismiss(animated: Bool = true) {
        guard animated else { return removeFromSuperview() }
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }, completion: { _ in self.removeFromSuperview() })
    }

    /// Keeps the card on its place: above it when there's room, else below,
    /// and never past the map's edges. Call while the map moves.
    func reposition() {
        guard let mapView, let container = superview else { return }
        let mapFrame = container === mapView ? mapView.bounds : mapView.frame
        let saved = transform
        transform = .identity
        defer { transform = saved }

        let margin: CGFloat = 12
        let width = min(340, mapFrame.width - margin * 2)
        let cardHeight = card.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                     withHorizontalFittingPriority: .required,
                                                     verticalFittingPriority: .fittingSizeLevel).height
        let point = mapView.convert(coordinate, toPointTo: container)
        let gap: CGFloat = 14   // clears the selected pin's glyph
        let total = cardHeight + arrowSize.height
        let top = mapFrame.minY + mapView.safeAreaInsets.top + margin
        pointsDown = point.y - gap - total >= top || point.y + gap + total > mapFrame.maxY - margin

        var x = point.x - width / 2
        x = max(mapFrame.minX + margin, min(x, mapFrame.maxX - margin - width))
        let y = pointsDown ? point.y - gap - total : point.y + gap
        isHidden = !mapFrame.insetBy(dx: -4, dy: -4).contains(point)
        frame = CGRect(x: x, y: y, width: width, height: total)
        card.frame = CGRect(x: 0, y: pointsDown ? 0 : arrowSize.height, width: width, height: cardHeight)

        // The arrow points at the place even when the card slid to stay on screen
        let tipX = max(24, min(point.x - x, width - 24))
        let path = UIBezierPath()
        if pointsDown {
            path.move(to: CGPoint(x: tipX - arrowSize.width / 2, y: cardHeight - 1))
            path.addLine(to: CGPoint(x: tipX, y: total))
            path.addLine(to: CGPoint(x: tipX + arrowSize.width / 2, y: cardHeight - 1))
        } else {
            path.move(to: CGPoint(x: tipX - arrowSize.width / 2, y: arrowSize.height + 1))
            path.addLine(to: CGPoint(x: tipX, y: 0))
            path.addLine(to: CGPoint(x: tipX + arrowSize.width / 2, y: arrowSize.height + 1))
        }
        path.close()
        arrow.path = path.cgPath
        arrow.fillColor = Self.cardColor.resolvedColor(with: traitCollection).cgColor
        // Grows out of the place it points at
        layer.anchorPoint = CGPoint(x: tipX / width, y: pointsDown ? 1 : 0)
        frame = CGRect(x: x, y: y, width: width, height: total)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        arrow.fillColor = Self.cardColor.resolvedColor(with: traitCollection).cgColor
    }

    // MARK: - Layout

    private func build(_ model: Model) {
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        arrow.fillColor = Self.cardColor.resolvedColor(with: traitCollection).cgColor
        layer.addSublayer(arrow)

        card.backgroundColor = Self.cardColor
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        addSubview(card)

        // The place's own Apple Maps glyph on its color
        let iconTile = UIView()
        iconTile.backgroundColor = model.iconColor ?? Constants.Colors.primary
        iconTile.layer.cornerRadius = 21
        let iconView = UIImageView(image: (model.icon ?? UIImage(systemName: "mappin"))?
            .withTintColor(.white, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(iconView)
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = model.name
        nameLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.numberOfLines = 2

        let detailLabel = UILabel()
        detailLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        detailLabel.numberOfLines = 1
        if model.isSaved {
            let saved = NSMutableAttributedString(string: "✓ Saved", attributes: [
                .foregroundColor: UIColor.systemGreen, .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
            ])
            if let detail = model.detail {
                saved.append(NSAttributedString(string: " · \(detail)", attributes: [.foregroundColor: Constants.Colors.secondaryLabel]))
            }
            detailLabel.attributedText = saved
        } else {
            detailLabel.text = model.detail
            detailLabel.textColor = Constants.Colors.secondaryLabel
        }
        detailLabel.isHidden = !model.isSaved && model.detail == nil

        let text = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2

        let close = UIButton.iconButton(systemName: "xmark.circle.fill", pointSize: 22)
        close.tintColor = .tertiaryLabel
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [iconTile, text, close])
        header.alignment = .center
        header.spacing = 12

        let primary = UIButton.capsuleButton(title: model.isSaved ? "View Place" : "Add Place",
                                             systemName: model.isSaved ? "arrow.up.right" : "plus", filled: true)
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        let directions = UIButton.capsuleButton(title: "Directions", systemName: "car.fill", filled: false)
        directions.addTarget(self, action: #selector(directionsTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [primary, directions])
        buttons.distribution = .fillEqually
        buttons.spacing = 10

        let content = UIStackView(arrangedSubviews: [header, buttons])
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: 42),
            iconTile.heightAnchor.constraint(equalToConstant: 42),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        accessibilityElements = [nameLabel, detailLabel, primary, directions, close]
    }

    @objc private func primaryTapped() { onPrimary?() }
    @objc private func directionsTapped() { onDirections?() }
    @objc private func closeTapped() { onClose?() }
}

extension MapPlaceCalloutView.Model {
    /// What MapKit knows about a tapped place, and how far it is from them
    init(feature: MKMapFeatureAnnotation, userLocation: CLLocation?, isSaved: Bool) {
        let here = CLLocation(latitude: feature.coordinate.latitude, longitude: feature.coordinate.longitude)
        self.init(
            name: feature.title ?? "This place",
            detail: MapPlaceCalloutCopy.detail(category: feature.pointOfInterestCategory?.rawValue,
                                               meters: userLocation.map { $0.distance(from: here) }),
            icon: feature.iconStyle?.image,
            iconColor: feature.iconStyle?.backgroundColor,
            isSaved: isSaved
        )
    }
}
