import UIKit

/// Business storefront card shown on a brand account's profile, between the
/// header and the circles area. Renders what the storefront has: name, about,
/// links, the "Find us at" circle, and a live-offers line. Collapsed to zero
/// height on non-business profiles (the profile owns the height constraint).
class StorefrontCardView: UIView {

    var onWebsite: (() -> Void)?
    var onCatalog: (() -> Void)?
    var onFindUsAt: (() -> Void)?
    var onOffers: (() -> Void)?
    var onEdit: (() -> Void)?

    private let card: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 14
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "storefront.fill"))
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        label.textColor = Constants.Colors.label
        return label
    }()

    private lazy var editButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pencil.circle"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.isHidden = true
        button.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        button.accessibilityLabel = "Edit storefront"
        return button
    }()

    private let aboutLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 3
        return label
    }()

    private lazy var websiteButton = makeLinkButton(title: "Website", icon: "globe", action: #selector(websiteTapped))
    private lazy var catalogButton = makeLinkButton(title: "Catalog", icon: "book", action: #selector(catalogTapped))

    private lazy var findUsAtButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.setTitleColor(Constants.Colors.label, for: .normal)
        button.addTarget(self, action: #selector(findUsAtTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var offersLabel: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.addTarget(self, action: #selector(offersTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        addSubview(card)

        let headerRow = UIStackView(arrangedSubviews: [iconView, nameLabel, UIView(), editButton])
        headerRow.axis = .horizontal
        headerRow.spacing = 8
        headerRow.alignment = .center

        let linksRow = UIStackView(arrangedSubviews: [websiteButton, catalogButton, UIView()])
        linksRow.axis = .horizontal
        linksRow.spacing = 10

        let stack = UIStackView(arrangedSubviews: [headerRow, aboutLabel, linksRow, findUsAtButton, offersLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // The card's bottom hugs the content at less-than-required priority so
        // the profile can pin this whole view to height 0 without a constraint
        // conflict when the profile isn't a business.
        let cardBottom = card.bottomAnchor.constraint(equalTo: bottomAnchor)
        cardBottom.priority = .defaultHigh
        let stackBottom = stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        stackBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardBottom,

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stackBottom
        ])
    }

    private func makeLinkButton(title: String, icon: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.setTitle(" \(title)", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.isHidden = true
        return button
    }

    /// Renders the storefront. Pass `findUsAtCircle`/`venues` when the full
    /// storefront read has landed; the card shows what it has.
    func configure(storefront: StorefrontInfo, findUsAtCircle: StorefrontCircleSummary?,
                   venues: [OfferVenue]?, isOwnProfile: Bool) {
        nameLabel.text = storefront.businessName ?? "Storefront"
        editButton.isHidden = !isOwnProfile

        aboutLabel.text = storefront.about
        aboutLabel.isHidden = (storefront.about ?? "").isEmpty

        websiteButton.isHidden = (storefront.website ?? "").isEmpty
        catalogButton.isHidden = (storefront.catalogUrl ?? "").isEmpty

        if let circle = findUsAtCircle {
            let count = circle.placesCount ?? 0
            let suffix = count > 0 ? " · \(count) \(count == 1 ? "stop" : "stops")" : ""
            findUsAtButton.setTitle("📍 Find us at: \(circle.name)\(suffix)  ›", for: .normal)
            findUsAtButton.isHidden = false
        } else {
            findUsAtButton.isHidden = true
        }

        let offerCount = (venues ?? []).reduce(0) { $0 + $1.offers.count }
        let announcementCount = (venues ?? []).reduce(0) { $0 + ($1.announcements?.count ?? 0) }
        if offerCount > 0 || announcementCount > 0 {
            var parts: [String] = []
            if offerCount > 0 { parts.append("\(offerCount) \(offerCount == 1 ? "offer" : "offers")") }
            if announcementCount > 0 { parts.append("\(announcementCount) \(announcementCount == 1 ? "announcement" : "announcements")") }
            offersLabel.setTitle("🎁 \(parts.joined(separator: " · "))  ›", for: .normal)
            offersLabel.isHidden = false
        } else {
            offersLabel.isHidden = true
        }
    }

    @objc private func websiteTapped() { onWebsite?() }
    @objc private func catalogTapped() { onCatalog?() }
    @objc private func findUsAtTapped() { onFindUsAt?() }
    @objc private func offersTapped() { onOffers?() }
    @objc private func editTapped() { onEdit?() }
}
