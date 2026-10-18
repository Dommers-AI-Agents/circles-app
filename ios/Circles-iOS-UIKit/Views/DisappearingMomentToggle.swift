import UIKit

/// "Disappears after 24 hours" on the two moment post screens (the place
/// picker and the link screen). Off every time (Wes, 2026-10-18); turning it
/// on shows what it means.
final class DisappearingMomentToggle: UIView {
    private(set) var isOn = false

    private let toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = false
        toggle.onTintColor = Constants.Colors.primary
        return toggle
    }()

    private let note: UILabel = {
        let label = UILabel()
        label.text = "Deleted for everyone, including you, 24 hours after posting."
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "timer"))
        icon.tintColor = Constants.Colors.primary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = "Disappears after 24 hours"
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.textColor = Constants.Colors.label
        let line = UIStackView(arrangedSubviews: [icon, title, toggle])
        line.spacing = 8
        line.alignment = .center
        let stack = UIStackView(arrangedSubviews: [line, note])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        toggle.addTarget(self, action: #selector(changed), for: .valueChanged)
        accessibilityElements = [toggle]
        toggle.accessibilityLabel = "Disappears after 24 hours"
        toggle.accessibilityHint = "Deleted for everyone, including you, 24 hours after posting"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() {
        isOn = toggle.isOn
        UIView.animate(withDuration: 0.2) { self.note.isHidden = !self.isOn }
    }
}
