import UIKit

/// Bold "Upgrade to FavCircles Business" promo shown to free-tier owners at
/// the top of venue screens (manage hub, stats dashboard). Solid primary
/// background so it stands out from regular content. Tapping runs `onTap` —
/// present the Business paywall for the venue on screen.
final class BusinessUpsellBanner: UIView {

    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.primary
        layer.cornerRadius = 12

        let iconCircle = UIView()
        iconCircle.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        iconCircle.layer.cornerRadius = 18
        iconCircle.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Upgrade to FavCircles Business"
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Offers, announcements, loyalty rewards & full stats for this store."
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.9)
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconCircle)
        iconCircle.addSubview(icon)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            iconCircle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconCircle.widthAnchor.constraint(equalToConstant: 36),
            iconCircle.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            titleLabel.leadingAnchor.constraint(equalTo: iconCircle.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Upgrade to FavCircles Business"
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onTap?()
    }
}
