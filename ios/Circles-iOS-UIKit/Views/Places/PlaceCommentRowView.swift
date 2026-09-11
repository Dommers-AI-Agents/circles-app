import UIKit

/// One comment in the place page's inline comments section: avatar, name
/// (badged OWNER for the venue's verified owner), relative time, the text,
/// and a heart with its count. The page handles the like request; the row
/// reports the tap and applies the result.
final class PlaceCommentRowView: UIView {
    /// The heart was tapped; the button is passed so the caller can disable
    /// and animate it around the request.
    var onLikeTapped: ((UIButton) -> Void)?

    private let likeButton = UIButton(type: .system)
    private let likeCountLabel = UILabel()

    init(comment: PlaceComment) {
        super.init(frame: .zero)
        backgroundColor = Constants.Colors.background
        layer.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        // User info stack (avatar + name + time)
        let userInfoStack = UIStackView()
        userInfoStack.axis = .horizontal
        userInfoStack.spacing = 8
        userInfoStack.alignment = .center
        userInfoStack.translatesAutoresizingMaskIntoConstraints = false

        // Avatar
        let avatarImageView = UIImageView()
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.backgroundColor = Constants.Colors.tertiaryBackground
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.secondaryLabel
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        avatarImageView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        // Load avatar if available
        if let urlString = comment.user?.profilePicture, let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        avatarImageView.image = image
                    }
                }
            }.resume()
        }

        // Name and time stack
        let nameTimeStack = UIStackView()
        nameTimeStack.axis = .vertical
        nameTimeStack.spacing = 2

        let nameLabel = UILabel()
        nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = Constants.Colors.label
        let commentAuthorName = comment.user?.displayName ?? "Unknown User"
        if comment.isVenueOwner == true {
            // The store speaking on its own page — badge the name
            let attributed = NSMutableAttributedString(string: commentAuthorName)
            attributed.append(NSAttributedString(
                string: "  OWNER",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: Constants.Colors.primary,
                    .baselineOffset: 1
                ]
            ))
            nameLabel.attributedText = attributed
        } else {
            nameLabel.text = commentAuthorName
        }

        let timeLabel = UILabel()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.text = formatter.localizedString(for: comment.createdAt, relativeTo: Date())
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = Constants.Colors.secondaryLabel

        nameTimeStack.addArrangedSubview(nameLabel)
        nameTimeStack.addArrangedSubview(timeLabel)

        userInfoStack.addArrangedSubview(avatarImageView)
        userInfoStack.addArrangedSubview(nameTimeStack)

        // Like button
        likeButton.translatesAutoresizingMaskIntoConstraints = false
        likeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        likeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)

        // Like count label
        likeCountLabel.font = UIFont.systemFont(ofSize: 12)
        likeCountLabel.textColor = Constants.Colors.secondaryLabel
        likeCountLabel.translatesAutoresizingMaskIntoConstraints = false
        setLiked(comment.isLikedByCurrentUser, count: comment.displayLikesCount)

        // Comment text
        let commentLabel = UILabel()
        commentLabel.text = comment.text
        commentLabel.font = UIFont.systemFont(ofSize: 14)
        commentLabel.textColor = Constants.Colors.label
        commentLabel.numberOfLines = 0
        commentLabel.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        addSubview(userInfoStack)
        addSubview(likeButton)
        addSubview(likeCountLabel)
        addSubview(commentLabel)

        // Constraints
        NSLayoutConstraint.activate([
            userInfoStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            userInfoStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            likeButton.centerYAnchor.constraint(equalTo: userInfoStack.centerYAnchor),
            likeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            likeCountLabel.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            likeCountLabel.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -4),

            commentLabel.topAnchor.constraint(equalTo: userInfoStack.bottomAnchor, constant: 8),
            commentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            commentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            commentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Heart state and count, as returned by the like request.
    func setLiked(_ liked: Bool, count: Int) {
        likeButton.setImage(UIImage(systemName: liked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = liked ? .systemRed : Constants.Colors.secondaryLabel
        likeCountLabel.text = count > 0 ? "\(count)" : ""
    }

    @objc private func likeTapped() {
        onLikeTapped?(likeButton)
    }
}
