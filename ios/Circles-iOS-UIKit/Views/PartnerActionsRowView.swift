import UIKit

protocol PartnerActionsRowViewDelegate: AnyObject {
    func partnerActionsRow(_ view: PartnerActionsRowView, didTap group: PartnerActionGroup, sourceView: UIView)
}

/// Horizontal row of server-driven partner action chips (Delivery / Reserve /
/// Ride) on the place detail screen. Styling matches the practical chips row
/// directly above it; max 3 groups fit untruncated (enforced upstream by
/// PartnerActionsService.eligibleGroups). Collapses to zero height when empty —
/// the hosting controller owns the collapse constraint.
class PartnerActionsRowView: UIView {

    weak var delegate: PartnerActionsRowViewDelegate?

    private var groups: [PartnerActionGroup] = []

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
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
    func configure(with groups: [PartnerActionGroup]) {
        self.groups = groups
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, group) in groups.enumerated() {
            let chip = Self.chip(title: group.title, systemName: group.icon)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(chip)
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
        guard sender.tag < groups.count else { return }
        delegate?.partnerActionsRow(self, didTap: groups[sender.tag], sourceView: sender)
    }
}
