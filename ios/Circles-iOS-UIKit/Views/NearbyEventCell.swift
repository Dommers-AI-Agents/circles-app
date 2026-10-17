import UIKit

/// A "Happening nearby" row on the Locals tab: the event's picture, name,
/// when, where, and a "Free" or price chip. Also draws a farmers market
/// (name, "Farmers market", address and distance).
final class NearbyEventCell: UITableViewCell {
    static let identifier = "NearbyEventCell"

    private var currentImageLoadId: String?

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

    private let whenLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let placeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let priceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Constants.Colors.secondaryLabel
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.addSubview(containerView)
        [thumbnailImageView, titleLabel, whenLabel, placeLabel, priceLabel].forEach(containerView.addSubview)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            thumbnailImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 96),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 64),
            thumbnailImageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 12),
            thumbnailImageView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),

            priceLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            priceLabel.firstBaselineAnchor.constraint(equalTo: whenLabel.firstBaselineAnchor),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            whenLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            whenLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            whenLabel.trailingAnchor.constraint(lessThanOrEqualTo: priceLabel.leadingAnchor, constant: -8),

            placeLabel.topAnchor.constraint(equalTo: whenLabel.bottomAnchor, constant: 2),
            placeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            placeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            placeLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with event: NearbyEvent) {
        titleLabel.text = event.name
        whenLabel.text = NearbyEventFormatter.dateLine(localDate: event.startLocalDate, localTime: event.startLocalTime)
        whenLabel.numberOfLines = 1
        placeLabel.text = NearbyEventFormatter.placeLine(venueName: event.venueName, city: event.city, distanceMeters: event.distanceMeters)
        priceLabel.text = event.isFree == true ? "Free" : NearbyEventFormatter.priceText(min: event.priceMin, currency: event.currency)
        priceLabel.textColor = event.isFree == true ? .systemGreen : Constants.Colors.secondaryLabel
        placeholderSymbol = event.isStoreEvent ? "storefront" : (event.source == "library" ? "books.vertical" : "ticket")
        accessibilityLabel = [titleLabel.text, whenLabel.text, placeLabel.text, priceLabel.text].compactMap { $0 }.joined(separator: ", ")
        isAccessibilityElement = true

        loadImage(event.imageUrl, key: "nearby-event-\(event.id)")
    }

    func configure(with market: FarmersMarket) {
        titleLabel.text = market.name
        // Its days and times when Google knows them
        whenLabel.text = market.hoursSummary ?? "Farmers market"
        whenLabel.numberOfLines = 2
        placeLabel.text = NearbyEventFormatter.placeLine(venueName: market.address, city: nil, distanceMeters: market.distanceMeters)
        priceLabel.text = market.acceptsSnap == true ? "SNAP/EBT" : nil
        priceLabel.textColor = Constants.Colors.secondaryLabel
        placeholderSymbol = "basket.fill"
        accessibilityLabel = [titleLabel.text, whenLabel.text, placeLabel.text, priceLabel.text].compactMap { $0 }.joined(separator: ", ")
        isAccessibilityElement = true
        loadImage(market.photoUrl, key: "market-\(market.id)")
    }

    private var placeholderSymbol = "ticket"

    private func loadImage(_ imageUrl: String?, key: String) {
        currentImageLoadId = nil
        guard let imageUrl else { return showPlaceholder() }
        let loadId = UUID().uuidString
        currentImageLoadId = loadId
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.image = nil
        ImageService.shared.loadImageWithKey(from: imageUrl, cacheKey: key) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.currentImageLoadId == loadId else { return }
                if let image { self.thumbnailImageView.image = image } else { self.showPlaceholder() }
            }
        }
    }

    private func showPlaceholder() {
        thumbnailImageView.contentMode = .center
        thumbnailImageView.image = UIImage(systemName: placeholderSymbol)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentImageLoadId = nil
        thumbnailImageView.image = nil
        titleLabel.text = nil
        whenLabel.text = nil
        placeLabel.text = nil
        priceLabel.text = nil
    }
}
