import UIKit

class UploadThumbnailCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    private var currentImageUrl: String?
    
    // MARK: - UI Elements
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.secondaryBackground
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let placeTagView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        view.layer.cornerRadius = 6
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeTagLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = Constants.Colors.primary
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // Top-right badge showing how many photos are in this place's group
    // (e.g. a stacked-photos icon + count). Hidden for single-photo places.
    private let countBadgeView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        view.layer.cornerRadius = 6
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let countBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let countBadgeIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "square.on.square"))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        
        contentView.addSubview(imageView)
        contentView.addSubview(placeTagView)
        placeTagView.addSubview(placeTagLabel)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(countBadgeView)
        countBadgeView.addSubview(countBadgeIcon)
        countBadgeView.addSubview(countBadgeLabel)

        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Image view fills the entire cell
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Place tag positioned at bottom with padding
            placeTagView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            placeTagView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            placeTagView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            placeTagView.heightAnchor.constraint(equalToConstant: 22),
            
            // Place tag label with padding
            placeTagLabel.topAnchor.constraint(equalTo: placeTagView.topAnchor, constant: 3),
            placeTagLabel.leadingAnchor.constraint(equalTo: placeTagView.leadingAnchor, constant: 8),
            placeTagLabel.trailingAnchor.constraint(equalTo: placeTagView.trailingAnchor, constant: -8),
            placeTagLabel.bottomAnchor.constraint(equalTo: placeTagView.bottomAnchor, constant: -3),
            
            // Loading indicator centered
            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Count badge, top-right
            countBadgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            countBadgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            countBadgeView.heightAnchor.constraint(equalToConstant: 22),

            countBadgeIcon.leadingAnchor.constraint(equalTo: countBadgeView.leadingAnchor, constant: 6),
            countBadgeIcon.centerYAnchor.constraint(equalTo: countBadgeView.centerYAnchor),
            countBadgeIcon.widthAnchor.constraint(equalToConstant: 12),
            countBadgeIcon.heightAnchor.constraint(equalToConstant: 12),

            countBadgeLabel.leadingAnchor.constraint(equalTo: countBadgeIcon.trailingAnchor, constant: 4),
            countBadgeLabel.trailingAnchor.constraint(equalTo: countBadgeView.trailingAnchor, constant: -6),
            countBadgeLabel.centerYAnchor.constraint(equalTo: countBadgeView.centerYAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    /// Configure as a place GROUP tile: cover photo, place name, and a count
    /// badge when the place has more than one photo.
    func configure(with group: UploadPlaceGroup) {
        configure(with: group.cover)
        if group.count > 1 {
            countBadgeLabel.text = "\(group.count)"
            countBadgeView.isHidden = false
        } else {
            countBadgeView.isHidden = true
        }
    }

    func configure(with upload: UserUploadedPhoto) {
        // Set place name
        placeTagLabel.text = upload.placeName
        countBadgeView.isHidden = true

        // Reset state
        imageView.image = nil
        currentImageUrl = upload.imageUrl
        loadingIndicator.startAnimating()
        
        // Load image with caching using unique cache key
        let uniqueCacheKey = "upload_\(upload.id)_\(upload.imageUrl.hashValue)"
        
        ImageService.shared.loadImageWithKey(
            from: upload.imageUrl,
            cacheKey: uniqueCacheKey
        ) { [weak self] image in
            DispatchQueue.main.async {
                // Check if this is still the current image request
                guard self?.currentImageUrl == upload.imageUrl else {
                    return
                }
                
                self?.loadingIndicator.stopAnimating()
                
                if let image = image {
                    self?.imageView.image = image
                } else {
                    // Show placeholder on error
                    self?.imageView.backgroundColor = Constants.Colors.secondaryBackground
                }
            }
        }
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Reset state
        currentImageUrl = nil
        imageView.image = nil
        placeTagLabel.text = nil
        countBadgeView.isHidden = true
        loadingIndicator.stopAnimating()
        imageView.backgroundColor = Constants.Colors.secondaryBackground
    }
}

// MARK: - Accessibility

extension UploadThumbnailCell {
    override func awakeFromNib() {
        super.awakeFromNib()
        setupAccessibility()
    }
    
    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double tap to view place details"
    }
    
    func updateAccessibility(with upload: UserUploadedPhoto) {
        accessibilityLabel = "Photo uploaded to \(upload.placeName)"
        accessibilityValue = "Uploaded on \(DateFormatter.localizedString(from: upload.uploadedAt, dateStyle: .medium, timeStyle: .none))"
    }
}