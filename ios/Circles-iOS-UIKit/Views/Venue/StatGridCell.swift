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
            grid.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        accessoryType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tiles: [VenueAdminCopy.StatTile]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        StatTileView.grid(tiles).arrangedSubviews.forEach { grid.addArrangedSubview($0) }
    }
}
