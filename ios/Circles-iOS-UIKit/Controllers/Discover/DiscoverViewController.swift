import UIKit

class DiscoverViewController: UIViewController {
    
    // MARK: - Properties
    private var featuredCircles: [Circle] = []
    private var popularUsers: [User] = []
    private var trendingCategories: [CircleCategory] = []
    private var isLoading = false
    
    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = Constants.Colors.background
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search circles, places, or users"
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let featuredLabel: UILabel = {
        let label = UILabel()
        label.text = "Featured Circles"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let featuredCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = Constants.Spacing.medium
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: Constants.Spacing.medium, bottom: 0, right: Constants.Spacing.medium)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(FeaturedCircleCell.self, forCellWithReuseIdentifier: "FeaturedCircleCell")
        return collectionView
    }()
    
    private let usersLabel: UILabel = {
        let label = UILabel()
        label.text = "Popular Users"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let usersCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = Constants.Spacing.small
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: Constants.Spacing.medium, bottom: 0, right: Constants.Spacing.medium)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(UserCell.self, forCellWithReuseIdentifier: "UserCell")
        return collectionView
    }()
    
    private let categoriesLabel: UILabel = {
        let label = UILabel()
        label.text = "Browse Categories"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoriesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = Constants.Spacing.small
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: Constants.Spacing.medium, bottom: 0, right: Constants.Spacing.medium)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(CategoryCell.self, forCellWithReuseIdentifier: "CategoryCell")
        return collectionView
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionViews()
        fetchDiscoverData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Discover"
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(searchBar)
        contentView.addSubview(featuredLabel)
        contentView.addSubview(featuredCollectionView)
        contentView.addSubview(usersLabel)
        contentView.addSubview(usersCollectionView)
        contentView.addSubview(categoriesLabel)
        contentView.addSubview(categoriesCollectionView)
        contentView.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            searchBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            searchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.small),
            searchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.small),
            
            featuredLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Constants.Spacing.medium),
            featuredLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            featuredLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            featuredCollectionView.topAnchor.constraint(equalTo: featuredLabel.bottomAnchor, constant: Constants.Spacing.small),
            featuredCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            featuredCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            featuredCollectionView.heightAnchor.constraint(equalToConstant: 240),
            
            usersLabel.topAnchor.constraint(equalTo: featuredCollectionView.bottomAnchor, constant: Constants.Spacing.medium),
            usersLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            usersLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            usersCollectionView.topAnchor.constraint(equalTo: usersLabel.bottomAnchor, constant: Constants.Spacing.small),
            usersCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usersCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            usersCollectionView.heightAnchor.constraint(equalToConstant: 100),
            
            categoriesLabel.topAnchor.constraint(equalTo: usersCollectionView.bottomAnchor, constant: Constants.Spacing.medium),
            categoriesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            categoriesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            categoriesCollectionView.topAnchor.constraint(equalTo: categoriesLabel.bottomAnchor, constant: Constants.Spacing.small),
            categoriesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            categoriesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            categoriesCollectionView.heightAnchor.constraint(equalToConstant: 120),
            categoriesCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large),
            
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        // Set up search bar delegate
        searchBar.delegate = self
    }
    
    private func setupCollectionViews() {
        featuredCollectionView.delegate = self
        featuredCollectionView.dataSource = self
        
        usersCollectionView.delegate = self
        usersCollectionView.dataSource = self
        
        categoriesCollectionView.delegate = self
        categoriesCollectionView.dataSource = self
    }
    
    // MARK: - Data Loading
    private func fetchDiscoverData() {
        isLoading = true
        activityIndicator.startAnimating()
        
        // In a real app, these would be API calls
        // For demo purposes, we'll create sample data
        loadSampleData()
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
            self.activityIndicator.stopAnimating()
            
            self.featuredCollectionView.reloadData()
            self.usersCollectionView.reloadData()
            self.categoriesCollectionView.reloadData()
        }
    }
    
    private func loadSampleData() {
        // Sample featured circles
        let currentDate = Date()
        
        featuredCircles = [
            Circle(
                id: "featured1",
                name: "NYC Food Tour",
                description: "Best restaurants in New York City",
                coverImage: nil,
                owner: "user1",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place1", "place2", "place3", "place4"],
                placesCount: 4,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .food,
                location: "New York, NY",
                tags: ["food", "nyc", "restaurants"],
                sharedWith: nil,
                followers: ["user2", "user3", "user4"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 5),
                updatedAt: currentDate.addingTimeInterval(-3600)
            ),
            Circle(
                id: "featured2",
                name: "LA Shopping",
                description: "Top shopping spots in Los Angeles",
                coverImage: nil,
                owner: "user2",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place5", "place6", "place7"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .shopping,
                location: "Los Angeles, CA",
                tags: ["shopping", "la", "fashion"],
                sharedWith: nil,
                followers: ["user1", "user3", "user5"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 8),
                updatedAt: currentDate.addingTimeInterval(-7200)
            ),
            Circle(
                id: "featured3",
                name: "Chicago Entertainment",
                description: "Entertainment venues in Chicago",
                coverImage: nil,
                owner: "user3",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place8", "place9", "place10", "place11"],
                placesCount: 4,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .entertainment,
                location: "Chicago, IL",
                tags: ["entertainment", "chicago", "venues"],
                sharedWith: nil,
                followers: ["user2", "user4", "user6"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 12),
                updatedAt: currentDate.addingTimeInterval(-10800)
            ),
            Circle(
                id: "featured4",
                name: "Miami Beaches",
                description: "Best beaches and beach clubs in Miami",
                coverImage: nil,
                owner: "user4",
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: ["place12", "place13", "place14"],
                placesCount: 3,
                placesWithDetails: nil,
                privacy: .public,
                allowNetworkEdit: false,
                category: .travel,
                location: "Miami, FL",
                tags: ["travel", "miami", "beaches"],
                sharedWith: nil,
                followers: ["user1", "user5", "user7"],
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 15),
                updatedAt: currentDate.addingTimeInterval(-14400)
            )
        ]
        
        // Sample popular users
        popularUsers = [
            User(
                id: "user1",
                email: "john@example.com",
                displayName: "John Traveler",
                profilePicture: nil,
                bio: "Travel enthusiast and food lover",
                location: "New York, NY",
                friends: ["user2", "user3"],
                friendRequests: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 30)
            ),
            User(
                id: "user2",
                email: "emma@example.com",
                displayName: "Emma Foodie",
                profilePicture: nil,
                bio: "Food critic and restaurant finder",
                location: "Los Angeles, CA",
                friends: ["user1", "user4"],
                friendRequests: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 45)
            ),
            User(
                id: "user3",
                email: "alex@example.com",
                displayName: "Alex Explorer",
                profilePicture: nil,
                bio: "Urban explorer and architecture lover",
                location: "Chicago, IL",
                friends: ["user1", "user5"],
                friendRequests: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 60)
            ),
            User(
                id: "user4",
                email: "sarah@example.com",
                displayName: "Sarah Shopper",
                profilePicture: nil,
                bio: "Shopping enthusiast and style advisor",
                location: "Miami, FL",
                friends: ["user2", "user6"],
                friendRequests: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 75)
            ),
            User(
                id: "user5",
                email: "mike@example.com",
                displayName: "Mike Adventurer",
                profilePicture: nil,
                bio: "Adventure seeker and outdoor enthusiast",
                location: "Denver, CO",
                friends: ["user3", "user7"],
                friendRequests: nil,
                createdAt: currentDate.addingTimeInterval(-86400 * 90)
            )
        ]
        
        // Categories
        trendingCategories = [
            .food,
            .travel,
            .shopping,
            .entertainment,
            .services,
            .healthcare,
            .other
        ]
    }
}

// MARK: - UICollectionView DataSource & Delegate
extension DiscoverViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case featuredCollectionView:
            return featuredCircles.count
        case usersCollectionView:
            return popularUsers.count
        case categoriesCollectionView:
            return trendingCategories.count
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case featuredCollectionView:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FeaturedCircleCell", for: indexPath) as? FeaturedCircleCell else {
                return UICollectionViewCell()
            }
            let circle = featuredCircles[indexPath.item]
            cell.configure(with: circle)
            return cell
            
        case usersCollectionView:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UserCell", for: indexPath) as? UserCell else {
                return UICollectionViewCell()
            }
            let user = popularUsers[indexPath.item]
            cell.configure(with: user)
            return cell
            
        case categoriesCollectionView:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CategoryCell", for: indexPath) as? CategoryCell else {
                return UICollectionViewCell()
            }
            let category = trendingCategories[indexPath.item]
            cell.configure(with: category)
            return cell
            
        default:
            return UICollectionViewCell()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch collectionView {
        case featuredCollectionView:
            return CGSize(width: 280, height: 220)
        case usersCollectionView:
            return CGSize(width: 80, height: 90)
        case categoriesCollectionView:
            return CGSize(width: 100, height: 100)
        default:
            return CGSize.zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView {
        case featuredCollectionView:
            let circle = featuredCircles[indexPath.item]
            let detailVC = CircleDetailViewController(circle: circle)
            navigationController?.pushViewController(detailVC, animated: true)
            
        case usersCollectionView:
            let user = popularUsers[indexPath.item]
            // Navigate to user profile (in a real app)
            print("Selected user: \(user.displayName)")
            
        case categoriesCollectionView:
            let category = trendingCategories[indexPath.item]
            searchByCategory(category)
            
        default:
            break
        }
    }
    
    private func searchByCategory(_ category: CircleCategory) {
        // In a real app, this would filter by category
        print("Searching circles in category: \(category.rawValue)")
    }
}

// MARK: - UISearchBarDelegate
extension DiscoverViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchText = searchBar.text, !searchText.isEmpty else { return }
        searchBar.resignFirstResponder()
        
        // In a real app, this would perform a search
        print("Searching for: \(searchText)")
    }
}

// MARK: - FeaturedCircleCell
class FeaturedCircleCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addShadow(opacity: 0.1, radius: 5, offset: CGSize(width: 0, height: 2))
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.white
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        contentView.addSubview(containerView)
        
        containerView.addSubview(coverImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(descriptionLabel)
        containerView.addSubview(locationLabel)
        containerView.addSubview(placeCountLabel)
        containerView.addSubview(categoryLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            coverImageView.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.6),
            
            categoryLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            categoryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20),
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            nameLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: Constants.Spacing.small),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            locationLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            locationLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            
            placeCountLabel.centerYAnchor.constraint(equalTo: locationLabel.centerYAnchor),
            placeCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small)
        ])
    }
    
    // MARK: - Configure
    func configure(with circle: Circle) {
        nameLabel.text = circle.name
        descriptionLabel.text = circle.description
        locationLabel.text = circle.location
        
        if let places = circle.places {
            placeCountLabel.text = "\(places.count) place\(places.count != 1 ? "s" : "")"
        } else {
            placeCountLabel.text = "0 places"
        }
        
        // Category label
        categoryLabel.text = circle.category.rawValue.capitalized
        
        // Category color
        switch circle.category {
        case .travel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .food:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
        case .services:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .shopping:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        }
        
        // Cover image (would be loaded from URL in real app)
        if let _ = circle.coverImage {
            // Would load image from URL here
            coverImageView.image = UIImage(systemName: "photo")
        } else {
            // Default image based on category
            switch circle.category {
            case .travel:
                coverImageView.image = UIImage(systemName: "airplane.departure")
            case .food:
                coverImageView.image = UIImage(systemName: "fork.knife.circle.fill")
            case .services:
                coverImageView.image = UIImage(systemName: "wrench.and.screwdriver.fill")
            case .shopping:
                coverImageView.image = UIImage(systemName: "bag.fill")
            case .healthcare:
                coverImageView.image = UIImage(systemName: "heart.text.square.fill")
            case .entertainment:
                coverImageView.image = UIImage(systemName: "music.note.tv.fill")
            case .other:
                coverImageView.image = UIImage(systemName: "square.stack.3d.up.fill")
            }
            coverImageView.tintColor = Constants.Colors.primary
            coverImageView.contentMode = .center
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        descriptionLabel.text = nil
        locationLabel.text = nil
        placeCountLabel.text = nil
        coverImageView.image = nil
        categoryLabel.text = nil
    }
}

// MARK: - UserCell
class UserCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 30
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            profileImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 60),
            profileImageView.heightAnchor.constraint(equalToConstant: 60),
            
            nameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.tiny),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }
    
    // MARK: - Configure
    func configure(with user: User) {
        nameLabel.text = user.displayName
        
        // Profile image (would be loaded from URL in real app)
        if let _ = user.profilePicture {
            // Would load image from URL here
            profileImageView.image = UIImage(systemName: "person.fill")
        } else {
            profileImageView.image = Constants.Images.defaultProfileImage
        }
        profileImageView.tintColor = Constants.Colors.primary
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        profileImageView.image = nil
    }
}

// MARK: - CategoryCell
class CategoryCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addShadow(opacity: 0.1, radius: 3, offset: CGSize(width: 0, height: 1))
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        contentView.addSubview(containerView)
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.medium),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Constants.Spacing.small),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.tiny),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.tiny),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small)
        ])
    }
    
    // MARK: - Configure
    func configure(with category: CircleCategory) {
        nameLabel.text = category.rawValue.capitalized
        
        // Set icon and tint color based on category
        switch category {
        case .travel:
            iconImageView.image = UIImage(systemName: "airplane.departure")
            iconImageView.tintColor = UIColor(hex: "#3182CE") // Blue
        case .food:
            iconImageView.image = UIImage(systemName: "fork.knife.circle.fill")
            iconImageView.tintColor = UIColor(hex: "#E53E3E") // Red
        case .services:
            iconImageView.image = UIImage(systemName: "wrench.and.screwdriver.fill")
            iconImageView.tintColor = UIColor(hex: "#38A169") // Green
        case .shopping:
            iconImageView.image = UIImage(systemName: "bag.fill")
            iconImageView.tintColor = UIColor(hex: "#805AD5") // Purple
        case .healthcare:
            iconImageView.image = UIImage(systemName: "heart.text.square.fill")
            iconImageView.tintColor = UIColor(hex: "#DD6B20") // Orange
        case .entertainment:
            iconImageView.image = UIImage(systemName: "music.note.tv.fill")
            iconImageView.tintColor = UIColor(hex: "#D69E2E") // Yellow
        case .other:
            iconImageView.image = UIImage(systemName: "square.stack.3d.up.fill")
            iconImageView.tintColor = UIColor(hex: "#38A169") // Green
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        iconImageView.image = nil
    }
}