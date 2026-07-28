import UIKit

/// A rounded pill label (used for source-circle chips).
final class ChipLabel: UILabel {
    private let inset = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = Constants.Colors.primary
        backgroundColor = Constants.Colors.primary.withAlphaComponent(0.12)
        layer.cornerRadius = 11
        layer.masksToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
    }
}

/// A venue row in the city browse view: name, "Category · Neighborhood", and one
/// chip per circle the place belongs to ("one pin, every lens").
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
    private let iconView: UIImageView = {
        let v = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        v.tintColor = Constants.Colors.primary
        v.contentMode = .scaleAspectFit
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }()
    private let chipsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 6
        s.alignment = .leading
        return s
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let textStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel, chipsStack])
        textStack.axis = .vertical
        textStack.spacing = 4
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

        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Show up to 3 circle chips, then a "+N" overflow chip.
        let maxChips = 3
        for chip in venue.circles.prefix(maxChips) {
            let label = ChipLabel()
            label.text = chip.name
            chipsStack.addArrangedSubview(label)
        }
        if venue.circles.count > maxChips {
            let more = ChipLabel()
            more.text = "+\(venue.circles.count - maxChips)"
            chipsStack.addArrangedSubview(more)
        }
        chipsStack.isHidden = venue.circles.isEmpty
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
