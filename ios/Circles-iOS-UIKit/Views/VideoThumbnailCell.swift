import UIKit

class VideoThumbnailCell: UICollectionViewCell {
    
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
            viewCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        
        // Add padding to labels
        durationLabel.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        viewCountLabel.layoutMargins = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    }
    
    // MARK: - Configuration
    
    func configure(with video: PlaceVideo) {
        // Check if this is a photo or video
        let isPhoto = video.contentType == "photo"
        
        // Hide play icon and duration for photos
        playIconView.isHidden = isPhoto || video.uploadStatus != .ready
        durationLabel.isHidden = isPhoto
        
        // Set duration (only for videos)
        if !isPhoto {
            durationLabel.text = " \(video.formattedDuration) "
        }
        
        // Set view count (for both photos and videos)
        let viewCountText = video.viewCount == 1 ? "1 view" : "\(video.viewCount) views"
        viewCountLabel.text = " \(viewCountText) "
        
        // Load thumbnail
        if let thumbnailUrl = video.thumbnailUrl {
            ImageService.shared.loadImage(from: thumbnailUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.thumbnailImageView.image = image
                }
            }
        } else {
            thumbnailImageView.image = nil
        }
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
        durationLabel.text = nil
        durationLabel.isHidden = false
        viewCountLabel.text = nil
        playIconView.isHidden = false
    }
}