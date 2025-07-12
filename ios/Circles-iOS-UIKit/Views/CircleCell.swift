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
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
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
            
            // Activity indicator in top left corner
            activityIndicatorView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            activityIndicatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            activityIndicatorView.widthAnchor.constraint(equalToConstant: 8),
            activityIndicatorView.heightAnchor.constraint(equalToConstant: 8)
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
        activityIndicatorView.isHidden = !(circle.hasNewPlaces ?? false)
        
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
            ImageService.shared.loadImage(from: coverImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.coverImageView.image = image
                    self?.updateCornerRadius()
                }
            }
        } else {
            // Set default image based on category
            coverImageView.image = UIImage(systemName: categoryIcon(for: circle.category))
            coverImageView.tintColor = Constants.Colors.primary
            coverImageView.contentMode = .scaleAspectFit
        }
        
        // Force layout to ensure circular shape is applied immediately
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func categoryIcon(for category: CircleCategory) -> String {
        switch category {
        case .travel: return "airplane"
        case .food: return "fork.knife"
        case .services: return "wrench.and.screwdriver"
        case .shopping: return "bag"
        case .healthcare: return "heart"
        case .entertainment: return "tv"
        case .other: return "circle.grid.3x3"
        }
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        nameLabel.text = nil
        placeCountLabel.text = nil
        privacyImageView.image = nil
        activityIndicatorView.isHidden = true
    }
}