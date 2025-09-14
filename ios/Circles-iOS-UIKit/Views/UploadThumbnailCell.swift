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
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with upload: UserUploadedPhoto) {
        // Set place name
        placeTagLabel.text = upload.placeName
        
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