import UIKit

protocol DiscoverUserCellDelegate: AnyObject {
    func discoverUserCellDidTapFollow(_ cell: DiscoverUserCell)
}

class DiscoverUserCell: UITableViewCell {
    
    // MARK: - Discovery Types
    enum DiscoveryType {
        case all
        case popular
        case nearby
        case friendsOfFriends
    }
    
    // MARK: - Properties
    weak var delegate: DiscoverUserCellDelegate?
    var indexPath: IndexPath?
    private var user: User?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.label.withAlphaComponent(0.1).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 24
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let verifiedBadge: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        imageView.tintColor = .systemBlue
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let discoveryReasonLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var followButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(profileImageView)
        containerView.addSubview(verifiedBadge)
        containerView.addSubview(nameLabel)
        containerView.addSubview(detailLabel)
        containerView.addSubview(discoveryReasonLabel)
        containerView.addSubview(followButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),
            
            verifiedBadge.trailingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 2),
            verifiedBadge.bottomAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 2),
            verifiedBadge.widthAnchor.constraint(equalToConstant: 16),
            verifiedBadge.heightAnchor.constraint(equalToConstant: 16),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8),
            
            discoveryReasonLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            discoveryReasonLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 2),
            discoveryReasonLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8),
            
            followButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            followButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            followButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    // MARK: - Configuration
    func configure(with user: User, discoveryType: DiscoveryType) {
        self.user = user
        
        // Name and verification
        nameLabel.text = user.displayName
        verifiedBadge.isHidden = !(user.isVerified ?? false)
        
        // Details (places and circles)
        let placesText = "\(user.placesCount ?? 0) place\(user.placesCount == 1 ? "" : "s")"
        let circlesText = "\(user.circlesCount ?? 0) circle\(user.circlesCount == 1 ? "" : "s")"
        let followersText = "\(user.followersCount ?? 0) follower\(user.followersCount == 1 ? "" : "s")"
        detailLabel.text = "\(placesText) • \(circlesText) • \(followersText)"
        
        // Discovery reason
        configureDiscoveryReason(user: user, type: discoveryType)
        
        // Profile image - use profile-specific loading to prevent cache collisions
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            ImageService.shared.loadProfileImage(for: user.id, from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        self?.profileImageView.tintColor = Constants.Colors.secondaryLabel
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.secondaryLabel
        }
        
        // Follow button
        updateFollowButton()
    }
    
    private func configureDiscoveryReason(user: User, type: DiscoveryType) {
        var reasonText = ""
        var reasonIcon = ""
        
        // Check for specific discovery metadata
        if let discoveryType = user.discoveryType {
            switch discoveryType {
            case "friendsOfFriends":
                if let mutualCount = user.mutualConnectionsCount, mutualCount > 0 {
                    if let mutualNames = user.mutualConnectionNames, !mutualNames.isEmpty {
                        let namesText = mutualNames.prefix(2).joined(separator: ", ")
                        if mutualCount > 2 {
                            reasonText = "👥 Friends with \(namesText) and \(mutualCount - 2) others"
                        } else {
                            reasonText = "👥 Friends with \(namesText)"
                        }
                    } else {
                        reasonText = "👥 \(mutualCount) mutual connection\(mutualCount == 1 ? "" : "s")"
                    }
                }
            case "nearby":
                if let distance = user.distance {
                    reasonText = "📍 \(distance) km away"
                }
            case "popular":
                reasonText = "⭐ Popular user"
            default:
                break
            }
        }
        
        // Fallback to type-based reasons
        if reasonText.isEmpty {
            switch type {
            case .popular:
                reasonText = "⭐ Popular user"
            case .nearby:
                reasonText = "📍 Nearby"
            case .friendsOfFriends:
                reasonText = "👥 Mutual connections"
            case .all:
                // Show most relevant reason
                if user.followersCount ?? 0 > 100 {
                    reasonText = "⭐ Popular user"
                } else if user.placesCount ?? 0 > 20 {
                    reasonText = "🏆 Active contributor"
                }
            }
        }
        
        discoveryReasonLabel.text = reasonText
        discoveryReasonLabel.isHidden = reasonText.isEmpty
    }
    
    private func updateFollowButton() {
        guard let user = user else { return }
        
        let isFollowing = user.isFollowing ?? false
        let connectionStatus = user.connectionStatus ?? "none"
        
        if connectionStatus == "accepted" {
            followButton.setTitle("Connected", for: .normal)
            followButton.backgroundColor = .systemGreen.withAlphaComponent(0.1)
            followButton.setTitleColor(.systemGreen, for: .normal)
            followButton.layer.borderColor = UIColor.systemGreen.cgColor
            followButton.isEnabled = false
        } else if connectionStatus == "pending" {
            followButton.setTitle("Pending", for: .normal)
            followButton.backgroundColor = .systemOrange.withAlphaComponent(0.1)
            followButton.setTitleColor(.systemOrange, for: .normal)
            followButton.layer.borderColor = UIColor.systemOrange.cgColor
            followButton.isEnabled = false
        } else if isFollowing {
            followButton.setTitle("Following", for: .normal)
            followButton.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            followButton.setTitleColor(Constants.Colors.primary, for: .normal)
            followButton.layer.borderColor = Constants.Colors.primary.cgColor
            followButton.isEnabled = false
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.backgroundColor = Constants.Colors.primary
            followButton.setTitleColor(.white, for: .normal)
            followButton.layer.borderColor = Constants.Colors.primary.cgColor
            followButton.isEnabled = true
        }
    }
    
    // MARK: - Actions
    @objc private func followButtonTapped() {
        delegate?.discoverUserCellDidTapFollow(self)
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = nil
        verifiedBadge.isHidden = true
        discoveryReasonLabel.text = nil
        discoveryReasonLabel.isHidden = false
        user = nil
        indexPath = nil
    }
}