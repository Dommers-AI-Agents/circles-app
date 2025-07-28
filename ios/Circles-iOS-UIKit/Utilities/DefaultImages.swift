import UIKit

// MARK: - DefaultImages
struct DefaultImages {
    
    // MARK: - Circle Default Images
    enum CircleDefault: String, CaseIterable {
        // Travel & Destinations
        case travel = "airplane.circle.fill"
        case beach = "beach.umbrella.fill"
        case mountain = "mountain.2.fill"
        case cityscape = "building.2.crop.circle.fill"
        
        // Food & Dining
        case restaurant = "fork.knife.circle.fill"
        case coffee = "cup.and.saucer.fill"
        case drinks = "wineglass.fill"
        case takeout = "takeoutbag.and.cup.and.straw.fill"
        
        // Shopping & Services
        case shopping = "bag.circle.fill"
        case gift = "gift.circle.fill"
        case cart = "cart.circle.fill"
        case store = "storefront.circle.fill"
        
        // Activities & Entertainment
        case music = "music.note.house.fill"
        case sports = "sportscourt.circle.fill"
        case games = "gamecontroller.fill"
        case movies = "tv.circle.fill"
        
        // General & Abstract
        case star = "star.circle.fill"
        case heart = "heart.circle.fill"
        case bookmark = "bookmark.circle.fill"
        case flag = "flag.circle.fill"
        
        var displayName: String {
            switch self {
            case .travel: return "Travel"
            case .beach: return "Beach"
            case .mountain: return "Mountain"
            case .cityscape: return "City"
            case .restaurant: return "Dining"
            case .coffee: return "Coffee"
            case .drinks: return "Drinks"
            case .takeout: return "Takeout"
            case .shopping: return "Shopping"
            case .gift: return "Gifts"
            case .cart: return "Cart"
            case .store: return "Store"
            case .music: return "Music"
            case .sports: return "Sports"
            case .games: return "Games"
            case .movies: return "Movies"
            case .star: return "Favorites"
            case .heart: return "Loved"
            case .bookmark: return "Saved"
            case .flag: return "Featured"
            }
        }
        
        var color: UIColor {
            switch self {
            case .travel, .beach, .mountain, .cityscape:
                return UIColor.systemBlue
            case .restaurant, .coffee, .drinks, .takeout:
                return UIColor.systemOrange
            case .shopping, .gift, .cart, .store:
                return UIColor.systemPurple
            case .music, .sports, .games, .movies:
                return UIColor.systemPink
            case .star, .heart, .bookmark, .flag:
                return UIColor.systemYellow
            }
        }
        
        func image(size: CGFloat = 100) -> UIImage? {
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
            return UIImage(systemName: self.rawValue, withConfiguration: config)
        }
    }
    
    // MARK: - Avatar Default Images
    enum AvatarDefault: String, CaseIterable {
        case person1 = "person.circle.fill"
        case person2 = "person.crop.circle.fill"
        case person3 = "person.crop.circle.badge.checkmark.fill"
        case person4 = "person.crop.circle.badge.fill"
        case people = "person.2.circle.fill"
        case smiley = "face.smiling.fill"
        case sunglasses = "face.smiling.inverse"
        case star = "star.circle.fill"
        
        var displayName: String {
            switch self {
            case .person1: return "Classic"
            case .person2: return "Simple"
            case .person3: return "Verified"
            case .person4: return "Badge"
            case .people: return "Social"
            case .smiley: return "Happy"
            case .sunglasses: return "Cool"
            case .star: return "Star"
            }
        }
        
        var backgroundColor: UIColor {
            switch self {
            case .person1, .person2:
                return UIColor.systemBlue
            case .person3, .person4:
                return UIColor.systemGreen
            case .people:
                return UIColor.systemPurple
            case .smiley, .sunglasses:
                return UIColor.systemOrange
            case .star:
                return UIColor.systemYellow
            }
        }
        
        func image(size: CGFloat = 80) -> UIImage? {
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
            return UIImage(systemName: self.rawValue, withConfiguration: config)
        }
    }
    
    // MARK: - Helper Methods
    static func randomCircleImage() -> CircleDefault {
        return CircleDefault.allCases.randomElement() ?? .star
    }
    
    static func randomAvatarImage() -> AvatarDefault {
        return AvatarDefault.allCases.randomElement() ?? .person1
    }
    
    static func circleImageForCategory(_ category: CircleCategory?) -> CircleDefault {
        guard let category = category else { return .star }
        
        switch category {
        case .travel:
            return .travel
        case .food:
            return .restaurant
        case .shopping:
            return .shopping
        case .entertainment:
            return .movies
        case .healthcare:
            return .heart
        case .services:
            return .star
        case .other:
            return .bookmark
        }
    }
}

// MARK: - Image Selection View
class DefaultImageSelectionView: UIView {
    
    enum SelectionType {
        case circle
        case avatar
    }
    
    // MARK: - Properties
    var onImageSelected: ((String) -> Void)?
    private let selectionType: SelectionType
    private let columns: Int = 4
    
    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(DefaultImageCell.self, forCellWithReuseIdentifier: "DefaultImageCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    // MARK: - Init
    init(type: SelectionType) {
        self.selectionType = type
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        clipsToBounds = true
        
        titleLabel.text = selectionType == .circle ? "Choose a default image" : "Choose an avatar"
        
        addSubview(titleLabel)
        addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }
}

// MARK: - UICollectionViewDataSource
extension DefaultImageSelectionView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch selectionType {
        case .circle:
            return DefaultImages.CircleDefault.allCases.count
        case .avatar:
            return DefaultImages.AvatarDefault.allCases.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "DefaultImageCell", for: indexPath) as! DefaultImageCell
        
        switch selectionType {
        case .circle:
            let imageCase = DefaultImages.CircleDefault.allCases[indexPath.item]
            cell.configure(with: imageCase.rawValue, color: imageCase.color, displayName: imageCase.displayName)
        case .avatar:
            let imageCase = DefaultImages.AvatarDefault.allCases[indexPath.item]
            cell.configure(with: imageCase.rawValue, color: imageCase.backgroundColor, displayName: imageCase.displayName)
        }
        
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension DefaultImageSelectionView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let spacing = 12.0 * CGFloat(columns - 1)
        let insets = 32.0 // left + right insets
        let availableWidth = collectionView.bounds.width - spacing - insets
        let itemWidth = availableWidth / CGFloat(columns)
        return CGSize(width: itemWidth, height: itemWidth + 20) // Extra height for label
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let symbolName: String
        
        switch selectionType {
        case .circle:
            symbolName = DefaultImages.CircleDefault.allCases[indexPath.item].rawValue
        case .avatar:
            symbolName = DefaultImages.AvatarDefault.allCases[indexPath.item].rawValue
        }
        
        onImageSelected?(symbolName)
    }
}

// MARK: - DefaultImageCell
class DefaultImageCell: UICollectionViewCell {
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        
        contentView.addSubview(imageView)
        contentView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4)
        ])
    }
    
    func configure(with symbolName: String, color: UIColor, displayName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        imageView.image = UIImage(systemName: symbolName, withConfiguration: config)
        imageView.tintColor = color
        nameLabel.text = displayName
    }
    
    override var isSelected: Bool {
        didSet {
            contentView.backgroundColor = isSelected ? Constants.Colors.primary.withAlphaComponent(0.2) : .secondarySystemBackground
        }
    }
}