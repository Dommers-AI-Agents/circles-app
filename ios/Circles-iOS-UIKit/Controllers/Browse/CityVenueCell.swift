import UIKit

/// A venue row in the city browse view: name, "Category · Neighborhood", and a
/// meta line with the star rating and who added it ("★ 4.5 · Added by Wes").
/// The disclosure arrow opens the place page.
final class CityVenueCell: UITableViewCell {
    static let reuseId = "CityVenueCell"

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.numberOfLines = 2
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = Constants.Colors.secondaryLabel
        return l
    }()
    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = Constants.Colors.secondaryLabel
        l.numberOfLines = 1
        return l
    }()
    private let iconView: UIImageView = {
        let v = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        v.tintColor = Constants.Colors.primary
        v.contentMode = .scaleAspectFit
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let textStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        let row = UIStackView(arrangedSubviews: [iconView, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        accessoryType = .disclosureIndicator
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with venue: CityVenue) {
        nameLabel.text = venue.name
        subtitleLabel.text = venue.subtitle

        // "★ 4.5 · Added by Wes" — omit either part if missing.
        let parts = [venue.ratingText, venue.addedByText].compactMap { $0 }
        metaLabel.text = parts.joined(separator: "  ·  ")
        metaLabel.isHidden = parts.isEmpty
    }
}
