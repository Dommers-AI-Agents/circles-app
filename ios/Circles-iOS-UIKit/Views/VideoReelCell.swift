import UIKit
import AVFoundation

protocol VideoReelCellDelegate: AnyObject {
    func videoReelCellDidTapLike(_ cell: VideoReelCell)
    func videoReelCellDidTapComment(_ cell: VideoReelCell)
    func videoReelCellDidTapShare(_ cell: VideoReelCell)
    func videoReelCellDidTapProfile(_ cell: VideoReelCell)
    func videoReelCellDidTapPlace(_ cell: VideoReelCell)
    func videoReelCellDidTapReaction(_ cell: VideoReelCell)
    func videoReelCellDidTapActivityEngagement(_ cell: VideoReelCell)
    func videoReelCellDidTapLikeCount(_ cell: VideoReelCell)
}

class VideoReelCell: UICollectionViewCell {
    
    // MARK: - Properties
    weak var delegate: VideoReelCellDelegate?
    private var playerLayer: AVPlayerLayer?
    private var embeddedPlayerView: EmbeddedVideoPlayerView?
    private var isLiked = false
    private var reel: PlaceVideo?
    private var playerItemObserver: NSKeyValueObservation?
    
    // MARK: - UI Elements
    private let videoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black // Black background for video
        view.clipsToBounds = true // Ensure video doesn't overflow
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        return view
    }()
    
    private let photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        imageView.isUserInteractionEnabled = false
        return imageView
    }()
    
    private let gradientView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Don't block touches
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.backgroundColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let followButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Follow", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 4
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let likeCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "message"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let reactionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let reactionCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let reactionSummaryView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.distribution = .fillProportionally
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = true
        return stack
    }()
    
    private let soundButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let watchOnPlatformButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Watch on Platform", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 30
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.backgroundColor = .black
        backgroundColor = .black
        
        // Add subviews - video container fills the entire cell
        contentView.addSubview(videoContainerView)
        
        // Don't add photoImageView as a subview - we'll add it only when needed
        // Add gradient for text readability on top of video/photo
        videoContainerView.addSubview(gradientView)
        
        // Add all UI elements as overlays on the video container
        videoContainerView.addSubview(profileImageView)
        videoContainerView.addSubview(usernameLabel)
        videoContainerView.addSubview(followButton)
        videoContainerView.addSubview(placeNameLabel)
        videoContainerView.addSubview(descriptionLabel)
        videoContainerView.addSubview(likeButton)
        videoContainerView.addSubview(likeCountLabel)
        videoContainerView.addSubview(commentButton)
        videoContainerView.addSubview(commentCountLabel)
        videoContainerView.addSubview(shareButton)
        videoContainerView.addSubview(reactionButton)
        videoContainerView.addSubview(reactionCountLabel)
        videoContainerView.addSubview(reactionSummaryView)
        videoContainerView.addSubview(soundButton)
        videoContainerView.addSubview(watchOnPlatformButton)
        videoContainerView.addSubview(playPauseButton)
        
        // Setup gradient
        setupGradient()
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Video container
            videoContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            videoContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            
            // Gradient - proportional height
            gradientView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),
            gradientView.heightAnchor.constraint(equalTo: videoContainerView.heightAnchor, multiplier: 0.5), // 50% of container height
            
            // Right side actions - Reaction button at bottom
            reactionButton.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor, constant: -16),
            reactionButton.bottomAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            reactionButton.widthAnchor.constraint(equalToConstant: 44),
            reactionButton.heightAnchor.constraint(equalToConstant: 44),
            
            reactionCountLabel.centerXAnchor.constraint(equalTo: reactionButton.centerXAnchor),
            reactionCountLabel.topAnchor.constraint(equalTo: reactionButton.bottomAnchor, constant: 4),
            
            reactionSummaryView.trailingAnchor.constraint(equalTo: reactionButton.leadingAnchor, constant: -8),
            reactionSummaryView.centerYAnchor.constraint(equalTo: reactionButton.centerYAnchor),
            reactionSummaryView.heightAnchor.constraint(equalToConstant: 24),
            
            shareButton.trailingAnchor.constraint(equalTo: reactionButton.trailingAnchor),
            shareButton.bottomAnchor.constraint(equalTo: reactionButton.topAnchor, constant: -20),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            
            commentButton.trailingAnchor.constraint(equalTo: shareButton.trailingAnchor),
            commentButton.bottomAnchor.constraint(equalTo: shareButton.topAnchor, constant: -20),
            commentButton.widthAnchor.constraint(equalToConstant: 44),
            commentButton.heightAnchor.constraint(equalToConstant: 44),
            
            commentCountLabel.centerXAnchor.constraint(equalTo: commentButton.centerXAnchor),
            commentCountLabel.topAnchor.constraint(equalTo: commentButton.bottomAnchor, constant: 4),
            
            likeButton.trailingAnchor.constraint(equalTo: commentButton.trailingAnchor),
            likeButton.bottomAnchor.constraint(equalTo: commentButton.topAnchor, constant: -20),
            likeButton.widthAnchor.constraint(equalToConstant: 44),
            likeButton.heightAnchor.constraint(equalToConstant: 44),
            
            likeCountLabel.centerXAnchor.constraint(equalTo: likeButton.centerXAnchor),
            likeCountLabel.topAnchor.constraint(equalTo: likeButton.bottomAnchor, constant: 4),
            
            profileImageView.trailingAnchor.constraint(equalTo: likeButton.trailingAnchor),
            profileImageView.bottomAnchor.constraint(equalTo: likeButton.topAnchor, constant: -20),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            // Bottom info
            descriptionLabel.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -16),
            descriptionLabel.bottomAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            placeNameLabel.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor),
            placeNameLabel.trailingAnchor.constraint(equalTo: descriptionLabel.trailingAnchor),
            placeNameLabel.bottomAnchor.constraint(equalTo: descriptionLabel.topAnchor, constant: -8),
            
            usernameLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            usernameLabel.bottomAnchor.constraint(equalTo: placeNameLabel.topAnchor, constant: -8),
            
            followButton.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 12),
            followButton.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            
            // Sound button (positioned at top right)
            soundButton.topAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.topAnchor, constant: 72),
            soundButton.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor, constant: -16),
            soundButton.widthAnchor.constraint(equalToConstant: 40),
            soundButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Watch on Platform button (centered at top)
            watchOnPlatformButton.topAnchor.constraint(equalTo: videoContainerView.safeAreaLayoutGuide.topAnchor, constant: 120),
            watchOnPlatformButton.centerXAnchor.constraint(equalTo: videoContainerView.centerXAnchor),
            
            // Play/Pause button (center)
            playPauseButton.centerXAnchor.constraint(equalTo: videoContainerView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: videoContainerView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 60),
            playPauseButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        // Add button targets
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        reactionButton.addTarget(self, action: #selector(reactionTapped), for: .touchUpInside)
        soundButton.addTarget(self, action: #selector(soundTapped), for: .touchUpInside)
        watchOnPlatformButton.addTarget(self, action: #selector(watchOnPlatformTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        
        // Add tap gesture to reaction summary
        let summaryTap = UITapGestureRecognizer(target: self, action: #selector(reactionSummaryTapped))
        reactionSummaryView.addGestureRecognizer(summaryTap)
    }
    
    private func setupGradient() {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor,
            UIColor.black.withAlphaComponent(0.9).cgColor
        ]
        gradientLayer.locations = [0.0, 0.3, 0.8, 1.0]  // Smooth gradient transition
        gradientView.layer.addSublayer(gradientLayer)
        
        // Frame will be updated in layoutSubviews
    }
    
    private func setupGestures() {
        // Double tap to like
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        videoContainerView.addGestureRecognizer(doubleTap)
        
        // Single tap to play/pause
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        videoContainerView.addGestureRecognizer(singleTap)
        
        // Profile tap
        let profileTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        profileImageView.addGestureRecognizer(profileTap)
        
        // Username tap
        let usernameTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        usernameLabel.isUserInteractionEnabled = true
        usernameLabel.addGestureRecognizer(usernameTap)
        
        // Place tap
        let placeTap = UITapGestureRecognizer(target: self, action: #selector(placeTapped))
        placeNameLabel.isUserInteractionEnabled = true
        placeNameLabel.addGestureRecognizer(placeTap)
        
        // Like count tap
        let likeCountTap = UITapGestureRecognizer(target: self, action: #selector(likeCountTapped))
        likeCountLabel.isUserInteractionEnabled = true
        likeCountLabel.addGestureRecognizer(likeCountTap)
    }
    
    // MARK: - Configuration
    func configure(with reel: PlaceVideo, player: AVPlayer? = nil) {
        self.reel = reel
        
        // Ensure layout is complete before configuring
        contentView.layoutIfNeeded()
        videoContainerView.layoutIfNeeded()
        
        print("📹 VideoReelCell: Configuring cell for reel:")
        print("   - ID: \(reel.id)")
        print("   - Title: \(reel.title)")
        print("   - Content Type: \(reel.contentType ?? "video")")
        print("   - Video Type: \(reel.videoType ?? "nil")")
        print("   - Is Embedded: \(reel.isEmbedded)")
        print("   - Embed URL: \(reel.embedUrl ?? "nil")")
        print("   - Embed Platform: \(reel.embedPlatform ?? "nil")")
        print("   - Has Player: \(player != nil)")
        print("   - Video URL: \(reel.videoUrl ?? "nil")")
        print("   - Preview URL: \(reel.previewUrl ?? "nil")")
        
        // Set like state based on server data
        self.isLiked = reel.likedByCurrentUser ?? false
        updateLikeButton()
        
        // Clear previous video views
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        embeddedPlayerView?.removeFromSuperview()
        embeddedPlayerView = nil
        photoImageView.image = nil
        photoImageView.isHidden = true
        photoImageView.removeFromSuperview()
        
        // Configure watch on platform button for embedded videos
        if reel.isEmbedded, let platform = reel.embedPlatform {
            watchOnPlatformButton.isHidden = false
            let platformName = platform.capitalized
            watchOnPlatformButton.setTitle("Watch on \(platformName)", for: .normal)
        } else {
            watchOnPlatformButton.isHidden = true
        }
        
        // Setup display based on content type
        if reel.contentType == "photo" {
            // Display photo
            soundButton.isHidden = true // Hide sound button for photos
            
            // Add photo image view if not already added
            if photoImageView.superview == nil {
                videoContainerView.insertSubview(photoImageView, at: 0)
                NSLayoutConstraint.activate([
                    photoImageView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
                    photoImageView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
                    photoImageView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
                    photoImageView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor)
                ])
            }
            photoImageView.isHidden = false
            
            // Load the photo from thumbnail URL
            if let thumbnailUrl = reel.thumbnailUrl {
                ImageService.shared.loadImage(from: thumbnailUrl) { [weak self] image in
                    self?.photoImageView.image = image
                }
            }
        } else if reel.isEmbedded {
            // Create and configure embedded player view
            soundButton.isHidden = false
            let embedView = EmbeddedVideoPlayerView()
            embedView.translatesAutoresizingMaskIntoConstraints = false
            videoContainerView.addSubview(embedView)
            NSLayoutConstraint.activate([
                embedView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
                embedView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
                embedView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
                embedView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor)
            ])
            embedView.loadVideo(reel)
            embeddedPlayerView = embedView
        } else if let player = player {
            // Setup video player layer for uploaded videos
            soundButton.isHidden = false
            photoImageView.isHidden = true  // Ensure photo view is hidden for videos
            
            let newPlayerLayer = AVPlayerLayer(player: player)
            newPlayerLayer.videoGravity = .resizeAspectFill  // Fill the entire container, cropping if needed
            // Set frame after ensuring layout is complete
            videoContainerView.layoutIfNeeded()
            newPlayerLayer.frame = videoContainerView.bounds
            newPlayerLayer.backgroundColor = UIColor.black.cgColor  // Black background
            newPlayerLayer.opacity = 1.0
            newPlayerLayer.isHidden = false
            
            // Observe player item status
            playerItemObserver = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    print("📹 VideoReelCell: Player item status changed: \(item.status.rawValue)")
                    if item.status == .readyToPlay {
                        print("📹 VideoReelCell: Video ready to play!")
                        self?.playerLayer?.isHidden = false
                        // Don't auto-play here - let CirclesHomeViewController control playback
                    } else if item.status == .failed {
                        print("❌ VideoReelCell: Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
            
            // Add observer for video end to loop playback
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidReachEnd(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
            
            // Remove any existing player layer first
            playerLayer?.removeFromSuperlayer()
            
            // Remove any existing video layers to ensure clean state
            videoContainerView.layer.sublayers?.forEach { layer in
                if layer is AVPlayerLayer {
                    layer.removeFromSuperlayer()
                }
            }
            
            // Insert the new player layer at the bottom (index 0) so UI elements appear on top
            videoContainerView.layer.insertSublayer(newPlayerLayer, at: 0)
            playerLayer = newPlayerLayer
            
            // Ensure video container has black background
            videoContainerView.backgroundColor = .black
            
            // Ensure video container is visible
            videoContainerView.isHidden = false
            videoContainerView.alpha = 1.0
            
            // Debug logging
            print("📹 VideoReelCell: Added player layer with frame: \(newPlayerLayer.frame)")
            print("📹 VideoReelCell: Video container bounds: \(videoContainerView.bounds)")
            print("📹 VideoReelCell: Player status: \(player.status.rawValue)")
            if let currentItem = player.currentItem {
                print("📹 VideoReelCell: Player item status: \(currentItem.status.rawValue)")
                print("📹 VideoReelCell: Player item duration: \(currentItem.duration.seconds)")
            }
            print("📹 VideoReelCell: Video container hidden: \(videoContainerView.isHidden)")
            print("📹 VideoReelCell: Video container alpha: \(videoContainerView.alpha)")
            print("📹 VideoReelCell: Number of sublayers: \(videoContainerView.layer.sublayers?.count ?? 0)")
            
            // Don't auto-play here - let CirclesHomeViewController control playback
            print("📹 VideoReelCell: Player configured, waiting for playback command")
            
            // Force layout update
            videoContainerView.setNeedsLayout()
            videoContainerView.layoutIfNeeded()
            
            // Debug: Print view hierarchy
            debugPrintViewHierarchy()
        }
        
        // Configure UI
        usernameLabel.text = "@\(reel.user?.displayName ?? "unknown")"
        placeNameLabel.text = "📍 \(reel.placeName)"
        descriptionLabel.text = reel.description.isEmpty ? reel.title : reel.description
        likeCountLabel.text = formatCount(reel.likeCount)
        commentCountLabel.text = formatCount(reel.commentCount)
        
        // Configure activity reaction UI
        configureReactionUI(for: reel)
        
        // Load profile image
        if let urlString = reel.user?.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                self?.profileImageView.image = image
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
        }
        
        // Update follow button visibility
        followButton.isHidden = reel.userId == AuthService.shared.currentUser?.id
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update player layer frame
        if let playerLayer = playerLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = videoContainerView.bounds
            CATransaction.commit()
            print("📹 VideoReelCell: Updated player layer frame in layoutSubviews: \(playerLayer.frame)")
            print("📹 VideoReelCell: Player layer bounds: \(playerLayer.bounds)")
            print("📹 VideoReelCell: Player ready for display: \(playerLayer.isReadyForDisplay)")
            print("📹 VideoReelCell: ContentView bounds: \(contentView.bounds)")
            print("📹 VideoReelCell: VideoContainer bounds: \(videoContainerView.bounds)")
        }
        
        // Update gradient frame
        if let gradientLayer = gradientView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = gradientView.bounds
        }
    }
    
    // MARK: - Actions
    @objc private func likeTapped() {
        isLiked.toggle()
        updateLikeButton()
        delegate?.videoReelCellDidTapLike(self)
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    @objc private func commentTapped() {
        delegate?.videoReelCellDidTapComment(self)
    }
    
    @objc private func shareTapped() {
        delegate?.videoReelCellDidTapShare(self)
    }
    
    @objc private func reactionTapped() {
        delegate?.videoReelCellDidTapReaction(self)
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    @objc private func reactionSummaryTapped() {
        delegate?.videoReelCellDidTapActivityEngagement(self)
    }
    
    @objc private func watchOnPlatformTapped() {
        guard let reel = reel,
              let embedUrl = reel.embedUrl,
              let url = URL(string: embedUrl) else { return }
        
        // Open the original platform URL in Safari
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc private func soundTapped() {
        // Don't do anything for photos
        if reel?.contentType == "photo" { return }
        
        if let player = playerLayer?.player {
            player.isMuted.toggle()
            soundButton.setImage(UIImage(systemName: player.isMuted ? "speaker.slash" : "speaker.wave.2"), for: .normal)
        } else if embeddedPlayerView != nil {
            // Toggle mute for embedded video
            if soundButton.currentImage == UIImage(systemName: "speaker.wave.2") {
                embeddedPlayerView?.mute()
                soundButton.setImage(UIImage(systemName: "speaker.slash"), for: .normal)
            } else {
                embeddedPlayerView?.unmute()
                soundButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
            }
        }
    }
    
    @objc private func playPauseTapped() {
        togglePlayPause()
    }
    
    @objc private func singleTapped() {
        togglePlayPause()
    }
    
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        // Loop the video by seeking to the beginning and playing again
        guard let playerItem = notification.object as? AVPlayerItem,
              let player = playerLayer?.player,
              player.currentItem == playerItem else { return }
        
        player.seek(to: .zero) { _ in
            player.play()
        }
    }
    
    @objc private func doubleTapped(gesture: UITapGestureRecognizer) {
        // Like animation
        isLiked = true
        updateLikeButton()
        delegate?.videoReelCellDidTapLike(self)
        
        // Show heart animation
        showHeartAnimation(at: gesture.location(in: videoContainerView))
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    @objc private func profileTapped() {
        delegate?.videoReelCellDidTapProfile(self)
    }
    
    @objc private func placeTapped() {
        delegate?.videoReelCellDidTapPlace(self)
    }
    
    @objc private func likeCountTapped() {
        delegate?.videoReelCellDidTapLikeCount(self)
    }
    
    // MARK: - Helper Methods
    private func togglePlayPause() {
        // Don't show play/pause for photos
        if reel?.contentType == "photo" { return }
        
        if let player = playerLayer?.player {
            if player.rate == 0 {
                // Check if video has ended (at the end of playback)
                let currentTime = player.currentTime()
                let duration = player.currentItem?.duration ?? .zero
                
                if CMTimeCompare(currentTime, duration) >= 0 || currentTime.seconds > 0 {
                    // Video has ended or is paused mid-way, restart from beginning
                    player.seek(to: .zero) { _ in
                        player.play()
                    }
                } else {
                    // Just play from current position
                    player.play()
                }
                playPauseButton.isHidden = true
            } else {
                player.pause()
                playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
                playPauseButton.isHidden = false
            }
        } else if let embedView = embeddedPlayerView {
            // Toggle play/pause for embedded video
            if playPauseButton.isHidden {
                embedView.pause()
                playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
                playPauseButton.isHidden = false
            } else {
                embedView.play()
                playPauseButton.isHidden = true
            }
        }
    }
    
    private func updateLikeButton() {
        let imageName = isLiked ? "heart.fill" : "heart"
        likeButton.setImage(UIImage(systemName: imageName), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : .white
        
        // Update count
        if let reel = reel {
            let newCount = isLiked ? reel.likeCount + 1 : max(0, reel.likeCount - 1)
            likeCountLabel.text = formatCount(newCount)
        }
    }
    
    private func showHeartAnimation(at point: CGPoint) {
        let heartImageView = UIImageView(image: UIImage(systemName: "heart.fill"))
        heartImageView.tintColor = .systemRed
        heartImageView.frame = CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80)
        videoContainerView.addSubview(heartImageView)
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            heartImageView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            heartImageView.alpha = 0.8
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                heartImageView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                heartImageView.alpha = 0
            }) { _ in
                heartImageView.removeFromSuperview()
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    private func configureReactionUI(for video: PlaceVideo) {
        // Update reaction count
        let reactionCount = video.activityReactionCount ?? 0
        reactionCountLabel.text = reactionCount > 0 ? formatCount(reactionCount) : ""
        
        // Update reaction button if user has reacted
        if let userReaction = video.userActivityReaction {
            reactionButton.setTitle(userReaction, for: .normal)
            reactionButton.setImage(nil, for: .normal)
            reactionButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        } else {
            reactionButton.setTitle(nil, for: .normal)
            reactionButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        }
        
        // Clear previous reaction summary
        reactionSummaryView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add reaction summary if there's an activityId
        if video.activityId != nil && reactionCount > 0 {
            // For now, just show the total count
            // In a full implementation, we'd fetch the reaction summary
            let summaryLabel = UILabel()
            summaryLabel.text = "👀 \(formatCount(reactionCount))"
            summaryLabel.textColor = .white
            summaryLabel.font = UIFont.systemFont(ofSize: 12)
            summaryLabel.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            summaryLabel.layer.cornerRadius = 10
            summaryLabel.textAlignment = .center
            summaryLabel.layer.masksToBounds = true
            reactionSummaryView.addArrangedSubview(summaryLabel)
            
            NSLayoutConstraint.activate([
                summaryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
                summaryLabel.heightAnchor.constraint(equalToConstant: 20)
            ])
        }
    }
    
    // MARK: - Debug
    private func debugPrintViewHierarchy() {
        print("📹 VideoReelCell: View hierarchy:")
        print("   - contentView frame: \(contentView.frame)")
        print("   - videoContainerView frame: \(videoContainerView.frame)")
        print("   - videoContainerView subviews: \(videoContainerView.subviews.count)")
        
        for (index, subview) in videoContainerView.subviews.enumerated() {
            print("     Subview \(index): \(type(of: subview)) - frame: \(subview.frame), hidden: \(subview.isHidden), alpha: \(subview.alpha)")
        }
        
        if let sublayers = videoContainerView.layer.sublayers {
            print("   - videoContainerView sublayers: \(sublayers.count)")
            for (index, layer) in sublayers.enumerated() {
                print("     Layer \(index): \(type(of: layer)) - frame: \(layer.frame), hidden: \(layer.isHidden), opacity: \(layer.opacity)")
            }
        }
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Clean up observer
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        // Remove video layers
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        // Remove embedded video view
        embeddedPlayerView?.removeFromSuperview()
        embeddedPlayerView = nil
        
        // Clear image views completely
        photoImageView.image = nil
        photoImageView.isHidden = true
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = .systemGray
        
        // Reset UI elements
        soundButton.isHidden = false
        soundButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        playPauseButton.isHidden = true
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        
        // Reset state
        isLiked = false
        reel = nil
        
        // Clear labels
        usernameLabel.text = ""
        placeNameLabel.text = ""
        descriptionLabel.text = ""
        likeCountLabel.text = "0"
        commentCountLabel.text = "0"
        reactionCountLabel.text = ""
        
        // Reset buttons
        likeButton.setImage(UIImage(systemName: "heart"), for: .normal)
        likeButton.tintColor = .white
        reactionButton.setTitle(nil, for: .normal)
        reactionButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        
        // Clear reaction summary
        reactionSummaryView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Reset follow button
        followButton.isHidden = false
    }
}