import UIKit

/// The "nothing here yet" block: an icon, a title, a message and, when
/// there's something to do about it, one button (UIButton factory).
final class EmptyStateView: UIView {

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = Constants.Colors.secondaryLabel
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private(set) var actionButton: UIButton?
    private var action: (() -> Void)?

    /// - Parameters:
    ///   - systemImage: SF Symbol name for the icon (nil: no icon).
    ///   - buttonTitle / action: an optional primary button under the text.
    init(systemImage: String? = nil, title: String, message: String? = nil,
         buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48)
        ])
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        stack.setCustomSpacing(16, after: messageLabel)
        configure(systemImage: systemImage, title: title, message: message,
                  buttonTitle: buttonTitle, action: action)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(systemImage: String? = nil, title: String, message: String? = nil,
                   buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        iconView.image = systemImage.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .regular))
        }
        iconView.isHidden = iconView.image == nil
        titleLabel.text = title
        messageLabel.text = message
        messageLabel.isHidden = (message ?? "").isEmpty

        actionButton?.removeFromSuperview()
        actionButton = nil
        self.action = action
        if let buttonTitle, action != nil {
            let button = UIButton.primaryButton(title: buttonTitle)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
            button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
            stack.addArrangedSubview(button)
            actionButton = button
        }
    }

    @objc private func buttonTapped() {
        action?()
    }
}
