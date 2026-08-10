import UIKit

protocol DiscoverUserCellDelegate: AnyObject {
    func discoverUserCellDidTapFollow(_ cell: DiscoverUserCell)
    func discoverUserCellDidTapDismiss(_ cell: DiscoverUserCell)
    /// The row is the signed-in user's own — the action is sharing their
    /// profile, not following themselves.
    func discoverUserCellDidTapShare(_ cell: DiscoverUserCell)
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
    /// True when the row shows the signed-in user themself (Most active
    /// includes them at their honest rank). Flips the action to Share and
    /// removes dismiss — you can't be not-interested in yourself.
    private var isSelfRow = false
    
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
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let discoveryReasonLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.primary
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    // Where they are — profile city, or the city the backend inferred from
    // the places they save. Distance rides along when the server knows it.
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    // Place-milestone tier chip (Explorer, Trailblazer, ...) — the same badge
    // system as the profile page, so "power user" reads at a glance and the
    // colors make the list feel alive.
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

        let stack = UIStackView(arrangedSubviews: [nameRow, detailLabel, locationLabel, discoveryReasonLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    /// "Not interested". Suggestions have to be able to run out, or the same
    /// faces reappear forever.
    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .tertiaryLabel
        button.accessibilityLabel = "Not interested"
        button.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
        containerView.addSubview(textStack)
        containerView.addSubview(followButton)
        containerView.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 12),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),

            verifiedBadge.trailingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 2),
            verifiedBadge.bottomAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 2),
            verifiedBadge.widthAnchor.constraint(equalToConstant: 16),
            verifiedBadge.heightAnchor.constraint(equalToConstant: 16),

            // The text column drives the row height (self-sizing rows): its
            // top/bottom pin to the card, and missing lines just collapse out
            // of the stack.
            textStack.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -8),

            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 28),
            dismissButton.heightAnchor.constraint(equalToConstant: 28),

            followButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),
            followButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            followButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    // MARK: - Configuration
    /// The section header already states the reason these people are grouped
    /// together, so the cell no longer needs to be told which list it's in.
    /// `rank` turns the row into a leaderboard entry (Popular tab): medals for
    /// the podium, #N for everyone else.
    func configure(with user: User, rank: Int? = nil) {
        self.user = user
        isSelfRow = user.id == AuthService.shared.getUserId()
        dismissButton.isHidden = isSelfRow

        // Name and verification (with leaderboard rank when in scorecard mode)
        if let rank = rank {
            let medal: String
            switch rank {
            case 1: medal = "🥇"
            case 2: medal = "🥈"
            case 3: medal = "🥉"
            default: medal = "#\(rank)"
            }
            nameLabel.text = "\(medal) \(user.displayName)"
        } else {
            nameLabel.text = user.displayName
        }
        verifiedBadge.isHidden = !(user.isVerified ?? false)

        // Business accounts read as stores everywhere; otherwise the
        // place-milestone tier chip — same tiers as the profile badge, so a
        // power user is recognizable before you ever open their profile.
        let placesTotal = user.placesCount ?? 0
        if user.isBusiness == true {
            tierChip.isHidden = false
            tierChip.backgroundColor = Constants.Colors.primary
            tierChipIcon.image = UIImage(systemName: "storefront.fill")
            tierChipLabel.text = "STORE"
        } else if let tier = PlaceMilestones.badge(for: placesTotal) {
            tierChip.isHidden = false
            tierChip.backgroundColor = tier.color
            tierChipIcon.image = UIImage(systemName: tier.iconName)
            tierChipLabel.text = tier.name.uppercased()
        } else {
            tierChip.isHidden = true
        }

        // Location: profile city, or the backend's best guess from where they
        // save places. Distance rides along when the server measured one.
        var locationParts: [String] = []
        if let location = user.location, !location.isEmpty {
            locationParts.append(location)
        }
        if let distance = user.distance {
            locationParts.append(distance < 1 ? "under 1 km away" : "\(distance) km away")
        }
        locationLabel.text = locationParts.isEmpty ? nil : "📍 " + locationParts.joined(separator: " · ")
        locationLabel.isHidden = locationParts.isEmpty

        // The stat line is the sell: following someone hands you their whole
        // collection, so the size of that collection is the headline —
        // "214 places · 18 circles", count in the primary color. Someone with
        // no places yet falls back to the standard relationship subtitle.
        let placesCount = placesTotal
        if placesCount > 0 {
            let stat = NSMutableAttributedString(
                string: "\(placesCount) \(placesCount == 1 ? "place" : "places")",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: Constants.Colors.primary
                ])
            if let circlesCount = user.circlesCount, circlesCount > 0 {
                stat.append(NSAttributedString(
                    string: "  ·  \(circlesCount) \(circlesCount == 1 ? "circle" : "circles")",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 14),
                        .foregroundColor: Constants.Colors.secondaryLabel
                    ]))
            }
            detailLabel.attributedText = stat
        } else {
            detailLabel.attributedText = nil
            detailLabel.text = RelationshipTier(user: user).subtitle(for: user)
        }
        // Empty lines collapse out of the stack instead of leaving gaps
        detailLabel.isHidden = (detailLabel.text ?? detailLabel.attributedText?.string ?? "").isEmpty
            && detailLabel.attributedText == nil

        // Per-person reason, where one exists beyond the section heading.
        configureDiscoveryReason(user: user, type: .all)
        
        // Profile image - use profile-specific loading to prevent cache collisions
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            // Initials placeholder while loading, so a reused cell never keeps
            // the previous user's photo — and a failed load leaves something
            // identifiable rather than an anonymous silhouette.
            profileImageView.image = AvatarPlaceholder.image(for: user, diameter: 50)
            ImageService.shared.loadProfileImage(for: user.id, from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    // The cell may have been reused for a different user while
                    // the image loaded — only apply if it's still the same user
                    guard let self = self, self.user?.id == user.id, let image = image else { return }
                    self.profileImageView.image = image
                }
            }
        } else {
            profileImageView.image = AvatarPlaceholder.image(for: user, diameter: 50)
            profileImageView.tintColor = Constants.Colors.secondaryLabel
        }
        
        // Follow button
        updateFollowButton()
    }
    
    private func configureDiscoveryReason(user: User, type: DiscoveryType) {
        // Your own row explains itself — and says what the button does.
        if isSelfRow {
            discoveryReasonLabel.text = "This is you — share your profile to grow your following"
            discoveryReasonLabel.isHidden = false
            return
        }

        // The server now phrases the reason itself — "Also saved Café Mogador
        // + 5 more" is something only the backend can know, and it beats
        // anything the client can infer from a bare discovery type. Fall
        // through to the derived text only when there's no server reason.
        if let reason = user.suggestionReason, !reason.isEmpty {
            discoveryReasonLabel.text = reason
            discoveryReasonLabel.isHidden = false
            return
        }

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
                // Distance already shows on the location line.
                break
            case "popular":
                // The stat line and the "Most active" section header already
                // say it — a third "Popular user" badge is noise.
                break
            default:
                break
            }
        }

        // Fallback to type-based reasons (the stat line covers place counts,
        // and the location line covers proximity)
        if reasonText.isEmpty {
            switch type {
            case .friendsOfFriends:
                reasonText = "👥 Mutual connections"
            case .nearby, .popular, .all:
                break
            }
        }
        
        discoveryReasonLabel.text = reasonText
        discoveryReasonLabel.isHidden = reasonText.isEmpty
    }
    
    private func updateFollowButton() {
        guard let user = user else { return }

        // Your own row: the ask is outward. Same styling weight as Follow —
        // this is the row's primary action, not a passive state chip.
        if isSelfRow {
            followButton.setTitle("Share", for: .normal)
            followButton.backgroundColor = Constants.Colors.primary
            followButton.setTitleColor(.white, for: .normal)
            followButton.layer.borderColor = Constants.Colors.primary.cgColor
            followButton.isEnabled = true
            return
        }

        let isFollowing = user.isFollowing ?? false
        let connectionStatus = user.connectionStatus ?? "none"
        
        if connectionStatus == "accepted" {
            followButton.setTitle("Connected", for: .normal)
            followButton.backgroundColor = .systemGreen.withAlphaComponent(0.1)
            followButton.setTitleColor(.systemGreen, for: .normal)
            followButton.layer.borderColor = UIColor.systemGreen.cgColor
            followButton.isEnabled = false
        } else if connectionStatus == "pending" {
            followButton.setTitle("Request Sent", for: .normal)
            followButton.backgroundColor = Constants.Colors.brightOrange.withAlphaComponent(0.1)
            followButton.setTitleColor(Constants.Colors.brightOrange, for: .normal)
            followButton.layer.borderColor = Constants.Colors.brightOrange.cgColor
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
        if isSelfRow {
            delegate?.discoverUserCellDidTapShare(self)
        } else {
            delegate?.discoverUserCellDidTapFollow(self)
        }
    }

    @objc private func dismissButtonTapped() {
        delegate?.discoverUserCellDidTapDismiss(self)
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = nil
        verifiedBadge.isHidden = true
        discoveryReasonLabel.text = nil
        discoveryReasonLabel.isHidden = true
        locationLabel.text = nil
        locationLabel.isHidden = true
        tierChip.isHidden = true
        detailLabel.isHidden = false
        user = nil
        indexPath = nil
    }
}