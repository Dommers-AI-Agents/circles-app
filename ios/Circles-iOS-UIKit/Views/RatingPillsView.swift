import UIKit

/// The 0–10 pill row used by the rating sheet and the check-in screen.
/// `currentRating` is outlined ("this is what you said last time");
/// `selectedRating` is filled. Tapping a pill selects it and fires `onSelect`.
final class RatingPillsView: UIView {
    var onSelect: ((Int) -> Void)?

    private(set) var selectedRating: Int?
    private let currentRating: Int?
    private var buttons: [UIButton] = []

    init(currentRating: Int? = nil) {
        self.currentRating = currentRating
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        for value in 0...10 {
            let button = UIButton(type: .system)
            button.setTitle("\(value)", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            button.setTitleColor(Constants.Colors.label, for: .normal)
            button.backgroundColor = Constants.Colors.secondaryBackground
            button.layer.cornerRadius = 8
            if value == currentRating {
                button.layer.borderWidth = 2
                button.layer.borderColor = Constants.Colors.primary.cgColor
            }
            button.tag = value
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(pillTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ rating: Int?) {
        selectedRating = rating
        for button in buttons {
            let selected = button.tag == rating
            button.backgroundColor = selected ? Constants.Colors.primary : Constants.Colors.secondaryBackground
            button.setTitleColor(selected ? .white : Constants.Colors.label, for: .normal)
        }
    }

    @objc private func pillTapped(_ sender: UIButton) {
        select(sender.tag)
        onSelect?(sender.tag)
    }
}
