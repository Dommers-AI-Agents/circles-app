// Views/ConversationCell.swift
// One row of the conversations list: avatar (or group marker), name,
// last message, time and unread state. Moved out of the controller file.

import UIKit

// MARK: - ConversationCell
class ConversationCell: UITableViewCell {

    private static let avatarSide: CGFloat = 56
    private static let groupMarkerSide: CGFloat = 22

    // Store the conversation ID for stable selection
    private(set) var conversationId: String?

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    /// Small "two people" marker pinned to the corner of a group avatar. The
    /// avatar shape already says "group" for placeholders; this keeps saying it
    /// once a group has a real photo, which is otherwise indistinguishable from
    /// a person's photo.
    private let groupMarkerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = ConversationCell.groupMarkerSide / 2
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        glyph.image = UIImage(systemName: "person.2.fill", withConfiguration: config)
        glyph.tintColor = .white
        glyph.contentMode = .center
        glyph.backgroundColor = Constants.Colors.primary
        glyph.layer.cornerRadius = (ConversationCell.groupMarkerSide - 4) / 2
        glyph.clipsToBounds = true
        glyph.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: ConversationCell.groupMarkerSide - 4),
            glyph.heightAnchor.constraint(equalToConstant: ConversationCell.groupMarkerSide - 4)
        ])
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let unreadBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        conversationId = nil
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        avatarImageView.backgroundColor = .systemGray5
        applyAvatarShape(isGroup: false)
        groupMarkerView.isHidden = true
        nameLabel.text = nil
        messageLabel.text = nil
        timeLabel.text = nil
        unreadBadge.isHidden = true
        messageLabel.font = .systemFont(ofSize: 14)
        accessibilityLabel = nil
    }

    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(groupMarkerView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(unreadBadge)

        applyAvatarShape(isGroup: false)

        let side = ConversationCell.avatarSide
        let marker = ConversationCell.groupMarkerSide

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: side),
            avatarImageView.heightAnchor.constraint(equalToConstant: side),

            // Overlaps the avatar's bottom-right corner by a third of its size
            groupMarkerView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: marker / 3),
            groupMarkerView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: marker / 3),
            groupMarkerView.widthAnchor.constraint(equalToConstant: marker),
            groupMarkerView.heightAnchor.constraint(equalToConstant: marker),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            unreadBadge.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    /// People are circles, groups are rounded squares. Same silhouette whether
    /// the image is a placeholder or a loaded photo.
    private func applyAvatarShape(isGroup: Bool) {
        let side = ConversationCell.avatarSide
        avatarImageView.layer.cornerRadius = isGroup
            ? AvatarPlaceholder.groupCornerRadius(for: side)
            : side / 2
        avatarImageView.layer.cornerCurve = isGroup ? .continuous : .circular
    }

    func configure(with conversation: Conversation) {
        // Store the conversation ID for stable selection
        self.conversationId = conversation.id

        nameLabel.text = conversation.displayName
        timeLabel.text = conversation.formattedLastMessageTime ?? ""

        // Log unread count for debugging
        Logger.debug("📱 ConversationCell: \(conversation.displayName) - unreadCount: \(conversation.unreadCount), hasUnread: \(conversation.hasUnreadMessages)")

        let isGroup = conversation.type == .group
        applyAvatarShape(isGroup: isGroup)
        groupMarkerView.isHidden = !isGroup

        switch conversation.type {
        case .direct:
            let other = conversation.participantDetails?.first
            avatarImageView.image = AvatarPlaceholder.image(
                name: other?.displayName,
                seed: other?.id,
                diameter: ConversationCell.avatarSide
            )
            if let other = other {
                loadAvatar(userId: other.id, urlString: other.profilePicture, for: conversation.id)
            }
            messageLabel.text = conversation.lastMessage ?? "No messages yet"

        case .group:
            avatarImageView.image = AvatarPlaceholder.groupImage(
                seed: conversation.id,
                side: ConversationCell.avatarSide
            )
            loadAvatar(userId: conversation.id, urlString: conversation.avatar, for: conversation.id)
            let members = conversation.participants.count
            messageLabel.text = conversation.lastMessagePreview
                ?? (members > 0 ? "\(members) member\(members == 1 ? "" : "s")" : "No messages yet")

        case .system:
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .systemGray3
            messageLabel.text = conversation.lastMessage ?? "No messages yet"
        }

        // Configure unread badge
        if conversation.hasUnreadMessages {
            unreadBadge.isHidden = false
            unreadBadge.text = "\(conversation.unreadCount)"
            messageLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        } else {
            unreadBadge.isHidden = true
            messageLabel.font = .systemFont(ofSize: 14)
        }

        // The marker is visual only; say "group" for VoiceOver too. Direct rows
        // keep UIKit's default label built from the subviews.
        if isGroup {
            var parts = ["Group chat", conversation.displayName]
            if let message = messageLabel.text { parts.append(message) }
            if let time = timeLabel.text, !time.isEmpty { parts.append(time) }
            if !unreadBadge.isHidden, let count = unreadBadge.text { parts.append("\(count) unread") }
            accessibilityLabel = parts.joined(separator: ", ")
        }
    }

    /// Loads a photo over the placeholder. Guarded on the conversation id so a
    /// slow load for a recycled cell can't paint the wrong row.
    private func loadAvatar(userId: String, urlString: String?, for conversationId: String) {
        guard let urlString = urlString, !urlString.isEmpty else { return }
        ImageService.shared.loadProfileImage(for: userId, from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self, let image = image, self.conversationId == conversationId else { return }
                self.avatarImageView.image = image
                self.avatarImageView.tintColor = nil
            }
        }
    }
}
