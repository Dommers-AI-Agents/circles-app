import UIKit

/// The chat's navigation title for a one-on-one chat (2026-11-23): the
/// person's photo and name, tappable, opening their profile.
final class ChatTitleView: UIControl {
    private static let avatarSide: CGFloat = 32
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right",
                                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
    private var avatarURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = Self.avatarSide / 2
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        chevron.tintColor = .tertiaryLabel
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel, chevron])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.setCustomSpacing(4, after: nameLabel)
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: Self.avatarSide),
            avatar.heightAnchor.constraint(equalToConstant: Self.avatarSide),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, avatarURL: String?, seed: String) {
        nameLabel.text = name
        accessibilityLabel = name
        accessibilityHint = "Opens their profile"
        avatar.image = AvatarPlaceholder.image(name: name, seed: seed, diameter: Self.avatarSide)
        self.avatarURL = avatarURL
        guard let avatarURL, !avatarURL.isEmpty else { return }
        ImageService.shared.loadImage(from: avatarURL) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.avatarURL == avatarURL, let image else { return }
                self.avatar.image = image
            }
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }
}

/// "Today" / "Yesterday" / a date between two days of a chat
final class ChatDayCell: UITableViewCell {
    static let reuseIdentifier = "ChatDayCell"
    private let pill = UIView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        pill.backgroundColor = UIColor.secondarySystemFill
        pill.layer.cornerRadius = 11
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pill)
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            pill.heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        label.text = title
        accessibilityLabel = title
    }
}

/// A chat with nothing in it yet: who it is with and two ways to start, so
/// the page is never blank.
final class ChatEmptyStateView: UIView {
    var onWave: (() -> Void)?
    var onSharePlace: (() -> Void)?

    private static let avatarSide: CGFloat = 84
    private let avatar = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let waveButton = UIButton.smallActionButton(title: "👋  Wave", style: .primary)
    private let placeButton = UIButton.smallActionButton(title: "Share a place", style: .secondary)
    private var avatarURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        for button in [waveButton, placeButton] {
            button.layer.cornerRadius = 18
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        }
        waveButton.addTarget(self, action: #selector(waveTapped), for: .touchUpInside)
        placeButton.addTarget(self, action: #selector(placeTapped), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [waveButton, placeButton])
        buttons.axis = .horizontal
        buttons.spacing = 10

        let stack = UIStackView(arrangedSubviews: [avatar, titleLabel, bodyLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(16, after: avatar)
        stack.setCustomSpacing(20, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: Self.avatarSide),
            avatar.heightAnchor.constraint(equalToConstant: Self.avatarSide),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `firstName` nil = a group chat
    func configure(name: String, firstName: String?, avatarURL: String?, seed: String, isGroup: Bool) {
        if isGroup {
            titleLabel.text = name
            bodyLabel.text = "Nobody has said anything yet. Start the chat, or share a place everyone should know."
            avatar.layer.cornerRadius = AvatarPlaceholder.groupCornerRadius(for: Self.avatarSide)
            avatar.layer.cornerCurve = .continuous
            avatar.image = AvatarPlaceholder.groupImage(seed: seed, side: Self.avatarSide)
        } else {
            let who = firstName ?? name
            titleLabel.text = "Say hi to \(who)"
            bodyLabel.text = "Messages, places and circles you share with \(who) show up here."
            avatar.layer.cornerRadius = Self.avatarSide / 2
            avatar.image = AvatarPlaceholder.image(name: name, seed: seed, diameter: Self.avatarSide)
        }
        self.avatarURL = avatarURL
        guard let avatarURL, !avatarURL.isEmpty else { return }
        ImageService.shared.loadImage(from: avatarURL) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.avatarURL == avatarURL, let image else { return }
                self.avatar.image = image
            }
        }
    }

    @objc private func waveTapped() { onWave?() }
    @objc private func placeTapped() { onSharePlace?() }
}
