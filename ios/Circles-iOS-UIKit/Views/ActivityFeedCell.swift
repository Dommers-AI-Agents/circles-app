import UIKit

// MARK: - ActivityFeedCellDelegate
protocol ActivityFeedCellDelegate: AnyObject {
    func didTapUserProfile(user: User)
    func didTapPlaceImage(activity: Activity)
    func didTapActivityContent(activity: Activity)
    func didTapReactions(activity: Activity)
    func didTapComments(activity: Activity)
    func didTapReactionButton(activity: Activity, emoji: String)
    func didLongPressReactionButton(activity: Activity, sourceView: UIView)
}

class ActivityFeedCell: UITableViewCell {
    
    // MARK: - Properties
    static let identifier = "ActivityFeedCell"
    weak var delegate: ActivityFeedCellDelegate?
    private var currentActivity: Activity?
    
    // Image loading state management
    private var currentAvatarLoadId: String?
    private var currentPlaceImageLoadId: String?
    
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
    
    // Interaction buttons - positioned in top row
    private let interactionButtonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let reactionButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.setImage(UIImage(systemName: "bubble.right", withConfiguration: config), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let reactionsLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // Container for reaction pills
    private let reactionPillsContainer: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
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
        let avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(avatarTapGesture)
        
        // Add tap gesture to place image
        let placeTapGesture = UITapGestureRecognizer(target: self, action: #selector(placeImageTapped))
        placeImageView.addGestureRecognizer(placeTapGesture)
        placeImageView.isUserInteractionEnabled = true
        
        // Add tap gesture to activity content (for navigating to places)
        let contentTapGesture = UITapGestureRecognizer(target: self, action: #selector(contentTapped))
        containerView.addGestureRecognizer(contentTapGesture)
        containerView.isUserInteractionEnabled = true
        
        contentView.addSubview(containerView)
        containerView.addSubview(avatarImageView)
        containerView.addSubview(activityLabel)
        containerView.addSubview(timestampLabel)
        containerView.addSubview(placeImageView)
        containerView.addSubview(commentLabel)
        containerView.addSubview(reactionsLabel)
        containerView.addSubview(reactionPillsContainer)
        containerView.addSubview(interactionButtonsContainer)
        
        // Add interaction buttons to their container
        interactionButtonsContainer.addSubview(reactionButton)
        interactionButtonsContainer.addSubview(commentButton)
        interactionButtonsContainer.addSubview(commentCountLabel)
        
        // Add button actions
        reactionButton.addTarget(self, action: #selector(reactionButtonTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        
        // Add long press gesture to reaction button
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(reactionButtonLongPressed(_:)))
        longPressGesture.minimumPressDuration = 0.5
        reactionButton.addGestureRecognizer(longPressGesture)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
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
            
            // Activity label - now ends at interaction buttons
            activityLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Constants.Spacing.xsmall),
            activityLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            activityLabel.trailingAnchor.constraint(equalTo: interactionButtonsContainer.leadingAnchor, constant: -Constants.Spacing.xsmall),
            
            // Interaction buttons container - positioned between text and thumbnail
            interactionButtonsContainer.trailingAnchor.constraint(equalTo: placeImageView.leadingAnchor, constant: -Constants.Spacing.small),
            interactionButtonsContainer.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            interactionButtonsContainer.widthAnchor.constraint(equalToConstant: 60),
            interactionButtonsContainer.heightAnchor.constraint(equalToConstant: 20),
            
            // Reaction button
            reactionButton.leadingAnchor.constraint(equalTo: interactionButtonsContainer.leadingAnchor),
            reactionButton.centerYAnchor.constraint(equalTo: interactionButtonsContainer.centerYAnchor),
            reactionButton.widthAnchor.constraint(equalToConstant: 20),
            reactionButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Comment button
            commentButton.leadingAnchor.constraint(equalTo: reactionButton.trailingAnchor, constant: 8),
            commentButton.centerYAnchor.constraint(equalTo: interactionButtonsContainer.centerYAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 20),
            commentButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Comment count label
            commentCountLabel.leadingAnchor.constraint(equalTo: commentButton.trailingAnchor, constant: 2),
            commentCountLabel.centerYAnchor.constraint(equalTo: commentButton.centerYAnchor),
            
            // Place image (optional) - positioned at top right
            placeImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            placeImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            placeImageView.widthAnchor.constraint(equalToConstant: 48),
            placeImageView.heightAnchor.constraint(equalToConstant: 48),
            
            // Timestamp
            timestampLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            timestampLabel.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 2),
            timestampLabel.trailingAnchor.constraint(equalTo: activityLabel.trailingAnchor),
            
            // Comment label (optional)
            commentLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            commentLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            commentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Reactions label (optional)
            reactionsLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            reactionsLabel.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            reactionsLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Reaction pills container
            reactionPillsContainer.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            reactionPillsContainer.topAnchor.constraint(equalTo: reactionsLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            reactionPillsContainer.heightAnchor.constraint(equalToConstant: 24),
            reactionPillsContainer.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small)
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
                // Generate unique load ID for this avatar request
                let loadId = UUID().uuidString
                currentAvatarLoadId = loadId
                
                // Use namespaced cache key for profile images to prevent collision with place images
                let profileCacheKey = "profile_\(actor.id)_\(profilePicture)"
                ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: profileCacheKey) { [weak self] image in
                    DispatchQueue.main.async {
                        // Only update if this is still the current load request
                        guard let self = self, self.currentAvatarLoadId == loadId else {
                            Logger.debug("ActivityFeedCell: Ignoring stale avatar image load")
                            return
                        }
                        
                        if let image = image {
                            self.avatarImageView.image = image
                        }
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
        
        // Configure optional elements - show place image for check-ins, places, video uploads, and photo uploads
        let shouldShowPlaceImage = (activity.type == .checkIn || 
                                   activity.type == .placeAdded || 
                                   activity.type == .placeLiked ||
                                   activity.type == .videoUploaded ||
                                   activity.type == .photoUploaded) && 
                                   activity.metadata?.placePhoto != nil
        
        placeImageView.isHidden = !shouldShowPlaceImage
        if let placePhoto = activity.metadata?.placePhoto, shouldShowPlaceImage {
            // Generate unique load ID for this place image request
            let loadId = UUID().uuidString
            currentPlaceImageLoadId = loadId
            
            // Clear any existing place image to prevent showing stale content
            placeImageView.image = nil
            
            Logger.debug("ActivityFeedCell: Loading place image for activity \(activity.type.rawValue) - \(activity.targetName)")
            Logger.debug("ActivityFeedCell: Place photo URL: \(placePhoto)")
            
            // Use a namespaced cache key to prevent collisions with profile images
            let placeCacheKey = "place_\(activity.targetId ?? "")_\(placePhoto)"
            
            ImageService.shared.loadImageWithKey(from: placePhoto, cacheKey: placeCacheKey) { [weak self] image in
                DispatchQueue.main.async {
                    // Only update if this is still the current load request
                    guard let self = self, self.currentPlaceImageLoadId == loadId else {
                        Logger.debug("ActivityFeedCell: Ignoring stale place image load")
                        return
                    }
                    
                    if let image = image {
                        Logger.debug("ActivityFeedCell: Successfully loaded place image for \(activity.targetName)")
                        self.placeImageView.image = image
                    } else {
                        Logger.warning("ActivityFeedCell: Failed to load place image for \(activity.targetName) from URL: \(placePhoto)")
                        // Set a default place image
                        self.placeImageView.image = UIImage(systemName: "photo")
                        self.placeImageView.tintColor = Constants.Colors.lightGray
                    }
                }
            }
        }
        
        // Show comment for comment activities
        commentLabel.isHidden = !(activity.type == .placeCommented || activity.type == .commentLiked)
        if activity.type == .placeCommented, let comment = activity.metadata?.comment {
            commentLabel.text = "\"" + comment + "\""
        } else if activity.type == .commentLiked, let comment = activity.metadata?.comment {
            commentLabel.text = "\"" + comment + "\""
        } else if activity.type == .checkIn, let message = activity.metadata?.message, !message.isEmpty {
            commentLabel.isHidden = false
            commentLabel.text = "\"" + message + "\""
        }
        
        // Update reaction pills and counts
        configureReactions(for: activity)
        
        // Update reaction button state based on user's reaction
        if let userReaction = activity.userReaction {
            // User has reacted - show their emoji or filled heart
            if let style = ReactionStyle(emoji: userReaction) {
                reactionButton.setImage(UIImage(systemName: "heart.fill"), for: .normal)
                reactionButton.tintColor = style.backgroundColor
            }
        } else {
            // User hasn't reacted - show empty heart
            reactionButton.setImage(UIImage(systemName: "heart"), for: .normal)
            reactionButton.tintColor = Constants.Colors.secondaryLabel
        }
        
        if let commentCount = activity.commentCount, commentCount > 0 {
            commentCountLabel.text = "\(commentCount)"
            commentCountLabel.isHidden = false
        } else {
            commentCountLabel.isHidden = true
        }
    }
    
    // MARK: - Actions
    @objc private func avatarTapped() {
        guard let activity = currentActivity,
              let actor = activity.actor else { return }
        
        delegate?.didTapUserProfile(user: actor)
    }
    
    @objc private func placeImageTapped() {
        guard let activity = currentActivity else { return }
        delegate?.didTapPlaceImage(activity: activity)
    }
    
    @objc private func contentTapped() {
        guard let activity = currentActivity else { return }
        
        // Navigate for all place-related activities
        if activity.type == .placeAdded || 
           activity.type == .placeLiked || 
           activity.type == .placeCommented ||
           activity.type == .checkIn ||
           activity.type == .videoUploaded ||
           activity.type == .photoUploaded {
            delegate?.didTapActivityContent(activity: activity)
        }
    }
    
    @objc private func reactionButtonTapped() {
        guard let activity = currentActivity else { return }
        
        // Use thumbs up as default reaction (LinkedIn-style "like")
        delegate?.didTapReactionButton(activity: activity, emoji: "👍")
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    @objc private func commentButtonTapped() {
        guard let activity = currentActivity else { return }
        delegate?.didTapComments(activity: activity)
    }
    
    // MARK: - Reaction Configuration
    private func configureReactions(for activity: Activity) {
        // Clear existing reaction pills
        reactionPillsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reactionPillsContainer.isHidden = true
        
        // Check if there are reactions to display
        guard let reactionSummary = activity.reactionSummary,
              !reactionSummary.isEmpty else {
            return
        }
        
        // Show reaction pills container
        reactionPillsContainer.isHidden = false
        
        // Add reaction pills (max 3 to keep it compact)
        let topReactions = reactionSummary.prefix(3)
        for reaction in topReactions {
            let config = ReactionPillConfiguration(
                emoji: reaction.emoji,
                count: reaction.count,
                isUserReaction: reaction.emoji == activity.userReaction
            )
            let pillView = ReactionPillView(configuration: config)
            pillView.translatesAutoresizingMaskIntoConstraints = false
            reactionPillsContainer.addArrangedSubview(pillView)
        }
        
        // Add "and X more" label if there are more reactions
        let totalReactionCount = activity.reactionCount ?? 0
        let displayedCount = topReactions.reduce(0) { $0 + $1.count }
        if totalReactionCount > displayedCount {
            let moreLabel = UILabel()
            moreLabel.text = "+\(totalReactionCount - displayedCount)"
            moreLabel.font = UIFont.systemFont(ofSize: 11)
            moreLabel.textColor = Constants.Colors.secondaryLabel
            reactionPillsContainer.addArrangedSubview(moreLabel)
        }
        
        // Add tap gesture to reaction pills
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(reactionPillsTapped))
        reactionPillsContainer.addGestureRecognizer(tapGesture)
    }
    
    @objc private func reactionPillsTapped() {
        guard let activity = currentActivity else { return }
        delegate?.didTapReactions(activity: activity)
    }
    
    @objc private func reactionButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let activity = currentActivity else { return }
        
        // Notify delegate to show reaction picker
        delegate?.didLongPressReactionButton(activity: activity, sourceView: reactionButton)
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel any pending image loads by clearing load IDs
        currentAvatarLoadId = nil
        currentPlaceImageLoadId = nil
        
        // Reset UI elements to default state
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.primary
        placeImageView.image = nil
        placeImageView.tintColor = nil
        placeImageView.isHidden = true
        commentLabel.isHidden = true
        commentLabel.text = nil
        reactionsLabel.isHidden = true
        reactionsLabel.text = nil
        commentCountLabel.isHidden = true
        commentCountLabel.text = nil
        reactionPillsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reactionPillsContainer.isHidden = true
        currentActivity = nil
        delegate = nil
        
        Logger.debug("ActivityFeedCell: prepareForReuse completed - cleared all image load states")
    }
}