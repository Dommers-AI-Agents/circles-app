import UIKit

protocol PartnerActionsRowViewDelegate: AnyObject {
    func partnerActionsRow(_ view: PartnerActionsRowView, didTap action: PlaceAction, sourceView: UIView)
}

/// The place page's action buttons (Menu, the store's own links, Delivery /
/// Reservations / Ride), ranked by PlaceActionPlanner. Styling matches the
/// practical chips row directly above it; three to a row, a second row when
/// the store set up more. Collapses to zero height when empty — the hosting
/// controller owns the collapse constraint (`height(for:)`).
class PartnerActionsRowView: UIView {

    weak var delegate: PartnerActionsRowViewDelegate?

    private var actions: [PlaceAction] = []

    static let perRow = 3
    static let chipHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 10

    static func height(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = CGFloat((count + perRow - 1) / perRow)
        return rows * chipHeight + (rows - 1) * rowSpacing
    }

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = PartnerActionsRowView.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuilds the chips. Empty array clears the row (host collapses it).
    func configure(with actions: [PlaceAction]) {
        self.actions = actions
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row: UIStackView?
        for (index, action) in actions.enumerated() {
            if index % Self.perRow == 0 {
                let next = UIStackView()
                next.axis = .horizontal
                next.distribution = .fillEqually
                next.spacing = 10
                stackView.addArrangedSubview(next)
                row = next
            }
            let chip = Self.chip(title: action.title, systemName: action.icon)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            row?.addArrangedSubview(chip)
        }
        // A short last row keeps chips the same width as the rows above
        if let row, actions.count > Self.perRow {
            for _ in 0..<((Self.perRow - actions.count % Self.perRow) % Self.perRow) { row.addArrangedSubview(UIView()) }
        }
    }

    private static func chip(title: String, systemName: String) -> UIButton {
        let button = UIButton(type: .system)
        // Server-supplied SF Symbol name — fall back so a typo'd catalog edit
        // still renders a tappable chip
        let image = UIImage(systemName: systemName) ?? UIImage(systemName: "arrow.up.right.square")
        button.setImage(image, for: .normal)
        button.setTitle(" \(title)", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.tintColor = Constants.Colors.primary
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard sender.tag < actions.count else { return }
        delegate?.partnerActionsRow(self, didTap: actions[sender.tag], sourceView: sender)
    }
}
