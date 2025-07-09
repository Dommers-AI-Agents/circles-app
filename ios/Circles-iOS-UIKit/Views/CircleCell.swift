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
        // No corner radius for Instagram-style grid
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .left
        label.numberOfLines = 1
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .white
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // Position name label at the bottom of the image with semi-transparent background
            nameLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            placeCountLabel.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -4),
            placeCountLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            placeCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            privacyImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            privacyImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            privacyImageView.widthAnchor.constraint(equalToConstant: 16),
            privacyImageView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    
    // MARK: - Configure
    func configure(with circle: Circle) {
        nameLabel.text = "  \(circle.name)  " // Add padding
        
        // Use placesCount if available, otherwise fall back to places array count
        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
        placeCountLabel.text = "  \(placeCount) \(placeCount == 1 ? "place" : "places")  " // Add padding
        
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
                }
            }
        } else {
            // Set default image based on category
            coverImageView.image = UIImage(systemName: categoryIcon(for: circle.category))
            coverImageView.tintColor = Constants.Colors.primary
            coverImageView.contentMode = .scaleAspectFit
        }
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
    }
}