import UIKit

class CircleCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addShadow(opacity: 0.1, radius: 5, offset: CGSize(width: 0, height: 2))
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
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
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            coverImageView.heightAnchor.constraint(equalToConstant: 80),
            
            nameLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            placeCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            placeCountLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            placeCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            
            privacyImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            privacyImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            privacyImageView.widthAnchor.constraint(equalToConstant: 20),
            privacyImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    // MARK: - Configure
    func configure(with circle: Circle) {
        nameLabel.text = circle.name
        
        let placeCount = circle.places?.count ?? 0
        placeCountLabel.text = "\(placeCount) \(placeCount == 1 ? "place" : "places")"
        
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