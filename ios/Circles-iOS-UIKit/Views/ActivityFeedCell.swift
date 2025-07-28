import UIKit

// MARK: - ActivityFeedCellDelegate
protocol ActivityFeedCellDelegate: AnyObject {
    func didTapUserProfile(user: User)
}

class ActivityFeedCell: UITableViewCell {
    
    // MARK: - Properties
    static let identifier = "ActivityFeedCell"
    weak var delegate: ActivityFeedCellDelegate?
    private var currentActivity: Activity?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.05
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 16
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private let activityLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()
    
    private let commentLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Add tap gesture to avatar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(tapGesture)
        
        contentView.addSubview(containerView)
        containerView.addSubview(avatarImageView)
        containerView.addSubview(activityLabel)
        containerView.addSubview(timestampLabel)
        containerView.addSubview(placeImageView)
        containerView.addSubview(commentLabel)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            
            // Avatar
            avatarImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            avatarImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            // Activity label
            activityLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Constants.Spacing.xsmall),
            activityLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            activityLabel.trailingAnchor.constraint(equalTo: placeImageView.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Timestamp
            timestampLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            timestampLabel.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 2),
            timestampLabel.trailingAnchor.constraint(equalTo: activityLabel.trailingAnchor),
            
            // Place image (optional)
            placeImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            placeImageView.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            placeImageView.widthAnchor.constraint(equalToConstant: 48),
            placeImageView.heightAnchor.constraint(equalToConstant: 48),
            
            // Comment label (optional)
            commentLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            commentLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            commentLabel.trailingAnchor.constraint(equalTo: activityLabel.trailingAnchor),
            commentLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small)
        ])
    }
    
    // MARK: - Configuration
    func configure(with activity: Activity) {
        // Store the current activity
        currentActivity = activity
        
        // Configure avatar
        if let actor = activity.actor {
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = Constants.Colors.primary
            
            if let profilePicture = actor.profilePicture, !profilePicture.isEmpty {
                ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                    DispatchQueue.main.async {
                        self?.avatarImageView.image = image
                    }
                }
            }
        }
        
        // Configure activity text
        let attributedString = NSMutableAttributedString()
        
        // Actor name in bold
        if let actorName = activity.actor?.displayName {
            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: Constants.Colors.label
            ]
            attributedString.append(NSAttributedString(string: actorName + " ", attributes: nameAttributes))
        }
        
        // Activity description
        let descriptionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: Constants.Colors.label
        ]
        attributedString.append(NSAttributedString(string: activity.formattedDescription, attributes: descriptionAttributes))
        
        activityLabel.attributedText = attributedString
        
        // Configure timestamp
        timestampLabel.text = activity.timeAgo
        
        // Configure optional elements
        placeImageView.isHidden = activity.metadata?.placePhoto == nil
        if let placePhoto = activity.metadata?.placePhoto {
            ImageService.shared.loadImage(from: placePhoto) { [weak self] image in
                DispatchQueue.main.async {
                    self?.placeImageView.image = image
                }
            }
        }
        
        // Show comment for comment activities
        commentLabel.isHidden = !(activity.type == .placeCommented || activity.type == .commentLiked)
        if activity.type == .placeCommented, let comment = activity.metadata?.comment {
            commentLabel.text = "\"" + comment + "\""
        } else if activity.type == .commentLiked, let comment = activity.metadata?.comment {
            commentLabel.text = "\"" + comment + "\""
        }
    }
    
    // MARK: - Actions
    @objc private func avatarTapped() {
        guard let activity = currentActivity,
              let actor = activity.actor else { return }
        
        delegate?.didTapUserProfile(user: actor)
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        placeImageView.image = nil
        placeImageView.isHidden = true
        commentLabel.isHidden = true
        commentLabel.text = nil
        currentActivity = nil
        delegate = nil
    }
}