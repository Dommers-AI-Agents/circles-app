import UIKit

class CircleCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        // Circular design to match app theme
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let activityIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        // Add a subtle pulsing animation for better visibility
        view.layer.shadowColor = UIColor.systemRed.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 0)
        view.layer.shadowRadius = 3
        view.layer.shadowOpacity = 0.8
        return view
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.addSubview(containerView)
        containerView.addSubview(coverImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(placeCountLabel)
        containerView.addSubview(privacyImageView)
        containerView.addSubview(activityIndicatorView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor),
            
            // Position name label below the circular image
            nameLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            
            placeCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            placeCountLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            placeCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            placeCountLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -4),
            
            privacyImageView.topAnchor.constraint(equalTo: coverImageView.topAnchor, constant: 6),
            privacyImageView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -6),
            privacyImageView.widthAnchor.constraint(equalToConstant: 20),
            privacyImageView.heightAnchor.constraint(equalToConstant: 20),
            
            // Activity indicator in top left corner (made slightly bigger for better visibility)
            activityIndicatorView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            activityIndicatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            activityIndicatorView.widthAnchor.constraint(equalToConstant: 10),
            activityIndicatorView.heightAnchor.constraint(equalToConstant: 10)
        ])
        
        // Set initial corner radius based on expected size
        // This ensures circles appear circular even before layoutSubviews is called
        DispatchQueue.main.async { [weak self] in
            self?.updateCornerRadius()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
    }
    
    private func updateCornerRadius() {
        // Make the image circular
        let radius = coverImageView.bounds.width / 2
        if radius > 0 {
            coverImageView.layer.cornerRadius = radius
        }
    }
    
    // MARK: - Configure
    func configure(with circle: Circle) {
        nameLabel.text = circle.name
        
        // Use placesCount if available, otherwise fall back to places array count
        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
        placeCountLabel.text = "\(placeCount) \(placeCount == 1 ? "place" : "places")"
        
        // Show/hide activity indicator based on hasNewPlaces
        let hasNew = circle.hasNewPlaces ?? false
        activityIndicatorView.isHidden = !hasNew
        
        // Add pulsing animation if there are new places
        if hasNew {
            addPulsingAnimation()
        } else {
            removePulsingAnimation()
        }
        
        // Set privacy icon
        switch circle.privacy {
        case .public:
            privacyImageView.image = UIImage(systemName: "globe")
        case .myNetwork:
            privacyImageView.image = UIImage(systemName: "person.2")
        case .private:
            privacyImageView.image = UIImage(systemName: "lock")
        }
        
        // Load cover image
        if let coverImageUrl = circle.coverImage {
            // Check if it's a default SF Symbol
            if coverImageUrl.starts(with: "sf-symbol:") {
                let symbolName = String(coverImageUrl.dropFirst("sf-symbol:".count))
                if let defaultCase = DefaultImages.CircleDefault.allCases.first(where: { $0.rawValue == symbolName }) {
                    coverImageView.image = defaultCase.image(size: 60)
                    coverImageView.tintColor = defaultCase.color
                    coverImageView.contentMode = .scaleAspectFit
                } else {
                    // Fallback to the symbol name directly
                    coverImageView.image = UIImage(systemName: symbolName)
                    coverImageView.tintColor = Constants.Colors.primary
                    coverImageView.contentMode = .scaleAspectFit
                }
            } else {
                // Regular image URL
                ImageService.shared.loadImage(from: coverImageUrl) { [weak self] image in
                    DispatchQueue.main.async {
                        self?.coverImageView.image = image
                        self?.coverImageView.contentMode = .scaleAspectFill
                        self?.updateCornerRadius()
                    }
                }
            }
        } else {
            // Set default image based on category
            let defaultImage = DefaultImages.circleImageForCategory(circle.category)
            coverImageView.image = defaultImage.image(size: 60)
            coverImageView.tintColor = defaultImage.color
            coverImageView.contentMode = .scaleAspectFit
        }
        
        // Force layout to ensure circular shape is applied immediately
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    // MARK: - Animation Methods
    
    private func addPulsingAnimation() {
        // Create a pulsing animation for the new indicator
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.3
        pulseAnimation.duration = 0.6
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        activityIndicatorView.layer.add(pulseAnimation, forKey: "pulse")
    }
    
    private func removePulsingAnimation() {
        activityIndicatorView.layer.removeAnimation(forKey: "pulse")
    }
    
    // MARK: - Drag & Drop Visual States
    
    /// Set visual state for when this cell is being dragged
    func setDragState(_ isDragging: Bool) {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction]) {
            if isDragging {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.alpha = 0.8
                self.layer.shadowColor = UIColor.black.cgColor
                self.layer.shadowOpacity = 0.3
                self.layer.shadowOffset = CGSize(width: 0, height: 4)
                self.layer.shadowRadius = 8
            } else {
                self.transform = .identity
                self.alpha = 1.0
                self.layer.shadowOpacity = 0
            }
        }
    }
    
    /// Set visual state for when another item is being dragged over this cell
    func setDropTargetState(_ isDropTarget: Bool) {
        UIView.animate(withDuration: 0.2) {
            if isDropTarget {
                self.containerView.layer.borderWidth = 3
                self.containerView.layer.borderColor = Constants.Colors.primary.cgColor
                self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            } else {
                self.containerView.layer.borderWidth = 0
                self.transform = .identity
            }
        }
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Reset visual state
        transform = .identity
        alpha = 1.0
        layer.shadowOpacity = 0
        containerView.layer.borderWidth = 0
        
        // Reset content
        coverImageView.image = nil
        nameLabel.text = nil
        placeCountLabel.text = nil
        privacyImageView.image = nil
        activityIndicatorView.isHidden = true
    }
}