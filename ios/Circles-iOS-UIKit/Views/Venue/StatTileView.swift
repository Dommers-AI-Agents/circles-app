import UIKit

/// One stat tile: big number, what it counts, a caption, and this month's
/// change. Two to a row in `StatGridCell` and on the owner's Insights page.
enum StatTileView {
    static func make(_ tile: VenueAdminCopy.StatTile) -> UIView {
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

    /// Tiles two to a row, as a vertical stack
    static func grid(_ tiles: [VenueAdminCopy.StatTile], spacing: CGFloat = 10) -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = spacing
        stride(from: 0, to: tiles.count, by: 2).forEach { start in
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = spacing
            row.distribution = .fillEqually
            row.alignment = .fill
            row.addArrangedSubview(make(tiles[start]))
            row.addArrangedSubview(start + 1 < tiles.count ? make(tiles[start + 1]) : UIView())
            grid.addArrangedSubview(row)
        }
        return grid
    }
}
