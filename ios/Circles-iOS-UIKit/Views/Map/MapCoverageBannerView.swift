import UIKit

/// The full-screen map's "nothing to show here" card: a two-line message,
/// an optional one-tap action, and a dismiss ✕. The controller decides
/// what it says and when it shows; the view only draws and reports taps.
final class MapCoverageBannerView: UIView {
    var onAction: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(UIColor(red: 0.36, green: 0.65, blue: 1.0, alpha: 1.0), for: .normal)
        button.contentEdgeInsets = .zero
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.55)
        button.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        layer.cornerRadius = 12
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let stack = UIStackView(arrangedSubviews: [label, actionButton])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),

            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sets the text; a nil action title hides the action row.
    func configure(message: String, actionTitle: String?) {
        label.text = message
        if let title = actionTitle {
            actionButton.setTitle(title, for: .normal)
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
    }

    @objc private func actionTapped() { onAction?() }
    @objc private func dismissTapped() { onDismiss?() }
}
