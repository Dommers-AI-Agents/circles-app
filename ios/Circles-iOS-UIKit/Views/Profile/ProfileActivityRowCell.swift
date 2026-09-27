import UIKit

/// One row of Profile › Activity: a tinted icon tile, the title and detail
/// lines, and on the right either the time or a thumbnail.
final class ProfileActivityRowCell: UITableViewCell {
    static let reuseIdentifier = "ProfileActivityRowCell"

    private let card = UIView()
    private let tile = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let timeLabel = UILabel()
    private let thumb = UIImageView()
    private var thumbWidth: NSLayoutConstraint?
    private var loadedThumbUrl: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        tile.layer.cornerRadius = 10
        tile.layer.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.numberOfLines = 2
        detailLabel.font = UIFont.systemFont(ofSize: 12)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.numberOfLines = 2
        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = Constants.Colors.tertiaryLabel
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 8
        thumb.backgroundColor = Constants.Colors.tertiaryBackground
        let trailing = UIStackView(arrangedSubviews: [timeLabel, thumb])
        trailing.axis = .vertical
        trailing.alignment = .trailing
        trailing.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(tile)
        card.addSubview(text)
        card.addSubview(trailing)
        thumbWidth = thumb.widthAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),

            tile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            tile.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 40),
            tile.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),

            text.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            text.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            text.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -10),

            trailing.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            thumbWidth!,
            thumb.heightAnchor.constraint(equalToConstant: 44),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.image = nil
        loadedThumbUrl = nil
    }

    func configure(item: OwnActivityItem) {
        let kind = ProfileActivityTimeline.Kind(category: item.category)
        paint(kind: kind, symbolName: kind.symbolName)
        titleLabel.text = ProfileActivityTimeline.title(for: item)
        let detail = ProfileActivityTimeline.detail(for: item)
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        timeLabel.text = Self.timeFormatter.string(from: item.timestamp)
        if let url = item.thumbnailUrl, kind == .moment || kind == .sent {
            showThumb(url: url)
        } else {
            hideThumb()
        }
        accessibilityLabel = [titleLabel.text, detail, timeLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    func configure(digest items: [OwnActivityItem]) {
        paint(kind: .social, symbolName: "heart")
        titleLabel.text = ProfileActivityTimeline.digestTitle(items)
        detailLabel.text = "Likes, comments and follows, grouped for the day"
        detailLabel.isHidden = false
        timeLabel.text = items.count == 1 ? "1 item" : "\(items.count) items"
        hideThumb()
        accessibilityLabel = titleLabel.text
    }

    private func paint(kind: ProfileActivityTimeline.Kind, symbolName: String) {
        let tint: UIColor
        switch kind {
        case .checkIn: tint = UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)
        case .place: tint = UIColor(red: 0.26, green: 0.22, blue: 0.79, alpha: 1)
        case .moment: tint = UIColor(red: 0.75, green: 0.07, blue: 0.24, alpha: 1)
        case .sent: tint = UIColor(red: 0.71, green: 0.33, blue: 0.04, alpha: 1)
        case .social, .other: tint = Constants.Colors.secondaryLabel
        }
        tile.backgroundColor = tint.withAlphaComponent(0.14)
        icon.tintColor = tint
        icon.image = UIImage(systemName: symbolName)
    }

    private func showThumb(url: String) {
        thumb.isHidden = false
        thumbWidth?.constant = 44
        timeLabel.isHidden = true
        loadedThumbUrl = url
        if let cached = ImageService.shared.getCachedImage(for: url) {
            thumb.image = cached
            return
        }
        ImageService.shared.loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadedThumbUrl == url else { return }
                self.thumb.image = image
            }
        }
    }

    private func hideThumb() {
        thumb.isHidden = true
        thumbWidth?.constant = 0
        timeLabel.isHidden = false
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
