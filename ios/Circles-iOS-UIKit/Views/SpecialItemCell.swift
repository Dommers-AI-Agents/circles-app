import UIKit

/// One row in the home-page Specials tab: a live offer or announcement from a
/// participating venue. Flat list — one row per deal, venue repeated as the
/// subtitle. Structure mirrors NewsArticleCell.
struct SpecialItem {
    enum Kind {
        case offer(RewardOffer)
        case announcement(VenueAnnouncement)
    }

    let venue: OfferVenue
    let kind: Kind

    var title: String {
        switch kind {
        case .offer(let offer): return offer.title
        case .announcement(let announcement): return announcement.title
        }
    }
}

class SpecialItemCell: UITableViewCell {

    static let identifier = "SpecialItemCell"

    // Guards against a recycled cell showing a stale async image
    private var currentImageLoadId: String?

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.05
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Announcement rows only: the announcement message
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let venueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Trailing badge: "{pts} pts" for offers, megaphone for announcements
    private let badgeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Constants.Colors.primary
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let badgeIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "megaphone.fill"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemOrange
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(containerView)
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(venueLabel)
        containerView.addSubview(badgeLabel)
        containerView.addSubview(badgeIconView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            thumbnailImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 60),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 60),
            thumbnailImageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 12),

            badgeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            badgeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            badgeIconView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            badgeIconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 18),
            badgeIconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -8),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            venueLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            venueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            venueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            venueLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    func configure(with item: SpecialItem) {
        titleLabel.text = item.title

        var venueText = item.venue.venueName
        if let distance = item.venue.distanceDisplay {
            venueText += " · \(distance)"
        }
        venueLabel.text = venueText

        switch item.kind {
        case .offer(let offer):
            messageLabel.text = nil
            badgeLabel.text = "\(offer.pointsCost) pts"
            badgeLabel.isHidden = false
            badgeIconView.isHidden = true
        case .announcement(let announcement):
            messageLabel.text = announcement.message
            badgeLabel.isHidden = true
            badgeIconView.isHidden = false
        }

        currentImageLoadId = nil
        if let photoUrl = item.venue.photoUrl {
            let loadId = UUID().uuidString
            currentImageLoadId = loadId
            thumbnailImageView.contentMode = .scaleAspectFill
            thumbnailImageView.image = nil
            ImageService.shared.loadImageWithKey(from: photoUrl, cacheKey: "special-\(item.venue.venueId)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, self.currentImageLoadId == loadId else { return }
                    if let image = image {
                        self.thumbnailImageView.image = image
                    } else {
                        self.showPlaceholder()
                    }
                }
            }
        } else {
            showPlaceholder()
        }
    }

    private func showPlaceholder() {
        thumbnailImageView.contentMode = .center
        thumbnailImageView.image = UIImage(systemName: "storefront")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentImageLoadId = nil
        thumbnailImageView.image = nil
        titleLabel.text = nil
        messageLabel.text = nil
        venueLabel.text = nil
        badgeLabel.text = nil
    }
}
