import UIKit

/// A person in a list: avatar, name, a subtitle line and an optional trailing
/// button (Follow, Connect…). Lists of people should use this rather than a
/// screen-specific cell.
class UserRowCell: UITableViewCell {

    static let reuseIdentifier = "UserRowCell"

    let avatarView = AvatarView(diameter: 50)

    let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// The trailing button, when one was set with `setTrailingButton`.
    private(set) var trailingButton: UIButton?
    private var trailingAction: (() -> Void)?
    private var textTrailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Constants.Colors.background
        selectionStyle = .default

        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(subtitleLabel)

        let guide = contentView.safeAreaLayoutGuide
        textTrailing = textStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            textTrailing
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Name and photo from the user; `subtitle` is whatever the list wants
    /// under the name (nil hides the line).
    func configure(with user: User, subtitle: String?) {
        nameLabel.text = user.displayName
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
        avatarView.configure(with: user)
    }

    /// Adds (or replaces) the trailing button; nil removes it.
    func setTrailingButton(_ button: UIButton?, action: (() -> Void)? = nil) {
        trailingButton?.removeFromSuperview()
        trailingButton = nil
        trailingAction = action
        textTrailing.isActive = false
        guard let button else {
            textTrailing = textStack.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
            textTrailing.isActive = true
            return
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(trailingTapped), for: .touchUpInside)
        contentView.addSubview(button)
        textTrailing = textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textTrailing
        ])
        trailingButton = button
    }

    @objc private func trailingTapped() {
        trailingAction?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.reset()
        nameLabel.text = nil
        subtitleLabel.text = nil
        setTrailingButton(nil)
    }
}
