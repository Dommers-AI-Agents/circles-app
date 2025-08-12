import UIKit
import AVFoundation

protocol VideoReelCellDelegate: AnyObject {
    func videoReelCellDidTapLike(_ cell: VideoReelCell)
    func videoReelCellDidTapComment(_ cell: VideoReelCell)
    func videoReelCellDidTapShare(_ cell: VideoReelCell)
    func videoReelCellDidTapProfile(_ cell: VideoReelCell)
    func videoReelCellDidTapPlace(_ cell: VideoReelCell)
}

class VideoReelCell: UICollectionViewCell {
    
    // MARK: - Properties
    weak var delegate: VideoReelCellDelegate?
    private var playerLayer: AVPlayerLayer?
    private var embeddedPlayerView: EmbeddedVideoPlayerView?
    private var isLiked = false
    private var reel: PlaceVideo?
    
    // MARK: - UI Elements
    private let videoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let gradientView: UIView = {
        let view = UIView()
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
    
    private let soundButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
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
        
        // Add subviews
        contentView.addSubview(videoContainerView)
        contentView.addSubview(gradientView)
        contentView.addSubview(profileImageView)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(followButton)
        contentView.addSubview(placeNameLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(likeButton)
        contentView.addSubview(likeCountLabel)
        contentView.addSubview(commentButton)
        contentView.addSubview(commentCountLabel)
        contentView.addSubview(shareButton)
        contentView.addSubview(soundButton)
        contentView.addSubview(playPauseButton)
        
        // Setup gradient
        setupGradient()
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Video container
            videoContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            videoContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Gradient
            gradientView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 300),
            
            // Right side actions
            shareButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            shareButton.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -100),
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
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -16),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            
            placeNameLabel.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor),
            placeNameLabel.trailingAnchor.constraint(equalTo: descriptionLabel.trailingAnchor),
            placeNameLabel.bottomAnchor.constraint(equalTo: descriptionLabel.topAnchor, constant: -8),
            
            usernameLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            usernameLabel.bottomAnchor.constraint(equalTo: placeNameLabel.topAnchor, constant: -8),
            
            followButton.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 12),
            followButton.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            
            // Sound button
            soundButton.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 16),
            soundButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            soundButton.widthAnchor.constraint(equalToConstant: 40),
            soundButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Play/Pause button (center)
            playPauseButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 60),
            playPauseButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        // Add button targets
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        soundButton.addTarget(self, action: #selector(soundTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
    }
    
    private func setupGradient() {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.8).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientView.layer.addSublayer(gradientLayer)
        
        // Update gradient frame in layoutSubviews
        gradientLayer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 300)
    }
    
    private func setupGestures() {
        // Double tap to like
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(doubleTap)
        
        // Single tap to play/pause
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        contentView.addGestureRecognizer(singleTap)
        
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
    }
    
    // MARK: - Configuration
    func configure(with reel: PlaceVideo, player: AVPlayer? = nil) {
        self.reel = reel
        
        // Clear previous video views
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        embeddedPlayerView?.removeFromSuperview()
        embeddedPlayerView = nil
        
        // Setup video display based on type
        if reel.isEmbedded {
            // Create and configure embedded player view
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
            let newPlayerLayer = AVPlayerLayer(player: player)
            newPlayerLayer.videoGravity = .resizeAspectFill
            newPlayerLayer.frame = videoContainerView.bounds
            videoContainerView.layer.addSublayer(newPlayerLayer)
            playerLayer = newPlayerLayer
        }
        
        // Configure UI
        usernameLabel.text = "@\(reel.user?.displayName ?? "unknown")"
        placeNameLabel.text = "📍 \(reel.placeName)"
        descriptionLabel.text = reel.description.isEmpty ? reel.title : reel.description
        likeCountLabel.text = formatCount(reel.likeCount)
        commentCountLabel.text = formatCount(reel.commentCount)
        
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
        playerLayer?.frame = videoContainerView.bounds
        
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
    
    @objc private func soundTapped() {
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
    
    @objc private func doubleTapped(gesture: UITapGestureRecognizer) {
        // Like animation
        isLiked = true
        updateLikeButton()
        delegate?.videoReelCellDidTapLike(self)
        
        // Show heart animation
        showHeartAnimation(at: gesture.location(in: contentView))
        
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
    
    // MARK: - Helper Methods
    private func togglePlayPause() {
        if let player = playerLayer?.player {
            if player.rate == 0 {
                player.play()
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
        contentView.addSubview(heartImageView)
        
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
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        embeddedPlayerView?.removeFromSuperview()
        embeddedPlayerView = nil
        isLiked = false
        profileImageView.image = nil
        playPauseButton.isHidden = true
    }
}