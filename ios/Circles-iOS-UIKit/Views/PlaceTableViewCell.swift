import UIKit

// Place row used by CircleDetailViewController. Extracted from that file
// (it was defined between two of the controller's extensions).
class PlaceTableViewCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let imageLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.primary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let imageGradientView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()
    
    private let activityIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        // Add shadow for better visibility
        view.layer.shadowColor = UIColor.systemRed.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 0)
        view.layer.shadowRadius = 3
        view.layer.shadowOpacity = 0.8
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = false
        label.alpha = 1.0
        label.backgroundColor = .clear
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = Constants.Colors.white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // "🔒 Private" chip — shown only on the owner's private places, so they can
    // see at a glance which saves are hidden from followers/connections.
    private let privacyChip: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemFill // subtle gray pill, adapts to dark mode
        view.layer.cornerRadius = 10
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let privacyChipIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let privacyChipLabel: UILabel = {
        let label = UILabel()
        label.text = "Private"
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private let ratingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let ratingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "star.fill")
        imageView.tintColor = UIColor(hex: "#F6E05E") // Yellow
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let ratingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let directionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let likeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        return label
    }()
    
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.right"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        return label
    }()
    
    // Closure for share action
    var onShareTapped: ((Place) -> Void)?
    var onDirectionsTapped: ((Place) -> Void)?
    var onLikeTapped: ((Place) -> Void)?
    var onCommentTapped: ((Place) -> Void)?
    private var place: Place?
    private var photoLoadingTask: URLSessionDataTask?
    
    // Image cache specifically for Google Places photos
    private static let googlePhotosCache = NSCache<NSString, UIImage>()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        containerView.addSubview(placeImageView)
        containerView.addSubview(imageGradientView)
        containerView.addSubview(categoryIconView)
        containerView.addSubview(imageLoadingIndicator)
        containerView.addSubview(nameLabel)
        containerView.addSubview(categoryLabel)
        containerView.addSubview(privacyChip)
        privacyChip.addSubview(privacyChipIcon)
        privacyChip.addSubview(privacyChipLabel)
        containerView.addSubview(addressLabel)
        containerView.addSubview(shareButton)
        containerView.addSubview(directionsButton)
        containerView.addSubview(likeButton)
        containerView.addSubview(likeCountLabel)
        containerView.addSubview(commentButton)
        containerView.addSubview(commentCountLabel)
        containerView.addSubview(activityIndicatorView)
        
        // Add rating view as overlay on image
        placeImageView.addSubview(ratingView)
        ratingView.addSubview(ratingImageView)
        ratingView.addSubview(ratingLabel)
        
        // Add target for share button
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        // Add target for directions button
        directionsButton.addTarget(self, action: #selector(directionsButtonTapped), for: .touchUpInside)
        // Add target for like button
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        // Add target for comment button
        commentButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.small),
            
            // Place image view
            placeImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            placeImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            placeImageView.widthAnchor.constraint(equalToConstant: 80),
            placeImageView.heightAnchor.constraint(equalToConstant: 80),
            placeImageView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small),
            
            // Image gradient view (same as image view)
            imageGradientView.topAnchor.constraint(equalTo: placeImageView.topAnchor),
            imageGradientView.leadingAnchor.constraint(equalTo: placeImageView.leadingAnchor),
            imageGradientView.trailingAnchor.constraint(equalTo: placeImageView.trailingAnchor),
            imageGradientView.bottomAnchor.constraint(equalTo: placeImageView.bottomAnchor),
            
            // Category icon view (centered on top of image view)
            categoryIconView.centerXAnchor.constraint(equalTo: placeImageView.centerXAnchor),
            categoryIconView.centerYAnchor.constraint(equalTo: placeImageView.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: 40),
            categoryIconView.heightAnchor.constraint(equalToConstant: 40),
            
            // Image loading indicator
            imageLoadingIndicator.centerXAnchor.constraint(equalTo: placeImageView.centerXAnchor),
            imageLoadingIndicator.centerYAnchor.constraint(equalTo: placeImageView.centerYAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            nameLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.trailingAnchor.constraint(equalTo: likeCountLabel.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Directions button
            directionsButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            directionsButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -Constants.Spacing.tiny),
            directionsButton.widthAnchor.constraint(equalToConstant: 30),
            directionsButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Share button
            shareButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            shareButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            shareButton.widthAnchor.constraint(equalToConstant: 30),
            shareButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            categoryLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20),

            // Privacy chip — sits on the category line, just after the category pill
            privacyChip.leadingAnchor.constraint(equalTo: categoryLabel.trailingAnchor, constant: 6),
            privacyChip.centerYAnchor.constraint(equalTo: categoryLabel.centerYAnchor),
            privacyChip.heightAnchor.constraint(equalToConstant: 20),
            privacyChip.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),

            privacyChipIcon.leadingAnchor.constraint(equalTo: privacyChip.leadingAnchor, constant: 8),
            privacyChipIcon.centerYAnchor.constraint(equalTo: privacyChip.centerYAnchor),
            privacyChipIcon.widthAnchor.constraint(equalToConstant: 10),
            privacyChipIcon.heightAnchor.constraint(equalToConstant: 10),

            privacyChipLabel.leadingAnchor.constraint(equalTo: privacyChipIcon.trailingAnchor, constant: 3),
            privacyChipLabel.trailingAnchor.constraint(equalTo: privacyChip.trailingAnchor, constant: -8),
            privacyChipLabel.centerYAnchor.constraint(equalTo: privacyChip.centerYAnchor),


            // Address label
            addressLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            addressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Rating view - now overlay on bottom-left of image
            ratingView.bottomAnchor.constraint(equalTo: placeImageView.bottomAnchor, constant: -4),
            ratingView.leadingAnchor.constraint(equalTo: placeImageView.leadingAnchor, constant: 4),
            ratingView.widthAnchor.constraint(equalToConstant: 50),
            ratingView.heightAnchor.constraint(equalToConstant: 20),
            
            // Like button - now below directions button
            likeButton.topAnchor.constraint(equalTo: directionsButton.bottomAnchor, constant: Constants.Spacing.tiny),
            likeButton.trailingAnchor.constraint(equalTo: directionsButton.trailingAnchor),
            likeButton.widthAnchor.constraint(equalToConstant: 30),
            likeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Like count label - to the left of like button
            likeCountLabel.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -2),
            likeCountLabel.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            likeCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 24),
            
            // Comment button - below share button
            commentButton.topAnchor.constraint(equalTo: shareButton.bottomAnchor, constant: Constants.Spacing.tiny),
            commentButton.trailingAnchor.constraint(equalTo: shareButton.trailingAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 30),
            commentButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Comment count label - to the left of comment button
            commentCountLabel.trailingAnchor.constraint(equalTo: commentButton.leadingAnchor, constant: -2),
            commentCountLabel.centerYAnchor.constraint(equalTo: commentButton.centerYAnchor),
            commentCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 24),
            
            // Rating image view
            ratingImageView.leadingAnchor.constraint(equalTo: ratingView.leadingAnchor, constant: 4),
            ratingImageView.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            ratingImageView.widthAnchor.constraint(equalToConstant: 12),
            ratingImageView.heightAnchor.constraint(equalToConstant: 12),
            
            // Rating label
            ratingLabel.leadingAnchor.constraint(equalTo: ratingImageView.trailingAnchor, constant: 2),
            ratingLabel.trailingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: -4),
            ratingLabel.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            
            // Activity indicator in top left corner of place image (made bigger for visibility)
            activityIndicatorView.topAnchor.constraint(equalTo: placeImageView.topAnchor, constant: 4),
            activityIndicatorView.leadingAnchor.constraint(equalTo: placeImageView.leadingAnchor, constant: 4),
            activityIndicatorView.widthAnchor.constraint(equalToConstant: 10),
            activityIndicatorView.heightAnchor.constraint(equalToConstant: 10)
        ])
    }
    
    // MARK: - Configure
    func configure(with place: Place) {
        self.place = place
        nameLabel.text = place.name.isEmpty ? "Unnamed Place" : place.name

        // Flag private places so the owner can see which saves are hidden from
        // their followers/connections (backend already omits these for others,
        // so this chip is only ever seen by the owner).
        privacyChip.isHidden = place.privacy != .private

        // Highlight new places
        if place.isNew == true {
            containerView.layer.borderColor = Constants.Colors.primary.cgColor
            containerView.layer.borderWidth = 2
            containerView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.05)
            activityIndicatorView.isHidden = false
            
            // Add pulsing animation to the activity indicator
            let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
            pulseAnimation.fromValue = 1.0
            pulseAnimation.toValue = 1.3
            pulseAnimation.duration = 0.6
            pulseAnimation.autoreverses = true
            pulseAnimation.repeatCount = .infinity
            pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            activityIndicatorView.layer.add(pulseAnimation, forKey: "pulse")
            
            // Add new badge to name
            let attributedString = NSMutableAttributedString(string: nameLabel.text ?? "")
            let newBadge = NSAttributedString(
                string: " 🆕",  // Using emoji for better visibility
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: Constants.Colors.primary
                ]
            )
            attributedString.append(newBadge)
            nameLabel.attributedText = attributedString
        } else {
            containerView.layer.borderColor = Constants.Colors.separator.cgColor
            containerView.layer.borderWidth = 1
            containerView.backgroundColor = Constants.Colors.secondaryBackground
            activityIndicatorView.isHidden = true
            activityIndicatorView.layer.removeAnimation(forKey: "pulse")
            nameLabel.attributedText = nil
            nameLabel.text = place.name.isEmpty ? "Unnamed Place" : place.name
        }
        
        // Category label
        categoryLabel.text = "  \(place.displayCategory)  " // Add padding with spaces
        
        // Set category color and icon
        setCategoryAppearance(for: place.category)
        
        // Initially show category icon while loading photo
        categoryIconView.isHidden = false
        placeImageView.image = nil
        imageGradientView.isHidden = true
        
        // Setup gradient layer
        setupGradientLayer()
        
        // Cancel any previous photo loading task
        photoLoadingTask?.cancel()
        
        // Load place photo
        loadPlacePhoto(for: place)
        
        // Address
        if !place.address.isEmpty {
            addressLabel.text = place.address
        } else {
            addressLabel.text = "No address available"
        }
        
        // Rating
        if let rating = place.rating {
            ratingLabel.text = String(format: "%.1f", rating)
            ratingView.isHidden = false
        } else {
            ratingLabel.text = "N/A"
            ratingView.isHidden = true
        }
        
        // Like button and count
        let isLiked = place.isLikedByCurrentUser
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : Constants.Colors.primary
        
        let likeCount = place.likesCount ?? 0
        likeCountLabel.text = likeCount > 0 ? "\(likeCount)" : ""
        
        // Comment count
        let commentCount = place.commentsCount ?? 0
        commentCountLabel.text = commentCount > 0 ? "\(commentCount)" : ""
        
        // Show/hide directions button based on location availability
        directionsButton.isHidden = (place.location == nil)

        // Let UIKit coalesce the layout pass with the table's own — a forced
        // synchronous layoutIfNeeded per configure ran layout once per cell
        // per scroll frame.
        self.setNeedsLayout()
    }
    
    // MARK: - Photo Loading
    private func loadPlacePhoto(for place: Place) {
        // First check if we have stored photo URLs
        if let photos = place.photos, !photos.isEmpty, let firstPhotoUrl = photos.first {
            // Load from URL if available
            loadPhotoFromURL(firstPhotoUrl)
        } else {
            // No photo available, use category icon
            // Don't call Google Places API to save costs
            showCategoryIcon()
        }
    }
    
    // Removed loadGooglePlacePhoto to avoid unnecessary API calls
    // All photos should be stored when the place is created
    
    private func loadPhotoFromURL(_ urlString: String) {
        imageLoadingIndicator.startAnimating()

        // Capture which place this load was for — the cell may be recycled to
        // a different place before the image arrives, and painting the stale
        // result put the WRONG photo on fast scrolls.
        let requestedPlaceId = place?.id

        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            guard let self = self else { return }
            guard self.place?.id == requestedPlaceId else { return }

            if let image = image {
                self.placeImageView.image = image
                self.categoryIconView.isHidden = true
                self.imageGradientView.isHidden = false
                // Show rating view if we have a rating
                if self.place?.rating != nil {
                    self.ratingView.isHidden = false
                }
            } else {
                self.showCategoryIcon()
            }
            self.imageLoadingIndicator.stopAnimating()
        }
    }
    
    private func showCategoryIcon() {
        categoryIconView.isHidden = false
        placeImageView.image = nil
        imageGradientView.isHidden = true
        // Hide rating view when showing category icon
        ratingView.isHidden = true
    }
    
    private func setupGradientLayer() {
        // Remove existing gradient layers
        imageGradientView.layer.sublayers?.forEach { if $0 is CAGradientLayer { $0.removeFromSuperlayer() } }
        
        // Create gradient layer
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.3).cgColor
        ]
        gradientLayer.locations = [0.5, 1.0]
        gradientLayer.cornerRadius = 8
        
        imageGradientView.layer.addSublayer(gradientLayer)
    }
    
    private func setCategoryAppearance(for category: PlaceCategory) {
        // Set category label color
        switch category {
        case .restaurant:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
            categoryIconView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
            categoryIconView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            categoryLabel.backgroundColor = UIColor(hex: "#7B341E") // Brown
            categoryIconView.image = UIImage(systemName: "wineglass")
        case .hotel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            categoryIconView.image = UIImage(systemName: "bed.double")
        case .retail:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
            categoryIconView.image = UIImage(systemName: "bag")
        case .service:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
            categoryIconView.image = UIImage(systemName: "star")
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#9C4221") // Orange Brown
            categoryIconView.image = UIImage(systemName: "ticket")
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#319795") // Teal
            categoryIconView.image = UIImage(systemName: "cross.case")
        case .fitness:
            categoryLabel.backgroundColor = UIColor(hex: "#2C7A7B") // Dark Teal
            categoryIconView.image = UIImage(systemName: "figure.run")
        case .education:
            categoryLabel.backgroundColor = UIColor(hex: "#744210") // Dark Yellow
            categoryIconView.image = UIImage(systemName: "book")
        case .outdoor:
            categoryLabel.backgroundColor = UIColor(hex: "#2F855A") // Dark Green
            categoryIconView.image = UIImage(systemName: "tree")
        case .transport:
            categoryLabel.backgroundColor = UIColor(hex: "#2B6CB0") // Dark Blue
            categoryIconView.image = UIImage(systemName: "car")
        case .finance:
            categoryLabel.backgroundColor = UIColor(hex: "#285E61") // Dark Teal
            categoryIconView.image = UIImage(systemName: "dollarsign.circle")
        case .home:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            categoryIconView.image = UIImage(systemName: "house")
        case .work:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "building.2")
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "mappin")
        }
    }
    
    // MARK: - Actions
    @objc private func shareButtonTapped() {
        guard let place = place else { return }
        onShareTapped?(place)
    }
    
    @objc private func directionsButtonTapped() {
        guard let place = place else { return }
        onDirectionsTapped?(place)
    }
    
    @objc private func likeButtonTapped() {
        guard let place = place else { return }
        onLikeTapped?(place)
    }
    
    @objc private func commentButtonTapped() {
        guard let place = place else { return }
        onCommentTapped?(place)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        categoryLabel.text = nil
        addressLabel.text = nil
        ratingLabel.text = nil
        placeImageView.image = nil
        categoryIconView.isHidden = false
        imageGradientView.isHidden = true
        ratingView.isHidden = true  // Reset rating view visibility
        directionsButton.isHidden = false
        activityIndicatorView.isHidden = true
        photoLoadingTask?.cancel()
        imageLoadingIndicator.stopAnimating()
    }
}

// MARK: - EditCircleDelegate
