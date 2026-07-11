import UIKit

// MARK: - AllUsersCell
protocol AllUsersCellDelegate: AnyObject {
    func allUsersCell(_ cell: AllUsersCell, didTapActionButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapFollowButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapRemoveButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapDeclineButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapProfileImage user: User)
}

class AllUsersCell: UITableViewCell {
    weak var delegate: AllUsersCellDelegate?
    private var user: User?
    
    // Constraint outlets for dynamic layout
    private var nameTrailingConstraint: NSLayoutConstraint?
    private var emailTrailingConstraint: NSLayoutConstraint?
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
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
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
    
    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.setTitleColor(.systemRed, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let declineButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Decline", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.setTitleColor(.systemRed, for: .normal)
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
        contentView.addSubview(nameLabel)
        contentView.addSubview(userInfoLabel)
        contentView.addSubview(actionButton)
        contentView.addSubview(followButton)
        contentView.addSubview(removeButton)
        contentView.addSubview(declineButton)
        
        // Make profile image tappable
        profileImageView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.addGestureRecognizer(tapGesture)
        
        // Add long press for full-screen image viewing
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(profileImageLongPressed))
        longPressGesture.minimumPressDuration = 0.5
        profileImageView.addGestureRecognizer(longPressGesture)
        
        // Create the trailing constraints for dynamic updates
        nameTrailingConstraint = nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8)
        emailTrailingConstraint = userInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8)
        actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6)
        followButtonTrailingConstraint = followButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -6)

        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            highlightView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameTrailingConstraint!,
            
            userInfoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            userInfoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailTrailingConstraint!,
            
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            removeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            removeButton.heightAnchor.constraint(equalToConstant: 32),

            declineButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            declineButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            declineButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            declineButton.heightAnchor.constraint(equalToConstant: 32),

            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButtonTrailingConstraint!,
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 75),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            followButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            followButtonTrailingConstraint!,
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            followButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineButtonTapped), for: .touchUpInside)
    }
    
    private func updateTrailingConstraints() {
        // Deactivate current constraints
        nameTrailingConstraint?.isActive = false
        emailTrailingConstraint?.isActive = false
        actionButtonTrailingConstraint?.isActive = false
        followButtonTrailingConstraint?.isActive = false

        // Determine the rightmost visible button
        let rightmostButton: UIView
        if !removeButton.isHidden {
            rightmostButton = removeButton
        } else if !declineButton.isHidden {
            rightmostButton = declineButton
        } else {
            rightmostButton = contentView
        }

        // Update action button position based on what's visible
        if rightmostButton == contentView {
            // No remove/decline button, action button goes to edge
            actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4)
        } else {
            // Position action button before remove/decline button
            actionButtonTrailingConstraint = actionButton.trailingAnchor.constraint(equalTo: rightmostButton.leadingAnchor, constant: -6)
        }

        // Update follow button position
        followButtonTrailingConstraint = followButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -6)

        // Determine the leftmost visible button to constrain text to
        let constraintTarget: UIView
        if !followButton.isHidden {
            constraintTarget = followButton
        } else if !actionButton.isHidden {
            constraintTarget = actionButton
        } else if !removeButton.isHidden {
            constraintTarget = removeButton
        } else if !declineButton.isHidden {
            constraintTarget = declineButton
        } else {
            constraintTarget = contentView
        }

        // Create and activate new constraints for labels
        if constraintTarget == contentView {
            nameTrailingConstraint = nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -4)
            emailTrailingConstraint = userInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -4)
        } else {
            nameTrailingConstraint = nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: constraintTarget.leadingAnchor, constant: -8)
            emailTrailingConstraint = userInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: constraintTarget.leadingAnchor, constant: -8)
        }

        // Activate all constraints
        nameTrailingConstraint?.isActive = true
        emailTrailingConstraint?.isActive = true
        actionButtonTrailingConstraint?.isActive = true
        followButtonTrailingConstraint?.isActive = true
    }
    
    func configure(with user: User) {
        self.user = user
        nameLabel.text = user.displayName
        // Display location first for consistency in My Network section
        if let location = user.location, !location.isEmpty {
            userInfoLabel.text = location
        } else if let bio = user.bio, !bio.isEmpty {
            // Fall back to bio if no location available
            userInfoLabel.text = bio
        } else {
            userInfoLabel.text = "Circles member"
        }
        
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
                // Regular image URL - show a placeholder while loading and clear
                // any styling left over from a previous user's default avatar
                profileImageView.image = UIImage(systemName: "person.circle.fill")
                profileImageView.tintColor = .systemGray3
                profileImageView.backgroundColor = .systemGray5
                profileImageView.contentMode = .scaleAspectFit
                ImageService.shared.loadProfileImage(for: user.id, from: profilePicture) { [weak self] image in
                    DispatchQueue.main.async {
                        // The cell may have been reused for a different user while
                        // the image loaded — only apply if it's still the same user
                        guard let self = self, self.user?.id == user.id else { return }
                        self.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                        self.profileImageView.contentMode = image != nil ? .scaleAspectFill : .scaleAspectFit
                        if image == nil {
                            self.profileImageView.tintColor = .systemGray3
                        }
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = .systemGray3
            profileImageView.backgroundColor = .systemGray5
            profileImageView.contentMode = .scaleAspectFit
        }
        
        // Configure buttons based on connection status
        switch user.connectionStatus {
        case "connected", "accepted":
            // Connected users: Show View and Remove buttons only (no Follow button since they're already connected)
            actionButton.setTitle("View", for: .normal)
            actionButton.backgroundColor = Constants.Colors.primary
            actionButton.setTitleColor(.white, for: .normal)
            actionButton.isEnabled = true
            
            // Hide follow button for connected users (they're already connected)
            followButton.isHidden = true
            
            removeButton.isHidden = false
            declineButton.isHidden = true
            contentView.backgroundColor = .systemBackground
            
        case "pending":
            if user.connectionDirection == "incoming" {
                // Incoming requests: Show Accept, Decline, and Follow buttons
                actionButton.setTitle("Accept", for: .normal)
                actionButton.backgroundColor = .systemGreen
                actionButton.setTitleColor(.white, for: .normal)
                actionButton.isEnabled = true
                
                // Configure follow button (can follow even without connection)
                let isFollowing = user.isFollowing ?? false
                followButton.setTitle(isFollowing ? "Following" : "Follow", for: .normal)
                followButton.backgroundColor = isFollowing ? .systemGray5 : .systemBlue
                followButton.setTitleColor(isFollowing ? .label : .white, for: .normal)
                followButton.isHidden = false
                
                removeButton.isHidden = true
                declineButton.isHidden = false
                contentView.backgroundColor = Constants.Colors.brightOrange.withAlphaComponent(0.05)
            } else {
                // Outgoing requests: Show Cancel and Follow buttons
                actionButton.setTitle("Request Sent", for: .normal)
                actionButton.backgroundColor = Constants.Colors.brightOrange.withAlphaComponent(0.1)
                actionButton.setTitleColor(Constants.Colors.brightOrange, for: .normal)
                actionButton.isEnabled = true
                
                // Configure follow button
                let isFollowing = user.isFollowing ?? false
                followButton.setTitle(isFollowing ? "Following" : "Follow", for: .normal)
                followButton.backgroundColor = isFollowing ? .systemGray5 : .systemBlue
                followButton.setTitleColor(isFollowing ? .label : .white, for: .normal)
                followButton.isHidden = false
                
                removeButton.isHidden = true
                declineButton.isHidden = true
                contentView.backgroundColor = Constants.Colors.brightOrange.withAlphaComponent(0.05)
            }
        default:
            // Non-connected users: Show Connect and Follow buttons
            actionButton.setTitle("Connect", for: .normal)
            actionButton.backgroundColor = Constants.Colors.primary
            actionButton.setTitleColor(.white, for: .normal)
            actionButton.isEnabled = true
            
            // Configure follow button
            let isFollowing = user.isFollowing ?? false
            followButton.setTitle(isFollowing ? "Following" : "Follow", for: .normal)
            followButton.backgroundColor = isFollowing ? .systemGray5 : .systemBlue
            followButton.setTitleColor(isFollowing ? .label : .white, for: .normal)
            followButton.isHidden = false
            
            removeButton.isHidden = true
            declineButton.isHidden = true
            contentView.backgroundColor = .systemBackground
        }
        
        // Update trailing constraints after setting button visibility
        updateTrailingConstraints()
    }
    
    @objc private func actionButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapActionButton: user)
    }
    
    @objc private func followButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapFollowButton: user)
    }
    
    @objc private func removeButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapRemoveButton: user)
    }
    
    @objc private func declineButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapDeclineButton: user)
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