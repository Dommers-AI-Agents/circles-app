import UIKit

/// Horizontal, scrollable row of category filter chips for the city browse view.
/// Only the groups passed in are shown (adaptive), with the selected one filled.
final class CategoryChipBar: UIView {

    var onSelect: ((PlaceCategoryGroup) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [(group: PlaceCategoryGroup, button: UIButton)] = []
    private(set) var selected: PlaceCategoryGroup = .all

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setGroups(_ groups: [PlaceCategoryGroup], selected: PlaceCategoryGroup = .all) {
        self.selected = groups.contains(selected) ? selected : .all
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = groups.map { group in
            let b = makeChip(group.title)
            b.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
            return (group, b)
        }
        updateSelectionUI()
    }

    private func makeChip(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.layer.cornerRadius = 16
        b.layer.masksToBounds = true
        b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        return b
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard let match = buttons.first(where: { $0.button === sender }) else { return }
        selected = match.group
        updateSelectionUI()
        onSelect?(match.group)
    }

    private func updateSelectionUI() {
        for (group, button) in buttons {
            let isOn = group == selected
            button.backgroundColor = isOn ? Constants.Colors.primary : Constants.Colors.primary.withAlphaComponent(0.10)
            button.setTitleColor(isOn ? .white : Constants.Colors.primary, for: .normal)
        }
    }
}
