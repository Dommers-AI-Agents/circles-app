import UIKit

class VideoThumbnailCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    private var currentThumbnailLoadId: String?
    private var currentThumbnailUrl: String?
    
    // MARK: - UI Elements
    
    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.secondaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let playIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "play.circle.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.alpha = 0.9
        return imageView
    }()
    
    private let viewCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let processingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        indicator.layer.cornerRadius = 15
        indicator.clipsToBounds = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private let processingLabel: UILabel = {
        let label = UILabel()
        label.text = "Processing..."
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        contentView.backgroundColor = Constants.Colors.secondaryBackground
        
        // Add subviews
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(playIconView)
        contentView.addSubview(durationLabel)
        contentView.addSubview(viewCountLabel)
        contentView.addSubview(processingIndicator)
        contentView.addSubview(processingLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Thumbnail image fills the cell
            thumbnailImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Play icon centered
            playIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playIconView.widthAnchor.constraint(equalToConstant: 40),
            playIconView.heightAnchor.constraint(equalToConstant: 40),
            
            // Duration label at bottom right
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            durationLabel.heightAnchor.constraint(equalToConstant: 20),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 35),
            
            // View count at bottom left
            viewCountLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            viewCountLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            viewCountLabel.heightAnchor.constraint(equalToConstant: 20),
            viewCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            // Processing indicator centered
            processingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            processingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            processingIndicator.widthAnchor.constraint(equalToConstant: 30),
            processingIndicator.heightAnchor.constraint(equalToConstant: 30),
            
            // Processing label below indicator
            processingLabel.topAnchor.constraint(equalTo: processingIndicator.bottomAnchor, constant: 8),
            processingLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            processingLabel.heightAnchor.constraint(equalToConstant: 20),
            processingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
        
        // Add padding to labels
        durationLabel.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        viewCountLabel.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    }
    
    // MARK: - Configuration
    
    func configure(with video: PlaceVideo) {
        // Clear cache for previous thumbnail if it exists
        if let previousUrl = currentThumbnailUrl {
            ImageService.shared.clearCacheForUrl(previousUrl)
        }
        
        // Reset the image immediately to prevent showing stale content
        thumbnailImageView.image = nil
        thumbnailImageView.backgroundColor = Constants.Colors.secondaryBackground
        currentThumbnailLoadId = nil
        currentThumbnailUrl = nil
        
        // Check if this is a photo or video
        let isPhoto = video.contentType == "photo"
        
        // Determine if video is still processing
        let isProcessing = video.uploadStatus == .processing || video.uploadStatus == .uploading
        
        // Hide play icon and duration for photos or processing videos
        playIconView.isHidden = isPhoto || video.uploadStatus != .ready
        durationLabel.isHidden = isPhoto || isProcessing
        
        // Show processing indicators for processing videos (not photos)
        if !isPhoto && isProcessing {
            processingIndicator.startAnimating()
            processingLabel.isHidden = false
        } else {
            processingIndicator.stopAnimating()
            processingLabel.isHidden = true
        }
        
        // Set duration (only for videos)
        if !isPhoto {
            durationLabel.text = " \(video.formattedDuration) "
        }
        
        // Set view count (for both photos and videos)
        let viewCountText = video.viewCount == 1 ? "1 view" : "\(video.viewCount) views"
        viewCountLabel.text = " \(viewCountText) "
        
        // Load thumbnail with tracking to prevent race conditions
        if let thumbnailUrl = video.thumbnailUrl {
            // Store the current thumbnail URL
            currentThumbnailUrl = thumbnailUrl
            
            // Generate a unique ID for this load request including video ID for better tracking
            let loadId = "\(video.id)_\(UUID().uuidString)"
            currentThumbnailLoadId = loadId
            
            // Debug logging with URL
            print("🖼️ VideoThumbnailCell: Loading thumbnail for video \(video.id)")
            print("   - URL: \(thumbnailUrl)")
            print("   - LoadId: \(loadId)")
            print("   - ContentType: \(video.contentType ?? "video")")
            
            // Use a unique cache key that includes the video ID
            let uniqueCacheKey = "\(thumbnailUrl)_\(video.id)"
            
            ImageService.shared.loadImageWithKey(from: thumbnailUrl, cacheKey: uniqueCacheKey) { [weak self] image in
                DispatchQueue.main.async {
                    // Only update image if this is still the current load request
                    guard let self = self else {
                        print("🖼️ VideoThumbnailCell: Cell deallocated for loadId: \(loadId)")
                        return
                    }
                    
                    guard self.currentThumbnailLoadId == loadId else {
                        print("🖼️ VideoThumbnailCell: Ignoring stale load. Current: \(self.currentThumbnailLoadId ?? "nil"), Received: \(loadId)")
                        return
                    }
                    
                    if let image = image {
                        print("🖼️ VideoThumbnailCell: Successfully applied image for video \(video.id)")
                        self.thumbnailImageView.image = image
                        self.thumbnailImageView.backgroundColor = .clear
                    } else {
                        print("⚠️ VideoThumbnailCell: Failed to load image for video \(video.id)")
                        self.thumbnailImageView.image = nil
                        self.thumbnailImageView.backgroundColor = Constants.Colors.secondaryBackground
                    }
                }
            }
        } else {
            currentThumbnailLoadId = nil
            currentThumbnailUrl = nil
            thumbnailImageView.image = nil
            print("🖼️ VideoThumbnailCell: No thumbnail URL for video \(video.id)")
        }
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Clear cache for current thumbnail
        if let currentUrl = currentThumbnailUrl {
            // Don't clear from cache on reuse, just reset the reference
            currentThumbnailUrl = nil
        }
        
        // Clear the load ID to prevent stale image loads
        currentThumbnailLoadId = nil
        thumbnailImageView.image = nil
        thumbnailImageView.backgroundColor = Constants.Colors.secondaryBackground
        processingIndicator.stopAnimating()
        processingLabel.isHidden = true
        durationLabel.text = nil
        durationLabel.isHidden = false
        viewCountLabel.text = nil
        playIconView.isHidden = false
    }
}