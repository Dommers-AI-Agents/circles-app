import UIKit

// MARK: - AllUsersCell
///
/// The cell reports *intent* (`RelationshipTier.Action`) rather than naming a
/// specific button, so adding a rung to the ladder doesn't ripple through every
/// list controller that shows people.
protocol AllUsersCellDelegate: AnyObject {
    func allUsersCell(_ cell: AllUsersCell, didTap action: RelationshipTier.Action, for user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapProfileImage user: User)
}

class AllUsersCell: UITableViewCell {
    weak var delegate: AllUsersCellDelegate?
    private var user: User?

    /// What the two visible buttons currently mean, set on every configure().
    private var primaryAction: RelationshipTier.Action = .follow
    private var secondaryAction: RelationshipTier.Action?

    // Constraint outlets for dynamic layout
    private var actionButtonTrailingConstraint: NSLayoutConstraint?
    private var followButtonTrailingConstraint: NSLayoutConstraint?
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let highlightView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let userInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    // "87 places · 12 circles" — the size of their collection is why this
    // person is interesting, so it gets its own line in the brand color.
    private let statsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    // Place-milestone tier chip — the same badge system as the profile page
    // and Discover, so a power user reads the same everywhere.
    private let tierChipIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let tierChipLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var tierChip: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 9
        view.isHidden = true
        view.addSubview(tierChipIcon)
        view.addSubview(tierChipLabel)
        NSLayoutConstraint.activate([
            tierChipIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            tierChipIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tierChipIcon.widthAnchor.constraint(equalToConstant: 10),
            tierChipIcon.heightAnchor.constraint(equalToConstant: 10),
            tierChipLabel.leadingAnchor.constraint(equalTo: tierChipIcon.trailingAnchor, constant: 3),
            tierChipLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            tierChipLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 18)
        ])
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    private lazy var textStack: UIStackView = {
        let nameRow = UIStackView(arrangedSubviews: [nameLabel, tierChip, UIView()])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [nameRow, statsLabel, userInfoLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.layer.cornerRadius = 6
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let followButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.layer.cornerRadius = 6
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = .systemBackground
        selectionStyle = .none
        
        contentView.addSubview(highlightView)
        contentView.addSubview(profileImageView)
        contentView.addSubview(textStack)
        contentView.addSubview(actionButton)
        contentView.addSubview(followButton)
        
        // Make profile image tappable
        profileImageView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.addGestureRecognizer(tapGesture)
        
        // Add long press for full-screen image viewing
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(profileImageLongPressed))
        longPressGesture.minimumPressDuration = 0.5
        profileImageView.addGestureRecognizer(longPressGesture)
        
        // Buttons read left-to-right as primary then secondary, so the
        // secondary is the one pinned to the trailing edge.
        actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(equalTo: followButton.leadingAnchor, constant: -6)
        followButtonTrailingConstraint = followButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            highlightView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            // The text column drives the row height (self-sizing rows): its
            // top/bottom pin to the cell, and hidden lines collapse out of
            // the stack.
            textStack.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            


            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButtonTrailingConstraint!,
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 75),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            followButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            followButtonTrailingConstraint!,
            // 44pt floor keeps the glyph variants (⋯, ✕) at Apple's minimum tap
            // target while titled variants like "Connect" size to their text.
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            followButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
    }
    
    /// Repositions the two buttons for the current tier. Only the secondary is
    /// ever hidden, so this reduces to two cases rather than the four-button
    /// permutation table this used to walk.
    private func updateTrailingConstraints() {
        actionButtonTrailingConstraint?.isActive = false
        followButtonTrailingConstraint?.isActive = false

        if followButton.isHidden {
            // Primary alone, pinned to the trailing edge.
            actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -12)
        } else {
            actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(
                equalTo: followButton.leadingAnchor, constant: -6)
            followButtonTrailingConstraint = followButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -12)
            followButtonTrailingConstraint?.isActive = true
        }

        // The text column always stops short of the leftmost button, which is
        // the primary — a single static constraint set up in setupCell().
        actionButtonTrailingConstraint?.isActive = true
    }

    func configure(with user: User) {
        self.user = user
        nameLabel.text = user.displayName
        // The subtitle is derived from the relationship tier further down — it
        // leads with why this person matters (mutuals, places saved) and only
        // falls back to location or bio when there's nothing better to say.

        // Check if this is a newly accepted connection
        let newlyAcceptedId = UserDefaults.standard.string(forKey: "newlyAcceptedConnectionId")
        let isNewlyAccepted = newlyAcceptedId == user.id
        highlightView.isHidden = !isNewlyAccepted
        
        // Set profile image
        if let profilePicture = user.profilePicture {
            // Check if it's a default SF Symbol avatar
            if profilePicture.starts(with: "sf-symbol:") {
                let symbolName = String(profilePicture.dropFirst("sf-symbol:".count))
                if let avatarCase = DefaultImages.AvatarDefault.allCases.first(where: { $0.rawValue == symbolName }) {
                    profileImageView.image = avatarCase.image(size: 40)
                    profileImageView.backgroundColor = avatarCase.backgroundColor
                    profileImageView.tintColor = .white
                    profileImageView.contentMode = .scaleAspectFit
                } else {
                    // Fallback to the symbol name directly
                    profileImageView.image = UIImage(systemName: symbolName)
                    profileImageView.tintColor = .systemGray3
                    profileImageView.backgroundColor = .systemGray5
                    profileImageView.contentMode = .scaleAspectFit
                }
            } else {
                // Initials placeholder while loading; clears any styling left
                // over from a previous user's avatar
                profileImageView.image = AvatarPlaceholder.image(for: user, diameter: 40)
                profileImageView.backgroundColor = .clear
                profileImageView.contentMode = .scaleAspectFill
                ImageService.shared.loadProfileImage(for: user.id, from: profilePicture) { [weak self] image in
                    DispatchQueue.main.async {
                        // The cell may have been reused for a different user while
                        // the image loaded — only apply if it's still the same user
                        guard let self = self, self.user?.id == user.id, let image = image else { return }
                        self.profileImageView.image = image
                    }
                }
            }
        } else {
            profileImageView.image = AvatarPlaceholder.image(for: user, diameter: 40)
            profileImageView.backgroundColor = .clear
            profileImageView.contentMode = .scaleAspectFit
        }
        
        // Configure buttons from the person's rung on the follow → connect
        // ladder. One shared source of truth, so a person looks the same here,
        // in Discover, and in search results.
        let tier = RelationshipTier(user: user)
        applyTier(tier)

        // Business accounts read as stores everywhere; otherwise the
        // place-milestone tier chip — the same badges as the profile page and
        // Discover, so a power user reads the same everywhere.
        let placesTotal = user.placesCount ?? 0
        if user.isBusiness == true {
            tierChip.isHidden = false
            tierChip.backgroundColor = Constants.Colors.primary
            tierChipIcon.image = UIImage(systemName: "storefront.fill")
            tierChipLabel.text = "STORE"
        } else if let badge = PlaceMilestones.badge(for: placesTotal) {
            tierChip.isHidden = false
            tierChip.backgroundColor = badge.color
            tierChipIcon.image = UIImage(systemName: badge.iconName)
            tierChipLabel.text = badge.name.uppercased()
        } else {
            tierChip.isHidden = true
        }

        // Stats line: "87 places · 12 circles", count in the brand color.
        let circlesTotal = user.circlesCount ?? 0
        if placesTotal > 0 || circlesTotal > 0 {
            let stat = NSMutableAttributedString()
            if placesTotal > 0 {
                stat.append(NSAttributedString(
                    string: "\(placesTotal) \(placesTotal == 1 ? "place" : "places")",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: Constants.Colors.primary
                    ]))
            }
            if circlesTotal > 0 {
                stat.append(NSAttributedString(
                    string: placesTotal > 0 ? "  ·  \(circlesTotal) \(circlesTotal == 1 ? "circle" : "circles")" : "\(circlesTotal) \(circlesTotal == 1 ? "circle" : "circles")",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13),
                        .foregroundColor: Constants.Colors.secondaryLabel
                    ]))
            }
            statsLabel.attributedText = stat
            statsLabel.isHidden = false
        } else {
            statsLabel.attributedText = nil
            statsLabel.isHidden = true
        }

        // Context line: where they are, plus the relationship signal.
        var contextParts: [String] = []
        if let location = user.location, !location.isEmpty {
            contextParts.append("📍 \(location)")
        }
        if user.followsYou == true, tier != .connected {
            contextParts.append("Follows you")
        }
        if contextParts.isEmpty {
            // Nothing better to say — fall back to the tier subtitle (mutuals,
            // bio, "Circles member").
            let subtitle = tier.subtitle(for: user)
            userInfoLabel.text = subtitle
            userInfoLabel.isHidden = subtitle.isEmpty
        } else {
            userInfoLabel.text = contextParts.joined(separator: " · ")
            userInfoLabel.isHidden = false
        }
    }

    /// Lays out the row's one primary button and optional secondary from the
    /// tier's spec. The old per-status `switch` set four buttons by hand and
    /// had drifted out of sync with the Discover cell.
    private func applyTier(_ tier: RelationshipTier) {
        let primary = tier.primaryButton
        primaryAction = primary.action
        apply(spec: primary, to: actionButton)
        actionButton.isHidden = false

        if let secondary = tier.secondaryButton {
            secondaryAction = secondary.action
            apply(spec: secondary, to: followButton)
            followButton.isHidden = false
        } else {
            secondaryAction = nil
            followButton.isHidden = true
        }

        // Incoming requests are the only rows that need to pull the eye.
        contentView.backgroundColor = tier == .requestReceived
            ? Constants.Colors.brightOrange.withAlphaComponent(0.05)
            : .systemBackground

        updateTrailingConstraints()
    }

    private func apply(spec: RelationshipTier.ButtonSpec, to button: UIButton) {
        if spec.isGlyph {
            button.setTitle(nil, for: .normal)
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            button.setImage(UIImage(systemName: spec.title, withConfiguration: config), for: .normal)
            button.tintColor = .secondaryLabel
            button.backgroundColor = .clear
            button.layer.borderWidth = 0
        } else {
            button.setImage(nil, for: .normal)
            button.setTitle(spec.title, for: .normal)
            button.setStyle(spec.style)
        }
        button.isEnabled = true
    }

    @objc private func actionButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTap: primaryAction, for: user)
    }

    @objc private func followButtonTapped() {
        guard let user = user, let action = secondaryAction else { return }
        delegate?.allUsersCell(self, didTap: action, for: user)
    }


    @objc private func profileImageTapped() {
        guard let user = user else { return }
        
        // Add subtle tap feedback animation
        UIView.animate(withDuration: 0.1, animations: {
            self.profileImageView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.profileImageView.transform = .identity
            }
        }
        
        delegate?.allUsersCell(self, didTapProfileImage: user)
    }
    
    @objc private func profileImageLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let user = user else { return }
        
        // Find the parent view controller to present the image viewer
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                // Show full-screen profile image
                if let profileImageURL = user.profilePicture {
                    ImageViewerService.shared.presentImageFromURL(profileImageURL, from: viewController)
                } else if let currentImage = profileImageView.image {
                    ImageViewerService.shared.presentImage(currentImage, from: viewController)
                }
                break
            }
            responder = responder?.next
        }
    }
}