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
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let userInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let followButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
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
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.widthAnchor.constraint(equalToConstant: 70),
            removeButton.heightAnchor.constraint(equalToConstant: 32),
            
            declineButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            declineButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            declineButton.widthAnchor.constraint(equalToConstant: 70),
            declineButton.heightAnchor.constraint(equalToConstant: 32),
            
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            actionButton.widthAnchor.constraint(equalToConstant: 70),
            actionButton.heightAnchor.constraint(equalToConstant: 32),
            
            followButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            followButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            followButton.widthAnchor.constraint(equalToConstant: 70),
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
            // Fallback to content view if no buttons are visible
            constraintTarget = contentView
        }
        
        // Create and activate new constraints
        if constraintTarget == contentView {
            nameTrailingConstraint = nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
            emailTrailingConstraint = userInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        } else {
            nameTrailingConstraint = nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: constraintTarget.leadingAnchor, constant: -8)
            emailTrailingConstraint = userInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: constraintTarget.leadingAnchor, constant: -8)
        }
        
        nameTrailingConstraint?.isActive = true
        emailTrailingConstraint?.isActive = true
    }
    
    func configure(with user: User) {
        self.user = user
        nameLabel.text = user.displayName
        // Display user info instead of email for privacy
        if let bio = user.bio, !bio.isEmpty {
            userInfoLabel.text = bio
        } else if let location = user.location, !location.isEmpty {
            // Use the location property if available
            userInfoLabel.text = location
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
                    profileImageView.contentMode = .scaleAspectFit
                }
            } else {
                // Regular image URL
                ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                    DispatchQueue.main.async {
                        self?.profileImageView.image = image
                        self?.profileImageView.contentMode = .scaleAspectFill
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = .systemGray3
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
                contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
            } else {
                // Outgoing requests: Show Cancel and Follow buttons
                actionButton.setTitle("Cancel", for: .normal)
                actionButton.backgroundColor = .systemRed.withAlphaComponent(0.1)
                actionButton.setTitleColor(.systemRed, for: .normal)
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