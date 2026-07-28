import UIKit

/// Generic horizontal scrollable chip selector (used for the People filter in
/// the city browse view). Same pill styling as the category chips.
final class BrowseChipBar: UIView {

    struct Item { let id: String; let title: String }

    var onSelect: ((String) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [(id: String, button: UIButton)] = []
    private(set) var selectedId: String?

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

    func setItems(_ items: [Item], selectedId: String) {
        self.selectedId = items.contains(where: { $0.id == selectedId }) ? selectedId : items.first?.id
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = items.map { item in
            let b = makeChip(item.title)
            b.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
            return (item.id, b)
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
        selectedId = match.id
        updateSelectionUI()
        onSelect?(match.id)
    }

    private func updateSelectionUI() {
        for (id, button) in buttons {
            let isOn = id == selectedId
            button.backgroundColor = isOn ? Constants.Colors.primary : Constants.Colors.primary.withAlphaComponent(0.10)
            button.setTitleColor(isOn ? .white : Constants.Colors.primary, for: .normal)
        }
    }
}
