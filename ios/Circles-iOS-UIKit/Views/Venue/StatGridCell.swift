import UIKit

// MARK: - Stat grid cell

/// Two-column tiles (super-user store page and the owner's store page): big number, what it counts, and this month's change
final class StatGridCell: UITableViewCell {
    static let reuseId = "StatGridCell"

    private let grid: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        accessoryType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tiles: [VenueAdminCopy.StatTile]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stride(from: 0, to: tiles.count, by: 2).forEach { start in
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            row.alignment = .fill
            row.addArrangedSubview(tileView(tiles[start]))
            row.addArrangedSubview(start + 1 < tiles.count ? tileView(tiles[start + 1]) : UIView())
            grid.addArrangedSubview(row)
        }
    }

    private func tileView(_ tile: VenueAdminCopy.StatTile) -> UIView {
        let box = UIView()
        box.backgroundColor = .tertiarySystemGroupedBackground
        box.layer.cornerRadius = 12

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        let value = UILabel()
        value.text = "\(tile.value)"
        value.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        let title = UILabel()
        title.text = tile.title
        title.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let caption = UILabel()
        caption.text = tile.caption
        caption.font = UIFont.systemFont(ofSize: 12)
        caption.textColor = Constants.Colors.secondaryLabel
        caption.numberOfLines = 2
        let month = UILabel()
        month.text = tile.monthNote ?? " "
        month.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        month.textColor = Constants.Colors.success

        [value, title, caption, month].forEach { stack.addArrangedSubview($0) }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -10)
        ])
        box.isAccessibilityElement = true
        box.accessibilityLabel = "\(tile.title): \(tile.value). \(tile.caption). \(tile.monthNote ?? "")"
        return box
    }
}
