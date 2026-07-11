import UIKit
import MapKit
import CoreLocation

// MARK: - Response Types
struct UserCirclesResponse: Codable {
    let success: Bool
    let data: UserCirclesData
}

struct UserCirclesData: Codable {
    let user: User
    let circles: [Circle]
}

struct FollowResponse: Codable {
    let success: Bool
    let message: String
    let user: User?
}

// MARK: - FollowListType
enum FollowListType {
    case followers
    case following
}

// MARK: - StatView
class StatView: UIView {
    private let numberLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        addSubview(numberLabel)
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            numberLabel.topAnchor.constraint(equalTo: topAnchor),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(number: String, title: String) {
        numberLabel.text = number
        titleLabel.text = title
    }
}

class ProfileViewController: BaseViewController, PlaceSearchable, FullScreenMapViewControllerDelegate {
    
    // MARK: - Properties
    private var user: User?
    var circles: [Circle] = []
    private var displayItems: [CircleDisplayItem] = []
    private var circleGroups: [CircleGroup] = []
    private var isShowingMap = false
    var allPlaces: [Place] = []
    var filteredPlaces: [Place] = []
    private var selectedCategory: PlaceCategory?
    private var availableCategories: [UnifiedCategory] = []
    private var selectedCity: String?
    private var selectedConnectionId: String? // nil means "All Connections" (default)
    var isSearching = false
    var searchResultsHeightConstraint: NSLayoutConstraint?
    private var videos: [PlaceVideo] = []
    
    // MARK: - Drag & Drop Properties
    private var dragAndDropEnabled = false
    
    // Request deduplication
    private var isFetchingOtherUserCircles = false
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No circles found" }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var reloadsDataOnAppear: Bool { true }
    
    // MARK: - Helper Methods
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Public Methods
    func configureWith(user: User) {
        self.user = user
        // Don't call loadUserProfile here - let the view lifecycle handle it
        // This prevents duplicate API calls when reloadsDataOnAppear is true
    }
    
    func resetToListViewIfNeeded() {
        if isShowingMap {
            toggleViewMode()
        }
    }
    
    /// Force clear all profile picture caches and refresh the profile
    /// Call this when profile picture corruption is detected
    func forceRefreshProfileAndClearCache() {
        print("🚨 ProfileViewController: Force clearing all profile caches and refreshing")
        
        // Clear all image caches
        ImageService.shared.clearAllProfilePictureCaches()
        
        // Clear any cached profile picture URL
        if let profilePictureUrl = user?.profilePicture {
            ImageService.shared.clearCachedImage(for: profilePictureUrl)
        }
        
        // Reset the profile image view
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = Constants.Colors.primary
        
        // Force fetch fresh user data
        fetchFreshUserData { [weak self] in
            print("✅ ProfileViewController: Profile refreshed after cache clear")
            // Reload circles as well to ensure correct order
            self?.loadUserCircles()
        }
    }
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Profile Header Section
    private let profileHeaderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 45
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.separator.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // Username at top
    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Premium badge
    private let premiumBadgeView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        
        let crownIcon = UIImageView()
        crownIcon.image = UIImage(systemName: "crown.fill")
        crownIcon.tintColor = .white
        crownIcon.contentMode = .scaleAspectFit
        crownIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = "PREMIUM"
        label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(crownIcon)
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            crownIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            crownIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crownIcon.widthAnchor.constraint(equalToConstant: 12),
            crownIcon.heightAnchor.constraint(equalToConstant: 12),
            
            label.leadingAnchor.constraint(equalTo: crownIcon.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            
            view.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return view
    }()
    
    // Stats containers
    private let topStatsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let bottomStatsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Individual stat views
    private let circlesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let connectionsStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let followersStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let followingStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Bio section
    private let fullNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bioLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Location label to display home city
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure with location icon
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "location.fill")?.withTintColor(Constants.Colors.secondaryLabel, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(x: 0, y: -1, width: 12, height: 12)
        
        let attributedString = NSMutableAttributedString()
        attributedString.append(NSAttributedString(attachment: attachment))
        label.attributedText = attributedString
        
        return label
    }()
    
    // Buttons container
    private let buttonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var editProfileButton = UIButton.smallActionButton(title: "Edit profile", style: .secondary)
    
    private lazy var shareProfileButton = UIButton.smallActionButton(title: "Share profile", style: .secondary)
    
    private lazy var visitHistoryButton = UIButton.smallActionButton(title: "Visit History", style: .secondary)
    
    private lazy var suggestedButton: UIButton = {
        let button = UIButton.iconButton(systemName: "person.badge.plus")
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        return button
    }()
    
    // Buttons for viewing other users (connections)
    private lazy var messageButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Message", style: .primary)
        button.isHidden = true
        return button
    }()
    
    private lazy var followButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Follow", style: .secondary)
        button.isHidden = true
        return button
    }()
    
    private lazy var connectButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Connect", style: .primary)
        button.backgroundColor = Constants.Colors.secondary
        button.isHidden = true
        return button
    }()
    
    
    private lazy var logoutButton = UIButton.smallActionButton(title: "Log Out", style: .danger)
    
    private let versionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Notification Settings (for connected users)
    private let notificationsSectionContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let notificationsSectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Notifications"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notificationsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let notificationTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Activity Updates"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notificationDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Get notified when they add places, share moments, or create circles"
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var activityNotificationsToggle: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true // Default to enabled
        toggle.addTarget(self, action: #selector(activityNotificationsToggled), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    // Separator line
    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Content type segmented control
    private let contentTypeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Circles", "Moments", "Uploads"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    // Search bar container
    private let searchBarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Search bar
    let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search places..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    // Map toggle button (now next to search bar)
    private lazy var mapToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Map", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(toggleViewMode), for: .touchUpInside)
        return button
    }()
    
    // Search results table view
    let searchResultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Constants.Colors.background
        tableView.layer.cornerRadius = 8
        tableView.layer.shadowColor = UIColor.black.cgColor
        tableView.layer.shadowOffset = CGSize(width: 0, height: 2)
        tableView.layer.shadowOpacity = 0.1
        tableView.layer.shadowRadius = 4
        tableView.isHidden = true
        tableView.alpha = 0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        return tableView
    }()
    
    // Circles list section
    private let circlesHeaderView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circlesHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "" // No text for Instagram style
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    
    private let circlesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Constants.Colors.background
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.isScrollEnabled = false
        return collectionView
    }()
    
    private var circlesCollectionHeightConstraint: NSLayoutConstraint?
    
    // Videos collection view - Instagram-style 3-column grid
    private let videosCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets.zero
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.isPagingEnabled = false
        collectionView.showsVerticalScrollIndicator = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isScrollEnabled = true
        collectionView.isHidden = true
        return collectionView
    }()
    
    private var videosCollectionHeightConstraint: NSLayoutConstraint?
    
    private let videosEmptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No moments yet"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let videosLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private var isLoadingVideos = false
    
    // Uploads collection view - Instagram-style 3-column grid
    private let uploadsCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isHidden = true
        collectionView.showsVerticalScrollIndicator = false
        return collectionView
    }()
    
    private var uploads: [UserUploadedPhoto] = []
    private var uploadsCollectionHeightConstraint: NSLayoutConstraint?
    
    private let uploadsEmptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No uploads yet"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let uploadsLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private var isLoadingUploads = false
    private var logoutButtonTopToCollectionConstraint: NSLayoutConstraint?
    private var logoutButtonTopToMapConstraint: NSLayoutConstraint?
    private var logoutButtonTopToVideosConstraint: NSLayoutConstraint?
    private var logoutButtonTopToUploadsConstraint: NSLayoutConstraint?
    
    // Floating add button for creating circles
    private lazy var floatingAddButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(createCircleButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Map view elements
    private lazy var mapContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        return mapView
    }()
    
    private lazy var mapExpandButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.up.left.and.arrow.down.right")
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        return button
    }()
    
    private lazy var locationButton: UIButton = {
        let button = UIButton.iconButton(systemName: "location.circle.fill")
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: #selector(zoomToUserLocation), for: .touchUpInside)
        return button
    }()
    
    private lazy var filterContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 4
        return view
    }()
    
    // Overlay control chips for the map filter bar — same controls as the
    // home page map (hamburger menu, Me toggle, list/map toggle)
    private lazy var mapMenuChipButton: UIButton = {
        let button = UIButton.iconButton(systemName: "line.3.horizontal", pointSize: 15)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.buildProfileMapMenuElements() ?? [])
            }
        ])
        return button
    }()

    private lazy var mapMyPlacesChipButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.imagePlacement = .top
        config.imagePadding = 0
        config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
        config.image = UIImage(systemName: "person", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        var title = AttributedString("Me")
        title.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        config.attributedTitle = title
        config.baseForegroundColor = Constants.Colors.label

        let button = UIButton(configuration: config)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(mapMyPlacesChipTapped), for: .touchUpInside)
        return button
    }()

    private lazy var mapListChipButton: UIButton = {
        let button = UIButton.iconButton(systemName: "list.bullet", pointSize: 15)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.addTarget(self, action: #selector(mapListChipTapped), for: .touchUpInside)
        return button
    }()

    // Distance-sorted places list shown by the list/map toggle
    private lazy var mapPlacesListTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.secondaryBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = 72
        tableView.isHidden = true
        tableView.register(QuickAccessPlaceCell.self, forCellReuseIdentifier: "ProfilePlaceListCell")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private var isShowingMapPlacesList = false
    private var mapDistanceSortedPlaces: [(place: Place, distance: CLLocationDistance?)] = []
    private let mapListDistanceFormatter = MKDistanceFormatter()
    
    // State tracking for other users
    private var isFollowing: Bool = false
    private var connectionStatus: ConnectionStatus?
    
    // Constraint references for dynamic button positioning
    private var followButtonLeadingToMessageConstraint: NSLayoutConstraint?
    private var followButtonLeadingToConnectConstraint: NSLayoutConstraint?
    private var connectButtonLeadingConstraint: NSLayoutConstraint?
    
    // Dynamic constraints for search bar container positioning
    private var searchBarContainerTopToSegmentedConstraint: NSLayoutConstraint?
    private var searchBarContainerTopToSeparatorConstraint: NSLayoutConstraint?
    
    // Dynamic constraints for separator line positioning
    private var separatorLineTopToProfileConstraint: NSLayoutConstraint?
    private var separatorLineTopToNotificationConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    init(user: User? = nil) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        // Build the view hierarchy BEFORE super.viewDidLoad(): BaseViewController
        // kicks off loadData() -> loadUserProfile() -> displayUser() there, which
        // mutates header/collection constraints that only exist after setupUI().
        setupUI()
        super.viewDidLoad()
        setupActions()
        displayAppVersion()
        setupNotificationObservers()
        
        // Setup segmented control
        contentTypeSegmentedControl.addTarget(self, action: #selector(contentTypeChanged), for: .valueChanged)
        
        // Always start in list view
        isShowingMap = false
        circlesCollectionView.isHidden = false
        mapContainerView.isHidden = true
        mapToggleButton.setTitle("Map", for: .normal)
        
        // Clear any old saved view mode preference
        UserDefaults.standard.removeObject(forKey: "profileViewMode")
        
        // Register for SSE events
        SSEService.shared.addDelegate(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Check if we need to clear profile picture cache due to corruption
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        if isCurrentUser {
            // Clear profile picture cache if there's an issue
            if let profilePictureUrl = user?.profilePicture {
                // Check if the cached image might be incorrect
                // This is a temporary fix - clear cache if we suspect corruption
                let shouldClearCache = UserDefaults.standard.bool(forKey: "ProfilePictureCacheNeedsClearing")
                if shouldClearCache {
                    ImageService.shared.clearCachedImage(for: profilePictureUrl)
                    UserDefaults.standard.set(false, forKey: "ProfilePictureCacheNeedsClearing")
                    print("🔄 ProfileViewController: Cleared profile picture cache due to potential corruption")
                    
                    // Force refresh profile data
                    loadUserProfile()
                }
            }
        }
        
        // Always reset to list view when navigating to Profile tab
        if isShowingMap {
            isShowingMap = false
            
            // Update toggle button title
            mapToggleButton.setTitle("Map", for: .normal)
            
            // Show/hide views
            circlesCollectionView.isHidden = false
            mapContainerView.isHidden = true
            
            // Update constraints
            logoutButtonTopToCollectionConstraint?.isActive = true
            logoutButtonTopToMapConstraint?.isActive = false
            
            // Update scroll view layout
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Check if we should show the privacy settings tutorial step
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        if isCurrentUser && 
           OnboardingManager.shared.shouldShowTutorial && 
           OnboardingManager.shared.hasCompletedStep(.exploreNetwork) &&
           !OnboardingManager.shared.hasCompletedStep(.privacySettings) {
            // Show tutorial pointing to settings button
            if let settingsButton = navigationItem.rightBarButtonItems?.first(where: { $0.image == UIImage(systemName: "gear") }) {
                OnboardingManager.shared.showTutorialStep(
                    .privacySettings,
                    targetView: settingsButton.value(forKey: "view") as? UIView,
                    in: self,
                    arrowDirection: .top
                )
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        SSEService.shared.removeDelegate(self)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update colors when dark mode changes
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAppearance()
        }
    }
    
    private func updateAppearance() {
        // Update border colors that don't automatically adapt
        profileImageView.layer.borderColor = UIColor.separator.cgColor
        editProfileButton.layer.borderColor = UIColor.separator.cgColor
        shareProfileButton.layer.borderColor = UIColor.separator.cgColor
        visitHistoryButton.layer.borderColor = UIColor.separator.cgColor
        suggestedButton.layer.borderColor = UIColor.separator.cgColor
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update collection view height after layout is complete
        // This ensures the collection view has the correct width for calculations
        if !circles.isEmpty && contentTypeSegmentedControl.selectedSegmentIndex == 0 && !circlesCollectionView.isHidden {
            updateCollectionViewHeight()
        }
        
        if !videos.isEmpty && contentTypeSegmentedControl.selectedSegmentIndex == 1 && !videosCollectionView.isHidden {
            updateVideosCollectionHeight()
        }
    }
    
    // MARK: - BaseViewController Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        print("🚀 ProfileViewController: loadData called")
        print("🚀 ProfileViewController: isLoadingData = \(isLoadingData)")
        
        // Note: BaseViewController already manages isLoadingData, so we don't need to check it here
        // BaseViewController sets isLoadingData = true before calling this method
        
        // Call loadUserProfile with completion handler
        print("🚀 ProfileViewController: Calling loadUserProfile")
        loadUserProfile(completion: completion)
    }
    
    override func setupRefreshControl() {
        scrollView.refreshControl = refreshControl
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        setupNavigationBar(title: "Profile")
        
        // Add right bar button items
        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsButtonTapped))
        let videoButton = UIBarButtonItem(image: UIImage(systemName: "video.fill"), style: .plain, target: self, action: #selector(videoButtonTapped))
        let checkInButton = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"), style: .plain, target: self, action: #selector(checkInButtonTapped))
        let rewardsButton = UIBarButtonItem(image: UIImage(systemName: "star.circle"), style: .plain, target: self, action: #selector(rewardsButtonTapped))
        navigationItem.rightBarButtonItems = [settingsButton, videoButton, checkInButton, rewardsButton]
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileHeaderView)
        profileHeaderView.addSubview(usernameLabel)
        profileHeaderView.addSubview(premiumBadgeView)
        profileHeaderView.addSubview(profileImageView)
        profileHeaderView.addSubview(topStatsContainer)
        profileHeaderView.addSubview(bottomStatsContainer)
        topStatsContainer.addSubview(circlesStatView)
        topStatsContainer.addSubview(placesStatView)
        topStatsContainer.addSubview(connectionsStatView)
        bottomStatsContainer.addSubview(followersStatView)
        bottomStatsContainer.addSubview(followingStatView)
        profileHeaderView.addSubview(locationLabel)
        profileHeaderView.addSubview(bioLabel)
        profileHeaderView.addSubview(buttonsContainer)
        buttonsContainer.addSubview(editProfileButton)
        buttonsContainer.addSubview(shareProfileButton)
        buttonsContainer.addSubview(visitHistoryButton)
        buttonsContainer.addSubview(suggestedButton)
        buttonsContainer.addSubview(messageButton)
        buttonsContainer.addSubview(followButton)
        buttonsContainer.addSubview(connectButton)
        
        // Add notification settings section
        contentView.addSubview(notificationsSectionContainer)
        notificationsSectionContainer.addSubview(notificationsSectionLabel)
        notificationsSectionContainer.addSubview(notificationsContainer)
        notificationsContainer.addSubview(notificationTitleLabel)
        notificationsContainer.addSubview(notificationDescriptionLabel)
        notificationsContainer.addSubview(activityNotificationsToggle)
        
        contentView.addSubview(separatorLine)
        contentView.addSubview(contentTypeSegmentedControl)
        contentView.addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchBar)
        searchBarContainer.addSubview(mapToggleButton)
        contentView.addSubview(circlesHeaderView)
        circlesHeaderView.addSubview(circlesHeaderLabel)
        contentView.addSubview(circlesCollectionView)
        contentView.addSubview(videosCollectionView)
        contentView.addSubview(videosEmptyLabel)
        contentView.addSubview(videosLoadingIndicator)
        contentView.addSubview(uploadsCollectionView)
        contentView.addSubview(uploadsEmptyLabel)
        contentView.addSubview(uploadsLoadingIndicator)
        
        // Add map container (initially hidden)
        contentView.addSubview(mapContainerView)
        mapContainerView.addSubview(filterContainerView)
        filterContainerView.addSubview(mapMenuChipButton)
        filterContainerView.addSubview(mapMyPlacesChipButton)
        filterContainerView.addSubview(mapListChipButton)
        mapContainerView.addSubview(mapView)
        mapContainerView.addSubview(mapPlacesListTableView)
        mapContainerView.addSubview(mapExpandButton)
        mapContainerView.addSubview(locationButton)
        
        contentView.addSubview(logoutButton)
        contentView.addSubview(versionLabel)
        
        // Add floating add button last so it's on top
        view.addSubview(floatingAddButton)
        
        // Add search results table view on top of everything
        view.addSubview(searchResultsTableView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Profile header view
            profileHeaderView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.medium),
            profileHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            profileHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Username at top
            usernameLabel.topAnchor.constraint(equalTo: profileHeaderView.topAnchor, constant: Constants.Spacing.medium),
            usernameLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            
            // Premium badge
            premiumBadgeView.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),
            premiumBadgeView.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            
            // Profile image view (Instagram style - smaller, on the left)
            profileImageView.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            profileImageView.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            profileImageView.widthAnchor.constraint(equalToConstant: 90),
            profileImageView.heightAnchor.constraint(equalToConstant: 90),
            
            // Top stats container (to the right of profile image)
            topStatsContainer.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            topStatsContainer.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: Constants.Spacing.large),
            topStatsContainer.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            topStatsContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Bottom stats container (below top stats)
            bottomStatsContainer.topAnchor.constraint(equalTo: topStatsContainer.bottomAnchor, constant: Constants.Spacing.small),
            bottomStatsContainer.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: Constants.Spacing.large),
            bottomStatsContainer.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            bottomStatsContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Top row stats (3 items)
            circlesStatView.leadingAnchor.constraint(equalTo: topStatsContainer.leadingAnchor),
            circlesStatView.topAnchor.constraint(equalTo: topStatsContainer.topAnchor),
            circlesStatView.bottomAnchor.constraint(equalTo: topStatsContainer.bottomAnchor),
            circlesStatView.widthAnchor.constraint(equalTo: topStatsContainer.widthAnchor, multiplier: 0.33),
            
            placesStatView.centerXAnchor.constraint(equalTo: topStatsContainer.centerXAnchor),
            placesStatView.topAnchor.constraint(equalTo: topStatsContainer.topAnchor),
            placesStatView.bottomAnchor.constraint(equalTo: topStatsContainer.bottomAnchor),
            placesStatView.widthAnchor.constraint(equalTo: topStatsContainer.widthAnchor, multiplier: 0.33),
            
            connectionsStatView.trailingAnchor.constraint(equalTo: topStatsContainer.trailingAnchor),
            connectionsStatView.topAnchor.constraint(equalTo: topStatsContainer.topAnchor),
            connectionsStatView.bottomAnchor.constraint(equalTo: topStatsContainer.bottomAnchor),
            connectionsStatView.widthAnchor.constraint(equalTo: topStatsContainer.widthAnchor, multiplier: 0.33),
            
            // Bottom row stats (2 items centered)
            followersStatView.leadingAnchor.constraint(equalTo: bottomStatsContainer.leadingAnchor, constant: 20),
            followersStatView.topAnchor.constraint(equalTo: bottomStatsContainer.topAnchor),
            followersStatView.bottomAnchor.constraint(equalTo: bottomStatsContainer.bottomAnchor),
            followersStatView.widthAnchor.constraint(equalTo: bottomStatsContainer.widthAnchor, multiplier: 0.4),
            
            followingStatView.trailingAnchor.constraint(equalTo: bottomStatsContainer.trailingAnchor, constant: -20),
            followingStatView.topAnchor.constraint(equalTo: bottomStatsContainer.topAnchor),
            followingStatView.bottomAnchor.constraint(equalTo: bottomStatsContainer.bottomAnchor),
            followingStatView.widthAnchor.constraint(equalTo: bottomStatsContainer.widthAnchor, multiplier: 0.4),
            
            // Location label
            locationLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.small),
            locationLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            locationLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: Constants.Spacing.small),
            bioLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            bioLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Buttons container
            buttonsContainer.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: Constants.Spacing.medium),
            buttonsContainer.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            buttonsContainer.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            buttonsContainer.heightAnchor.constraint(equalToConstant: 30),
            buttonsContainer.bottomAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            // Edit profile button
            editProfileButton.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor),
            editProfileButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            editProfileButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            editProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.29),
            
            // Share profile button
            shareProfileButton.leadingAnchor.constraint(equalTo: editProfileButton.trailingAnchor, constant: 6),
            shareProfileButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            shareProfileButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            shareProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.29),
            
            // Visit History button
            visitHistoryButton.leadingAnchor.constraint(equalTo: shareProfileButton.trailingAnchor, constant: 6),
            visitHistoryButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            visitHistoryButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            visitHistoryButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.29),
            
            // Suggested button
            suggestedButton.trailingAnchor.constraint(equalTo: buttonsContainer.trailingAnchor),
            suggestedButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            suggestedButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            suggestedButton.widthAnchor.constraint(equalToConstant: 30),
            
            // Message button (for other users)
            messageButton.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor),
            messageButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            messageButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            messageButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.48),
            
            // Follow button (for other users) - fixed constraints
            followButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            followButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            followButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.48),
            
            // Connect button (for other users) - fixed constraints
            connectButton.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor),
            connectButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            connectButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            connectButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.48),
            
            // Notification settings section
            notificationsSectionContainer.topAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: Constants.Spacing.medium),
            notificationsSectionContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            notificationsSectionContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            notificationsSectionLabel.topAnchor.constraint(equalTo: notificationsSectionContainer.topAnchor),
            notificationsSectionLabel.leadingAnchor.constraint(equalTo: notificationsSectionContainer.leadingAnchor),
            notificationsSectionLabel.trailingAnchor.constraint(equalTo: notificationsSectionContainer.trailingAnchor),
            
            notificationsContainer.topAnchor.constraint(equalTo: notificationsSectionLabel.bottomAnchor, constant: 8),
            notificationsContainer.leadingAnchor.constraint(equalTo: notificationsSectionContainer.leadingAnchor),
            notificationsContainer.trailingAnchor.constraint(equalTo: notificationsSectionContainer.trailingAnchor),
            notificationsContainer.bottomAnchor.constraint(equalTo: notificationsSectionContainer.bottomAnchor),
            
            // Constraints inside notifications container
            notificationTitleLabel.topAnchor.constraint(equalTo: notificationsContainer.topAnchor, constant: 16),
            notificationTitleLabel.leadingAnchor.constraint(equalTo: notificationsContainer.leadingAnchor, constant: 16),
            notificationTitleLabel.trailingAnchor.constraint(equalTo: activityNotificationsToggle.leadingAnchor, constant: -16),
            
            activityNotificationsToggle.centerYAnchor.constraint(equalTo: notificationTitleLabel.centerYAnchor),
            activityNotificationsToggle.trailingAnchor.constraint(equalTo: notificationsContainer.trailingAnchor, constant: -16),
            
            notificationDescriptionLabel.topAnchor.constraint(equalTo: notificationTitleLabel.bottomAnchor, constant: 4),
            notificationDescriptionLabel.leadingAnchor.constraint(equalTo: notificationsContainer.leadingAnchor, constant: 16),
            notificationDescriptionLabel.trailingAnchor.constraint(equalTo: activityNotificationsToggle.leadingAnchor, constant: -16),
            notificationDescriptionLabel.bottomAnchor.constraint(equalTo: notificationsContainer.bottomAnchor, constant: -16),
            
            // Separator line (fixed constraints)
            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),
            
            // Content type segmented control
            contentTypeSegmentedControl.topAnchor.constraint(equalTo: separatorLine.bottomAnchor, constant: Constants.Spacing.medium),
            contentTypeSegmentedControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentTypeSegmentedControl.widthAnchor.constraint(equalToConstant: 200),
            contentTypeSegmentedControl.heightAnchor.constraint(equalToConstant: 32),
            
            // Search bar container (top constraint will be set dynamically)
            searchBarContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            searchBarContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 44),
            
            // Search bar
            searchBar.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),
            searchBar.trailingAnchor.constraint(equalTo: mapToggleButton.leadingAnchor, constant: -8),
            
            // Map toggle button
            mapToggleButton.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            mapToggleButton.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor),
            mapToggleButton.widthAnchor.constraint(equalToConstant: 60),
            mapToggleButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Circles header
            circlesHeaderView.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: Constants.Spacing.small),
            circlesHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            circlesHeaderView.heightAnchor.constraint(equalToConstant: 0), // Hide header for Instagram style
            
            circlesHeaderLabel.centerYAnchor.constraint(equalTo: circlesHeaderView.centerYAnchor),
            circlesHeaderLabel.leadingAnchor.constraint(equalTo: circlesHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            
            
            // Circles collection view
            circlesCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Videos collection view
            videosCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            videosCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videosCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Videos empty label
            videosEmptyLabel.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor, constant: 100),
            videosEmptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videosEmptyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            videosEmptyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Uploads collection view
            uploadsCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            uploadsCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            uploadsCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Uploads empty label
            uploadsEmptyLabel.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor, constant: 100),
            uploadsEmptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            uploadsEmptyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            uploadsEmptyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Videos loading indicator
            videosLoadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videosLoadingIndicator.centerYAnchor.constraint(equalTo: videosEmptyLabel.centerYAnchor),
            
            // Uploads loading indicator
            uploadsLoadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            uploadsLoadingIndicator.centerYAnchor.constraint(equalTo: uploadsEmptyLabel.centerYAnchor),
            
            // Map container (same position as circles collection)
            mapContainerView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            mapContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mapContainerView.heightAnchor.constraint(equalToConstant: 400),
            
            // Filter container
            filterContainerView.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
            filterContainerView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            filterContainerView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            filterContainerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Overlay control chips (hamburger, Me, list — same as home map)
            mapMenuChipButton.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            mapMenuChipButton.centerYAnchor.constraint(equalTo: filterContainerView.centerYAnchor),
            mapMenuChipButton.widthAnchor.constraint(equalToConstant: 36),
            mapMenuChipButton.heightAnchor.constraint(equalToConstant: 36),

            mapMyPlacesChipButton.leadingAnchor.constraint(equalTo: mapMenuChipButton.trailingAnchor, constant: 8),
            mapMyPlacesChipButton.centerYAnchor.constraint(equalTo: filterContainerView.centerYAnchor),
            mapMyPlacesChipButton.widthAnchor.constraint(equalToConstant: 36),
            mapMyPlacesChipButton.heightAnchor.constraint(equalToConstant: 36),

            mapListChipButton.leadingAnchor.constraint(equalTo: mapMyPlacesChipButton.trailingAnchor, constant: 8),
            mapListChipButton.centerYAnchor.constraint(equalTo: filterContainerView.centerYAnchor),
            mapListChipButton.widthAnchor.constraint(equalToConstant: 36),
            mapListChipButton.heightAnchor.constraint(equalToConstant: 36),

            // Map view
            mapView.topAnchor.constraint(equalTo: filterContainerView.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor),

            // Distance-sorted places list overlays the map area
            mapPlacesListTableView.topAnchor.constraint(equalTo: mapView.topAnchor),
            mapPlacesListTableView.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            mapPlacesListTableView.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
            mapPlacesListTableView.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
            
            // Map expand button
            mapExpandButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 8),
            mapExpandButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8),
            mapExpandButton.widthAnchor.constraint(equalToConstant: 36),
            mapExpandButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Location button (below expand button)
            locationButton.topAnchor.constraint(equalTo: mapExpandButton.bottomAnchor, constant: 8),
            locationButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8),
            locationButton.widthAnchor.constraint(equalToConstant: 36),
            locationButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Logout button (position constraints)
            logoutButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoutButton.widthAnchor.constraint(equalToConstant: 100),
            logoutButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Version label
            versionLabel.topAnchor.constraint(equalTo: logoutButton.bottomAnchor, constant: Constants.Spacing.medium),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            versionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large),
            
            // Floating add button
            floatingAddButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            floatingAddButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            floatingAddButton.widthAnchor.constraint(equalToConstant: 56),
            floatingAddButton.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        // Create height constraints for collection views
        circlesCollectionHeightConstraint = circlesCollectionView.heightAnchor.constraint(equalToConstant: 400)
        circlesCollectionHeightConstraint?.isActive = true
        
        videosCollectionHeightConstraint = videosCollectionView.heightAnchor.constraint(equalToConstant: 200)
        videosCollectionHeightConstraint?.isActive = true
        
        uploadsCollectionHeightConstraint = uploadsCollectionView.heightAnchor.constraint(equalToConstant: 200)
        uploadsCollectionHeightConstraint?.isActive = true
        
        // Create switchable constraints for logout button
        logoutButtonTopToCollectionConstraint = logoutButton.topAnchor.constraint(equalTo: circlesCollectionView.bottomAnchor, constant: Constants.Spacing.xlarge)
        logoutButtonTopToMapConstraint = logoutButton.topAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: Constants.Spacing.xlarge)
        logoutButtonTopToVideosConstraint = logoutButton.topAnchor.constraint(equalTo: videosCollectionView.bottomAnchor, constant: Constants.Spacing.xlarge)
        logoutButtonTopToUploadsConstraint = logoutButton.topAnchor.constraint(equalTo: uploadsCollectionView.bottomAnchor, constant: Constants.Spacing.xlarge)
        
        // Initially show collection view
        logoutButtonTopToCollectionConstraint?.isActive = true
        logoutButtonTopToMapConstraint?.isActive = false
        logoutButtonTopToVideosConstraint?.isActive = false
        
        // Create dynamic constraints for search bar container
        searchBarContainerTopToSegmentedConstraint = searchBarContainer.topAnchor.constraint(
            equalTo: contentTypeSegmentedControl.bottomAnchor, 
            constant: Constants.Spacing.medium
        )
        searchBarContainerTopToSeparatorConstraint = searchBarContainer.topAnchor.constraint(
            equalTo: separatorLine.bottomAnchor, 
            constant: Constants.Spacing.medium
        )
        
        // Create dynamic constraints for separator line positioning
        separatorLineTopToProfileConstraint = separatorLine.topAnchor.constraint(
            equalTo: profileHeaderView.bottomAnchor, 
            constant: Constants.Spacing.medium
        )
        separatorLineTopToNotificationConstraint = separatorLine.topAnchor.constraint(
            equalTo: notificationsSectionContainer.bottomAnchor, 
            constant: Constants.Spacing.medium
        )
        
        // Initially activate based on whether viewing current user
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        if isCurrentUser {
            // Current user - search bar anchored to segmented control, separator to profile
            searchBarContainerTopToSegmentedConstraint?.isActive = true
            searchBarContainerTopToSeparatorConstraint?.isActive = false
            separatorLineTopToProfileConstraint?.isActive = true
            separatorLineTopToNotificationConstraint?.isActive = false
            // Show floating add button for current user
            floatingAddButton.isHidden = false
        } else {
            // Connection profile - search bar anchored to separator, separator to notification section
            searchBarContainerTopToSegmentedConstraint?.isActive = false
            searchBarContainerTopToSeparatorConstraint?.isActive = true
            separatorLineTopToProfileConstraint?.isActive = false
            separatorLineTopToNotificationConstraint?.isActive = true
            // Hide floating add button for other users
            floatingAddButton.isHidden = true
        }
        
        // Map filter menus are built on demand by the hamburger chip

        // Setup collection views
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        
        // Drag and drop disabled for now
        
        videosCollectionView.delegate = self
        videosCollectionView.dataSource = self
        videosCollectionView.register(VideoThumbnailCell.self, forCellWithReuseIdentifier: "VideoThumbnailCell")
        
        uploadsCollectionView.delegate = self
        uploadsCollectionView.dataSource = self
        uploadsCollectionView.register(UploadThumbnailCell.self, forCellWithReuseIdentifier: "UploadThumbnailCell")
        
        // Configure videos collection view layout for 3-column grid
        if let flowLayout = videosCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.scrollDirection = .vertical
            flowLayout.minimumInteritemSpacing = 2
            flowLayout.minimumLineSpacing = 2
            flowLayout.sectionInset = .zero
        }
        
        // Configure uploads collection view layout for 3-column grid
        if let flowLayout = uploadsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.scrollDirection = .vertical
            flowLayout.minimumInteritemSpacing = 2
            flowLayout.minimumLineSpacing = 2
            flowLayout.sectionInset = .zero
        }
        
        // Drag and drop will be configured conditionally in configureDragAndDrop()
        
        // Setup search bar
        searchBar.delegate = self
        
        // Setup search results table view
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.delaysContentTouches = false
        searchResultsTableView.canCancelContentTouches = true
        
        // Search results table view constraints
        NSLayoutConstraint.activate([
            searchResultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            searchResultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            searchResultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        searchResultsHeightConstraint = searchResultsTableView.heightAnchor.constraint(equalToConstant: 0)
        searchResultsHeightConstraint?.isActive = true
        
        // Setup dynamic button constraints
        setupDynamicButtonConstraints()
    }
    
    private func setupDynamicButtonConstraints() {
        // Create the alternative leading constraints for follow button
        followButtonLeadingToMessageConstraint = followButton.leadingAnchor.constraint(equalTo: messageButton.trailingAnchor, constant: 6)
        followButtonLeadingToConnectConstraint = followButton.leadingAnchor.constraint(equalTo: connectButton.trailingAnchor, constant: 6)
        
        // Initially activate the constraint to message button
        followButtonLeadingToMessageConstraint?.isActive = true
    }
    
    private func setupActions() {
        editProfileButton.addTarget(self, action: #selector(editProfileButtonTapped), for: .touchUpInside)
        shareProfileButton.addTarget(self, action: #selector(shareProfileButtonTapped), for: .touchUpInside)
        visitHistoryButton.addTarget(self, action: #selector(visitHistoryButtonTapped), for: .touchUpInside)
        suggestedButton.addTarget(self, action: #selector(suggestedButtonTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        mapExpandButton.addTarget(self, action: #selector(expandMapButtonTapped), for: .touchUpInside)
        
        // Connection-related buttons for viewing other users
        messageButton.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        connectButton.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        
        // Add tap gestures for followers/following stats (owner only)
        let followersTapGesture = UITapGestureRecognizer(target: self, action: #selector(followersStatTapped))
        followersStatView.addGestureRecognizer(followersTapGesture)
        followersStatView.isUserInteractionEnabled = true
        
        let followingTapGesture = UITapGestureRecognizer(target: self, action: #selector(followingStatTapped))
        followingStatView.addGestureRecognizer(followingTapGesture)
        followingStatView.isUserInteractionEnabled = true
        
        // Add tap gesture for profile image to view full-screen
        let profileImageTapGesture = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.addGestureRecognizer(profileImageTapGesture)
        profileImageView.isUserInteractionEnabled = true
        
        // Add tap gesture to dismiss keyboard when tapping outside search bar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        // Apply initial appearance
        updateAppearance()
    }
    
    private func configureDragAndDrop() {
        // Only enable drag and drop for the current user's own profile
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        dragAndDropEnabled = isCurrentUser // Enable for current user
        
        if dragAndDropEnabled {
            // Set up drag and drop delegates
            circlesCollectionView.dragDelegate = self
            circlesCollectionView.dropDelegate = self
            circlesCollectionView.dragInteractionEnabled = true
            
            // Enable reordering
            circlesCollectionView.reorderingCadence = .immediate
        } else {
            // Disable drag and drop for other users' profiles
            circlesCollectionView.dragDelegate = nil
            circlesCollectionView.dropDelegate = nil
            circlesCollectionView.dragInteractionEnabled = false
        }
    }
    
    // MARK: - Actions
    @objc private func editProfileButtonTapped() {
        let editProfileVC = EditProfileViewController()
        navigationController?.pushViewController(editProfileVC, animated: true)
    }
    
    @objc private func shareProfileButtonTapped() {
        guard let user = user else { return }
        
        let shareProfileVC = ShareProfileViewController(user: user)
        shareProfileVC.modalPresentationStyle = .overFullScreen
        shareProfileVC.modalTransitionStyle = .crossDissolve
        present(shareProfileVC, animated: true)
    }
    
    @objc private func visitHistoryButtonTapped() {
        let visitHistoryVC = VisitHistoryViewController()
        navigationController?.pushViewController(visitHistoryVC, animated: true)
    }
    
    @objc private func suggestedButtonTapped() {
        shareConnectionInvite()
    }
    
    private func shareConnectionInvite() {
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = suggestedButton
            popover.sourceRect = suggestedButton.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func logoutButtonTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.logout()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func settingsButtonTapped() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }

    @objc private func rewardsButtonTapped() {
        let rewardsVC = RewardsViewController()
        navigationController?.pushViewController(rewardsVC, animated: true)
    }
    
    @objc private func videoButtonTapped() {
        let contentUploadVC = ContentUploadViewController()
        contentUploadVC.delegate = self
        let navController = UINavigationController(rootViewController: contentUploadVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func checkInButtonTapped() {
        let checkInVC = CheckInViewController()
        let navController = UINavigationController(rootViewController: checkInVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func contentTypeChanged() {
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        
        if contentTypeSegmentedControl.selectedSegmentIndex == 0 {
            // Show circles
            circlesCollectionView.isHidden = isShowingMap
            videosCollectionView.isHidden = true
            videosEmptyLabel.isHidden = true
            searchBar.placeholder = "Search places..."
            mapToggleButton.isHidden = false
            
            // Show floating add button for current user on Circles tab
            floatingAddButton.isHidden = !isCurrentUser
            
            // Ensure map container visibility matches current state
            mapContainerView.isHidden = !isShowingMap
            
            // Update circles collection height
            updateCollectionViewHeight()
            
            // Update logout button constraint
            logoutButtonTopToCollectionConstraint?.isActive = !isShowingMap
            logoutButtonTopToMapConstraint?.isActive = isShowingMap
            logoutButtonTopToVideosConstraint?.isActive = false
            
            // Force layout update
            view.setNeedsLayout()
            view.layoutIfNeeded()
            
            // Reload collection view to ensure proper display
            circlesCollectionView.reloadData()
            
            // Ensure scroll view adjusts to content
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            
            // Recalculate height after reload
            DispatchQueue.main.async { [weak self] in
                self?.updateCollectionViewHeight()
            }
        } else if contentTypeSegmentedControl.selectedSegmentIndex == 1 {
            // Show videos/moments
            print("📹 Switching to Moments tab")
            
            // TEMPORARY: Clear image cache to debug duplicate thumbnails
            ImageService.shared.clearAllCaches()
            print("🧹 Cleared all image caches for debugging")
            
            circlesCollectionView.isHidden = true
            videosCollectionView.isHidden = false
            uploadsCollectionView.isHidden = true
            uploadsEmptyLabel.isHidden = true
            mapContainerView.isHidden = true
            searchBar.placeholder = "Search videos..."
            mapToggleButton.isHidden = true
            
            // Hide floating add button on Moments tab
            floatingAddButton.isHidden = true
            
            // Check cache first before fetching
            if videos.isEmpty && !isLoadingVideos {
                // Show loading state
                videosEmptyLabel.isHidden = true
                videosLoadingIndicator.startAnimating()
                
                // Try to load from cache first
                loadCachedVideos()
                
                // Fetch from network
                fetchUserVideos()
            } else if !videos.isEmpty {
                // Update UI if we have videos
                videosCollectionView.reloadData()
                updateVideosCollectionHeight()
                videosEmptyLabel.isHidden = true
                videosLoadingIndicator.stopAnimating()
            }
            
            // Update logout button constraint to videos collection
            logoutButtonTopToCollectionConstraint?.isActive = false
            logoutButtonTopToMapConstraint?.isActive = false
            logoutButtonTopToVideosConstraint?.isActive = true
            logoutButtonTopToUploadsConstraint?.isActive = false
        } else {
            // Show uploads (tab index 2)
            print("📷 Switching to Uploads tab")
            
            circlesCollectionView.isHidden = true
            videosCollectionView.isHidden = true
            videosEmptyLabel.isHidden = true
            uploadsCollectionView.isHidden = false
            mapContainerView.isHidden = true
            searchBar.placeholder = "Search uploads..."
            mapToggleButton.isHidden = true
            
            // Hide floating add button on Uploads tab
            floatingAddButton.isHidden = true
            
            // Check if we need to fetch uploads
            if uploads.isEmpty && !isLoadingUploads {
                // Show loading state
                uploadsEmptyLabel.isHidden = true
                uploadsLoadingIndicator.startAnimating()
                
                // Fetch uploads from network
                fetchUserUploads()
            } else if !uploads.isEmpty {
                // Update UI if we have uploads
                uploadsCollectionView.reloadData()
                updateUploadsCollectionHeight()
                uploadsEmptyLabel.isHidden = true
                uploadsLoadingIndicator.stopAnimating()
            }
            
            // Update logout button constraint to uploads collection
            logoutButtonTopToCollectionConstraint?.isActive = false
            logoutButtonTopToMapConstraint?.isActive = false
            logoutButtonTopToVideosConstraint?.isActive = false
            logoutButtonTopToUploadsConstraint?.isActive = true
        }
    }
    
    @objc private func toggleViewMode() {
        isShowingMap.toggle()
        
        // Update toggle button title
        mapToggleButton.setTitle(isShowingMap ? "List" : "Map", for: .normal)
        
        // Show/hide views
        circlesCollectionView.isHidden = isShowingMap
        mapContainerView.isHidden = !isShowingMap
        
        // Update constraints
        if isShowingMap {
            logoutButtonTopToCollectionConstraint?.isActive = false
            logoutButtonTopToMapConstraint?.isActive = true
            
            // Load places for map if not already loaded
            if allPlaces.isEmpty {
                loadAllPlaces()
            } else {
                // Places already loaded, just filter and update map
                filterPlaces()
            }
        } else {
            logoutButtonTopToMapConstraint?.isActive = false
            logoutButtonTopToCollectionConstraint?.isActive = true
        }
        
        // Update scroll view layout
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
        
        // Note: We don't save view mode preference - always default to list view
    }
    
    /// Builds the hamburger chip's menu: Connections, Category and City
    /// submenus — the same structure as the home page map's menu, with the
    /// profile-specific City filter added. Rebuilt fresh on every open.
    private func buildProfileMapMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        // Connections submenu
        let connectionActions: [UIAction] = [
            UIAction(title: "All Connections", state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                self?.selectedConnectionId = nil
                self?.updateMapMyPlacesChipAppearance()
                self?.filterPlaces()
            },
            UIAction(title: "My Places Only", state: selectedConnectionId == "my_places_only" ? .on : .off) { [weak self] _ in
                self?.selectedConnectionId = "my_places_only"
                self?.updateMapMyPlacesChipAppearance()
                self?.filterPlaces()
            }
        ]
        elements.append(UIMenu(
            title: "Connections",
            subtitle: selectedConnectionId == "my_places_only" ? "My Places Only" : "All Connections",
            image: UIImage(systemName: "person.2"),
            children: connectionActions
        ))

        // Category submenu
        var categoryActions: [UIAction] = [
            UIAction(title: "All Categories", state: selectedCategory == nil ? .on : .off) { [weak self] _ in
                self?.selectedCategory = nil
                self?.filterPlaces()
            }
        ]
        for category in availableCategories {
            // For now, only standard categories are filterable here
            guard case .standard(let placeCategory) = category else { continue }
            categoryActions.append(
                UIAction(title: category.displayName, state: selectedCategory == placeCategory ? .on : .off) { [weak self] _ in
                    self?.selectedCategory = placeCategory
                    self?.filterPlaces()
                }
            )
        }
        elements.append(UIMenu(
            title: "Category",
            subtitle: selectedCategory.map { UnifiedCategory.standard($0).displayName } ?? "All Categories",
            image: UIImage(systemName: "square.grid.2x2"),
            children: categoryActions
        ))

        // City submenu (profile-specific)
        var cityPlaceCount: [String: Int] = [:]
        for place in allPlaces {
            if let city = extractCityFromAddress(place.address) {
                cityPlaceCount[city, default: 0] += 1
            }
        }
        var cityActions: [UIAction] = [
            UIAction(title: "All Cities", state: selectedCity == nil ? .on : .off) { [weak self] _ in
                self?.selectedCity = nil
                self?.filterPlaces()
            }
        ]
        for city in cityPlaceCount.keys.sorted() {
            let count = cityPlaceCount[city] ?? 0
            cityActions.append(
                UIAction(title: "\(city) (\(count))", state: selectedCity == city ? .on : .off) { [weak self] _ in
                    self?.selectedCity = city
                    self?.filterPlaces()
                }
            )
        }
        elements.append(UIMenu(
            title: "City",
            subtitle: selectedCity ?? "All Cities",
            image: UIImage(systemName: "building.2"),
            children: cityActions
        ))

        return elements
    }

    @objc private func mapMyPlacesChipTapped() {
        selectedConnectionId = (selectedConnectionId == "my_places_only") ? nil : "my_places_only"
        updateMapMyPlacesChipAppearance()
        filterPlaces()
    }

    private func updateMapMyPlacesChipAppearance() {
        let isActive = selectedConnectionId == "my_places_only"
        var config = mapMyPlacesChipButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: isActive ? "person.fill" : "person",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        config.baseForegroundColor = isActive ? .white : Constants.Colors.label
        mapMyPlacesChipButton.configuration = config
        mapMyPlacesChipButton.backgroundColor = isActive ? Constants.Colors.primary : Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        mapMyPlacesChipButton.layer.borderColor = isActive ? Constants.Colors.primary.cgColor : Constants.Colors.separator.cgColor
    }

    @objc private func mapListChipTapped() {
        isShowingMapPlacesList.toggle()

        // Flip the icon: show what tapping will switch to
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        mapListChipButton.setImage(
            UIImage(systemName: isShowingMapPlacesList ? "map" : "list.bullet", withConfiguration: config),
            for: .normal
        )

        if isShowingMapPlacesList {
            rebuildMapDistanceSortedPlaces()
            mapPlacesListTableView.reloadData()
        }

        // The list covers the map; map-only controls hide with it
        mapPlacesListTableView.isHidden = !isShowingMapPlacesList
        mapExpandButton.isHidden = isShowingMapPlacesList
        locationButton.isHidden = isShowingMapPlacesList
    }

    /// Rebuilds the distance-sorted data source for the places list from the
    /// currently filtered places. Places without a location sort last.
    private func rebuildMapDistanceSortedPlaces() {
        let reference = mapView.userLocation.location
            ?? CLLocation(latitude: mapView.region.center.latitude, longitude: mapView.region.center.longitude)

        mapDistanceSortedPlaces = filteredPlaces.map { place in
            let distance = place.location?.clLocation.map { reference.distance(from: $0) }
            return (place: place, distance: distance)
        }.sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
            }
        }

        if mapDistanceSortedPlaces.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No places to show"
            emptyLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            emptyLabel.textColor = Constants.Colors.secondaryLabel
            emptyLabel.textAlignment = .center
            mapPlacesListTableView.backgroundView = emptyLabel
        } else {
            mapPlacesListTableView.backgroundView = nil
        }
    }
    
    private func extractCityFromAddress(_ address: String) -> String? {
        // Split address by comma
        let components = address.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Common patterns:
        // "123 Main St, City, State ZIP"
        // "123 Main St, City, State"
        // "Place Name, 123 Main St, City, State"
        // "123 Main St, City"
        
        if components.count >= 3 {
            // Check if last component is ZIP/postal code (contains numbers)
            let lastComponent = components.last ?? ""
            let hasZipCode = lastComponent.rangeOfCharacter(from: .decimalDigits) != nil
            
            if hasZipCode && components.count >= 3 {
                // Format: "..., City, State ZIP"
                // City is 2 positions from the end
                let potentialCity = components[components.count - 3]
                // Clean up in case state is attached (e.g., "Phoenix AZ" -> "Phoenix")
                let cityParts = potentialCity.components(separatedBy: " ")
                if cityParts.count > 1 && cityParts.last?.count == 2 {
                    // Remove state abbreviation if attached
                    return cityParts.dropLast().joined(separator: " ")
                }
                return potentialCity
            } else if components.count >= 2 {
                // Format: "..., City, State" or "..., City"
                // City is typically second to last
                let potentialCity = components[components.count - 2]
                // Clean up in case state is attached
                let cityParts = potentialCity.components(separatedBy: " ")
                if cityParts.count > 1 && cityParts.last?.count == 2 {
                    // Remove state abbreviation if attached
                    return cityParts.dropLast().joined(separator: " ")
                }
                return potentialCity
            }
        } else if components.count == 2 {
            // Simple format: "Address, City"
            let potentialCity = components[1]
            // Clean up in case state is attached
            let cityParts = potentialCity.components(separatedBy: " ")
            if cityParts.count > 1 && cityParts.last?.count == 2 {
                // Remove state abbreviation if attached
                return cityParts.dropLast().joined(separator: " ")
            }
            return potentialCity
        }
        
        return nil
    }
    
    @objc private func followersStatTapped() {
        guard let user = user else { return }
        
        // Allow viewing any user's followers list
        // This enables social discovery through connections' networks
        showFollowersList(userId: user.id, listType: .followers)
    }
    
    @objc private func followingStatTapped() {
        guard let user = user else { return }
        
        // Allow viewing any user's following list
        // This enables social discovery through connections' networks
        showFollowersList(userId: user.id, listType: .following)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    private func showFollowersList(userId: String, listType: FollowListType) {
        let followersVC = FollowersListViewController()
        followersVC.userId = userId
        followersVC.listType = listType
        navigationController?.pushViewController(followersVC, animated: true)
    }
    
    @objc private func profileImageTapped() {
        // Show full-screen profile image
        if let profileImageURL = user?.profilePicture {
            ImageViewerService.shared.presentImageFromURL(profileImageURL, from: self)
        } else if let currentImage = profileImageView.image {
            ImageViewerService.shared.presentImage(currentImage, from: self)
        }
    }
    
    @objc private func messageButtonTapped() {
        print("🔍 ProfileViewController: messageButtonTapped called")
        guard let user = user else {
            print("❌ ProfileViewController: messageButtonTapped - user is nil")
            return
        }
        
        print("🔍 ProfileViewController: Creating/getting conversation with user: \(user.displayName) (ID: \(user.id))")
        
        // Create or get conversation with this user
        MessagingManager.shared.createOrGetDirectConversation(with: user.id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let conversation):
                print("✅ ProfileViewController: Successfully got conversation:")
                print("   - ID: \(conversation.id)")
                print("   - Type: \(conversation.type)")
                print("   - Participants: \(conversation.participants)")
                print("   - Display Name: \(conversation.displayName ?? "nil")")
                
                DispatchQueue.main.async {
                    print("🔍 ProfileViewController: Creating ChatViewController and navigating")
                    let chatVC = ChatViewController()
                    chatVC.conversation = conversation
                    self.navigationController?.pushViewController(chatVC, animated: true)
                }
            case .failure(let error):
                print("❌ ProfileViewController: Failed to create/get conversation: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: "Failed to start conversation: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func followButtonTapped() {
        guard let user = user else { return }
        
        // Disable button to prevent rapid toggles
        followButton.isEnabled = false
        followButton.alpha = 0.6
        
        let endpoint = isFollowing ? "users/\(user.id)/unfollow" : "users/\(user.id)/follow"
        let action = isFollowing ? "unfollow" : "follow"
        
        print("🔵 Follow button tapped - Action: \(action), User: \(user.displayName)")
        
        // Store original states for rollback
        let originalIsFollowing = isFollowing
        let originalUser = self.user
        
        // Apply optimistic UI updates immediately
        isFollowing.toggle()
        updateButtonVisibility()
        updateLocalFollowingCount(increment: action == "follow")
        
        // Update the user object's isFollowing flag optimistically
        if self.user?.isFollowing != nil {
            if let currentUser = self.user {
                self.user = User(
                    id: currentUser.id,
                    email: currentUser.email,
                    displayName: currentUser.displayName,
                    firstName: currentUser.firstName,
                    lastName: currentUser.lastName,
                    phoneNumber: currentUser.phoneNumber,
                    profilePicture: currentUser.profilePicture,
                    bio: currentUser.bio,
                    location: currentUser.location,
                    friends: currentUser.friends,
                    friendRequests: currentUser.friendRequests,
                    circleOrder: currentUser.circleOrder,
                    preferences: currentUser.preferences,
                    createdAt: currentUser.createdAt,
                    connectionStatus: currentUser.connectionStatus,
                    connectionDirection: currentUser.connectionDirection,
                    connectionId: currentUser.connectionId,
                    followers: currentUser.followers,
                    following: currentUser.following,
                    followersCount: currentUser.followersCount,
                    followingCount: currentUser.followingCount,
                    connectionsCount: currentUser.connectionsCount,
                    pinnedPlaces: currentUser.pinnedPlaces,
                    isFollowing: self.isFollowing
                )
            }
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success:
                    print("✅ Successfully \(action)ed user: \(user.displayName)")
                    
                    // Re-enable button after successful action
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.followButton.isEnabled = true
                        self.followButton.alpha = 1.0
                    }
                    
                case .failure(let error):
                    print("❌ Failed to \(action) user: \(error)")
                    
                    // Rollback optimistic updates on failure
                    self.isFollowing = originalIsFollowing
                    self.user = originalUser
                    self.updateButtonVisibility()
                    self.updateLocalFollowingCount(increment: action == "unfollow") // Reverse the action
                    
                    self.showAlert(title: "Error", message: "Failed to \(action) user: \(error.localizedDescription)")
                    
                    // Re-enable button immediately on error
                    self.followButton.isEnabled = true
                    self.followButton.alpha = 1.0
                }
            }
        }
    }
    
    @objc private func connectButtonTapped() {
        guard let user = user else { return }
        
        // Check if this is an incoming request to accept
        if connectionStatus == .pending && user.connectionDirection == "incoming" {
            // Find the connection to accept (check both accepted and pending connections)
            let allConnections = NetworkManager.shared.connections + NetworkManager.shared.pendingConnections
            guard let connection = allConnections.first(where: { 
                $0.otherUserId(currentUserId: AuthService.shared.getUserId() ?? "") == user.id 
            }) else {
                showAlert(title: "Error", message: "Connection request not found")
                return
            }
            
            // Accept the incoming request
            NetworkManager.shared.acceptConnection(connection.id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        // Update connection status
                        self.connectionStatus = .accepted
                        self.updateButtonVisibility()
                        self.showAlert(title: "Success", message: "Connection request accepted!")
                        
                        // Refresh connections
                        NetworkManager.shared.loadConnections()
                    case .failure(let error):
                        self.showAlert(title: "Error", message: "Failed to accept connection request: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Send new connection request
            NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        // Update connection status locally
                        self.connectionStatus = .pending
                        // Create new user instance with updated connection direction
                        if let currentUser = self.user {
                            self.user = User(
                                id: currentUser.id,
                                email: currentUser.email,
                                displayName: currentUser.displayName,
                                firstName: currentUser.firstName,
                                lastName: currentUser.lastName,
                                phoneNumber: currentUser.phoneNumber,
                                profilePicture: currentUser.profilePicture,
                                bio: currentUser.bio,
                                location: currentUser.location,
                                friends: currentUser.friends,
                                friendRequests: currentUser.friendRequests,
                                circleOrder: currentUser.circleOrder,
                                preferences: currentUser.preferences,
                                createdAt: currentUser.createdAt,
                                connectionStatus: "pending",
                                connectionDirection: "outgoing",
                                connectionId: currentUser.connectionId,
                                followers: currentUser.followers,
                                following: currentUser.following,
                                followersCount: currentUser.followersCount,
                                followingCount: currentUser.followingCount,
                                connectionsCount: currentUser.connectionsCount,
                                pinnedPlaces: currentUser.pinnedPlaces,
                                isFollowing: currentUser.isFollowing
                            )
                        }
                        self.updateButtonVisibility()
                        self.showAlert(title: "Success", message: "Connection request sent!")
                        
                        // Refresh connections to get updated list
                        NetworkManager.shared.loadConnections()
                    case .failure(let error):
                        self.showAlert(title: "Error", message: "Failed to send connection request: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    @objc private func expandMapButtonTapped() {
        // Pass all places to the full screen map, not the filtered ones
        // Don't pass the selected category so the full screen map starts fresh
        let fullScreenMapVC = FullScreenMapViewController(
            places: allPlaces,  // Pass all places
            initialRegion: mapView.region,
            selectedCategory: nil,  // Don't pass the filter
            selectedConnectionId: nil
        )
        fullScreenMapVC.delegate = self
        fullScreenMapVC.viewMode = .allPlaces
        fullScreenMapVC.isPresentedModally = true
        
        let navigationController = UINavigationController(rootViewController: fullScreenMapVC)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
    
    @objc private func createCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        
        present(navController, animated: true, completion: nil)
    }
    
    @objc private func activityNotificationsToggled() {
        guard let user = user else { return }
        
        let isEnabled = activityNotificationsToggle.isOn
        
        // Show loading state while updating
        activityNotificationsToggle.isEnabled = false
        
        // Find the connection for this user
        let allConnections = NetworkManager.shared.connections + NetworkManager.shared.pendingConnections
        let currentUserId = AuthService.shared.getUserId() ?? ""
        guard let connection = allConnections.first(where: { 
            $0.otherUserId(currentUserId: currentUserId) == user.id 
        }) else {
            print("❌ No connection found for user: \(user.id)")
            activityNotificationsToggle.isEnabled = true
            activityNotificationsToggle.setOn(!isEnabled, animated: true)
            showError("Connection not found")
            return
        }
        
        // Update connection notification preference
        updateConnectionNotificationPreference(connectionId: connection.id, enabled: isEnabled) { [weak self] success in
            DispatchQueue.main.async {
                self?.activityNotificationsToggle.isEnabled = true
                
                if !success {
                    // Revert toggle state if update failed
                    self?.activityNotificationsToggle.setOn(!isEnabled, animated: true)
                    self?.showError("Failed to update notification preference")
                }
            }
        }
    }
    
    private func updateConnectionNotificationPreference(connectionId: String, enabled: Bool, completion: @escaping (Bool) -> Void) {
        // Create a simple response model for this endpoint
        struct NotificationPreferenceResponse: Codable {
            let success: Bool
            let message: String?
        }
        
        APIService.shared.request(
            endpoint: "connections/\(connectionId)/notifications",
            method: .put,
            body: ["activityNotificationsEnabled": enabled],
            requiresAuth: true
        ) { (result: Result<NotificationPreferenceResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ Connection notification preference updated: \(response.success)")
                completion(response.success)
            case .failure(let error):
                print("❌ Failed to update connection notification preference: \(error)")
                completion(false)
            }
        }
    }
    
    @objc private func zoomToUserLocation() {
        let locationManager = CLLocationManager()
        
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            showError("Location services are disabled. Please enable them in Settings.")
            return
        }
        
        // Check authorization status
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            // Request permission
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            showError("Location access is denied. Please enable it in Settings.")
        case .authorizedWhenInUse, .authorizedAlways:
            // Zoom to user location
            if let userLocation = mapView.userLocation.location {
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: true)
            } else {
                // Try to get current location
                locationManager.requestLocation()
            }
        @unknown default:
            break
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func refreshCurrentUserData() {
        // Fetch updated user data for the current user
        guard let currentUserId = AuthService.shared.getUserId() else { return }
        
        // Force fetch fresh data from server to get updated following array
        AuthService.shared.fetchCurrentUser { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let updatedUser):
                    // Only update stats if viewing own profile
                    if self.user?.id == currentUserId {
                        // Update all stats with fresh data
                        let followingCount = updatedUser.followingCount ?? 0
                        let followersCount = updatedUser.followersCount ?? 0
                        self.followingStatView.configure(number: "\(followingCount)", title: "Following")
                        self.followersStatView.configure(number: "\(followersCount)", title: "Followers")
                        
                        // Update cached user data for own profile
                        self.user = updatedUser
                    }
                    
                    // Don't re-check follow status here as it would reset the local state
                    // The SSE event will handle updating the following array
                case .failure:
                    // Ignore errors for refresh
                    break
                }
            }
        }
    }
    
    private func checkConnectionAndFollowStatus() {
        guard let user = user else { return }
        
        print("🔍 Checking connection and follow status for user: \(user.displayName)")
        
        // Check if user is in current user's connections (both accepted and pending)
        let allConnections = NetworkManager.shared.connections + NetworkManager.shared.pendingConnections
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let connection = allConnections.first { $0.otherUserId(currentUserId: currentUserId) == user.id }
        
        connectionStatus = connection?.status
        
        // Set connection direction based on who initiated the request
        if let connection = connection, connection.status == .pending {
            // If the current user initiated the request, it's outgoing
            let direction = connection.userId == currentUserId ? "outgoing" : "incoming"
            
            // Create new user instance with updated connection direction
            if let currentUser = self.user {
                self.user = User(
                    id: currentUser.id,
                    email: currentUser.email,
                    displayName: currentUser.displayName,
                    firstName: currentUser.firstName,
                    lastName: currentUser.lastName,
                    phoneNumber: currentUser.phoneNumber,
                    profilePicture: currentUser.profilePicture,
                    bio: currentUser.bio,
                    location: currentUser.location,
                    friends: currentUser.friends,
                    friendRequests: currentUser.friendRequests,
                    circleOrder: currentUser.circleOrder,
                    preferences: currentUser.preferences,
                    createdAt: currentUser.createdAt,
                    connectionStatus: currentUser.connectionStatus,
                    connectionDirection: direction,
                    connectionId: currentUser.connectionId,
                    followers: currentUser.followers,
                    following: currentUser.following,
                    followersCount: currentUser.followersCount,
                    followingCount: currentUser.followingCount,
                    connectionsCount: currentUser.connectionsCount,
                    pinnedPlaces: currentUser.pinnedPlaces,
                    isFollowing: currentUser.isFollowing
                )
            }
        }
        
        // First, check if the user object has isFollowing property (from backend)
        if let userIsFollowing = user.isFollowing {
            let wasFollowing = isFollowing
            isFollowing = userIsFollowing
            print("📊 Follow status from backend - Was: \(wasFollowing), Now: \(isFollowing)")
        } else {
            // Fallback: Check follow status from current user's following list
            if let currentUser = AuthService.shared.currentUser,
               let following = currentUser.following {
                let wasFollowing = isFollowing
                isFollowing = following.contains(user.id)
                print("📊 Follow status from local - Was: \(wasFollowing), Now: \(isFollowing), Following array: \(following.count) users")
            } else {
                isFollowing = false
                print("📊 No following data available")
            }
            
            // If we're viewing another user and don't have current user data, fetch it
            if AuthService.shared.currentUser == nil && user.id != AuthService.shared.getUserId() {
                AuthService.shared.fetchCurrentUser { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Re-check follow status after fetching current user
                        self.checkConnectionAndFollowStatus()
                    }
                }
            }
        }
        
        updateButtonVisibility()
    }
    
    private func updateLocalFollowingCount(increment: Bool) {
        // Only update if we're viewing the current user's profile
        guard let currentUserId = AuthService.shared.getUserId(),
              let user = self.user,
              user.id == currentUserId else {
            return
        }
        
        // Get current following count and update it
        let currentCount = user.followingCount ?? 0
        let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)
        
        // Update the UI immediately
        followingStatView.configure(number: "\(newCount)", title: "Following")
        
        // Update the cached user data
        self.user = user.copy(followingCount: newCount)
        
        print("📊 Updated local following count: \(currentCount) → \(newCount)")
    }
    
    private func updateButtonVisibility() {
        guard let user = user else { return }
        let isCurrentUser = user.id == AuthService.shared.getUserId()
        
        // Don't show connection buttons for current user
        if isCurrentUser {
            messageButton.isHidden = true
            followButton.isHidden = true
            connectButton.isHidden = true
            return
        }
        
        // Determine connection status
        let isConnected = connectionStatus == .accepted
        let isPending = connectionStatus == .pending
        
        // Update button visibility and constraints based on connection status
        if isPending {
            // Pending connections: Show connect button with appropriate state
            messageButton.isHidden = true
            connectButton.isHidden = false
            followButton.isHidden = false
            
            // Update button based on connection direction
            if let direction = user.connectionDirection {
                if direction == "outgoing" {
                    // Sent request - show "Pending" disabled
                    connectButton.setTitle("Pending", for: .normal)
                    connectButton.backgroundColor = .systemGray5
                    connectButton.setTitleColor(.label, for: .normal)
                    connectButton.isEnabled = false
                } else if direction == "incoming" {
                    // Received request - show "Accept" enabled
                    connectButton.setTitle("Accept", for: .normal)
                    connectButton.backgroundColor = .systemGreen
                    connectButton.setTitleColor(.white, for: .normal)
                    connectButton.isEnabled = true
                }
            } else {
                // Default pending state if direction unknown
                connectButton.setTitle("Pending", for: .normal)
                connectButton.backgroundColor = .systemGray5
                connectButton.setTitleColor(.label, for: .normal)
                connectButton.isEnabled = false
            }
            
            // Activate follow button constraint to connect button
            followButtonLeadingToMessageConstraint?.isActive = false
            followButtonLeadingToConnectConstraint?.isActive = true
        } else if isConnected {
            // Connected users: Show message and follow buttons
            messageButton.isHidden = false
            connectButton.isHidden = true
            followButton.isHidden = false
            
            // Activate follow button constraint to message button
            followButtonLeadingToConnectConstraint?.isActive = false
            followButtonLeadingToMessageConstraint?.isActive = true
        } else {
            // Non-connected users: Show connect and follow buttons
            messageButton.isHidden = true
            connectButton.isHidden = false
            followButton.isHidden = false
            
            // Reset connect button to default state
            connectButton.setTitle("Connect", for: .normal)
            connectButton.backgroundColor = Constants.Colors.secondary
            connectButton.setTitleColor(.white, for: .normal)
            connectButton.isEnabled = true
            
            // Activate follow button constraint to connect button
            followButtonLeadingToMessageConstraint?.isActive = false
            followButtonLeadingToConnectConstraint?.isActive = true
        }
        
        // Update follow button appearance based on follow status
        followButton.setTitle(isFollowing ? "Following" : "Follow", for: .normal)
        if isFollowing {
            followButton.setStyle(.following)
        } else {
            followButton.setStyle(.secondary)
        }
        
        // Show/hide notifications section based on connection status
        let shouldShowNotifications = !isCurrentUser && isConnected
        notificationsSectionContainer.isHidden = !shouldShowNotifications
        
        // Set initial toggle state if connected
        if shouldShowNotifications {
            // Find the connection and set toggle state
            let allConnections = NetworkManager.shared.connections + NetworkManager.shared.pendingConnections
            let currentUserId = AuthService.shared.getUserId() ?? ""
            if let connection = allConnections.first(where: { 
                $0.otherUserId(currentUserId: currentUserId) == user.id 
            }) {
                activityNotificationsToggle.isOn = connection.activityNotificationsEnabled ?? false
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadAllPlaces() {
        // Load places from all circles
        allPlaces.removeAll()
        
        for circle in circles {
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success(let places):
                        self.allPlaces.append(contentsOf: places)
                        self.filterPlaces()
                    case .failure(let error):
                        print("Failed to load places for circle \(circle.name): \(error)")
                    }
                }
            }
        }
    }
    
    private func filterPlaces() {
        // Use centralized filtering extensions
        let unifiedCategory = selectedCategory.map { UnifiedCategory.standard($0) }
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        filteredPlaces = allPlaces.filtered(
            category: unifiedCategory,
            connectionId: selectedConnectionId,
            city: selectedCity,
            currentUserId: currentUserId
        )
        
        // Update map pins
        updateMapPins()

        // Keep the distance-sorted list in sync when it's visible
        if isShowingMapPlacesList {
            rebuildMapDistanceSortedPlaces()
            mapPlacesListTableView.reloadData()
        }
    }
    
    private func updateMapPins() {
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add filtered places as pins using PlaceAnnotation for custom styling
        for place in filteredPlaces {
            if place.location?.clLocation != nil {
                let annotation = PlaceAnnotation(place: place)
                mapView.addAnnotation(annotation)
            }
        }
        
        // Zoom to show all pins
        if !filteredPlaces.isEmpty {
            mapView.showAnnotations(mapView.annotations, animated: true)
        }
    }
    
    
    private func loadUserProfile(completion: (() -> Void)? = nil) {
        print("🚀 ProfileViewController: loadUserProfile called")
        print("🚀 ProfileViewController: Has existing user? \(self.user != nil)")
        
        if let user = self.user {
            // If user is provided, use it
            print("✅ ProfileViewController: Using existing user: \(user.id)")
            displayUser(user)
            fetchUserStats(userId: user.id)
            completion?()
        } else {
            // Otherwise fetch current user - always get fresh data
            print("🔄 ProfileViewController: No existing user, fetching fresh data")
            fetchFreshUserData(completion: completion)
        }
    }
    
    private func fetchFreshUserData(completion: (() -> Void)? = nil) {
        print("🚀 ProfileViewController: fetchFreshUserData called")
        
        // Always fetch fresh user data from the server
        UserService.shared.fetchUserProfile { [weak self] result in
            print("📡 ProfileViewController: fetchUserProfile callback received")
            guard let self = self else {
                print("⚠️ ProfileViewController: Self deallocated during fetch")
                completion?()
                return
            }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    print("✅ ProfileViewController: Successfully fetched user profile")
                    print("✅ ProfileViewController: User ID: \(user.id)")
                    print("✅ ProfileViewController: User name: \(user.displayName)")
                    self.user = user
                    self.displayUser(user)
                    self.fetchUserStats(userId: user.id)
                    
                    // Update the cached user in AuthService
                    AuthService.shared.updateCurrentUser(user)
                    
                case .failure(let error):
                    print("❌ ProfileViewController: Failed to fetch user profile: \(error)")
                    print("❌ ProfileViewController: Error type: \(type(of: error))")
                    
                    // If we have cached data, use it as fallback
                    if let cachedUser = AuthService.shared.currentUser {
                        print("⚠️ ProfileViewController: Using cached user as fallback: \(cachedUser.id)")
                        self.user = cachedUser
                        self.displayUser(cachedUser)
                        self.fetchUserStats(userId: cachedUser.id)
                    } else {
                        print("❌ ProfileViewController: No cached user available, showing default profile")
                        // Show error or default values
                        self.displayDefaultProfile()
                    }
                }
                
                // Call completion after all data loading is done
                completion?()
            }
        }
    }
    
    private func loadCachedVideos() {
        guard let userId = user?.id ?? AuthService.shared.getUserId() else { return }
        let isCurrentUser = userId == AuthService.shared.getUserId()
        
        // Only load cached videos for current user
        if isCurrentUser {
            print("💾 ProfileViewController: Checking for cached videos...")
            // For now, we'll just rely on network fetch
            // TODO: Implement actual cache retrieval from VideoStorageService
        }
    }
    
    private func fetchUserVideos() {
        guard let userId = user?.id ?? AuthService.shared.getUserId() else {
            print("⚠️ ProfileViewController: No user ID available for fetching videos")
            isLoadingVideos = false
            videosLoadingIndicator.stopAnimating()
            return
        }
        
        // Prevent multiple simultaneous fetches
        guard !isLoadingVideos else { return }
        
        isLoadingVideos = true
        
        let isCurrentUser = userId == AuthService.shared.getUserId()
        
        print("📹 ProfileViewController: Starting to fetch videos for user: \(userId)")
        print("   - Is current user: \(isCurrentUser)")
        print("   - Email: \(user?.email ?? "unknown")")
        
        APIService.shared.getUserVideos(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.isLoadingVideos = false
                    // Filter out failed uploads and videos without URLs
                    self.videos = response.data.filter { video in
                        let hasValidUrl = video.contentType == "photo" ? video.thumbnailUrl != nil : video.videoUrl != nil
                        return video.uploadStatus == .ready && hasValidUrl
                    }
                    
                    // Debug: Log thumbnail URLs to check for duplicates
                    print("📹 ProfileViewController: Fetched \(response.data.count) videos, showing \(self.videos.count) valid ones")
                    for (index, video) in self.videos.enumerated() {
                        let thumbnailPreview = video.thumbnailUrl?.suffix(50) ?? "none"
                        print("   [\(index)] ID: \(video.id.prefix(8))... Type: \(video.contentType ?? "video") Thumbnail: ...\(thumbnailPreview)")
                    }
                    
                    // Log video details
                    for (index, video) in response.data.enumerated() {
                        print("   Video \(index + 1):")
                        print("     - Title: \(video.title)")
                        print("     - ID: \(video.id)")
                        print("     - Has video URL: \(video.videoUrl != nil)")
                        print("     - Has preview URL: \(video.previewUrl != nil)")
                        print("     - Has thumbnail URL: \(video.thumbnailUrl != nil)")
                        print("     - Upload status: \(video.uploadStatus.rawValue)")
                        print("     - Content type: \(video.contentType ?? "video")")
                        print("     - Video type: \(video.videoType ?? "uploaded")")
                    }
                    
                    // Cache user's own videos for permanent storage
                    if isCurrentUser && !response.data.isEmpty {
                        print("💾 ProfileViewController: Caching \(response.data.count) user videos for offline access")
                        VideoStorageService.shared.cacheUserVideos(response.data)
                    }
                    
                    // Update videos collection view
                    if self.contentTypeSegmentedControl.selectedSegmentIndex == 1 {
                        self.videosLoadingIndicator.stopAnimating()
                        self.videosCollectionView.reloadData()
                        self.updateVideosCollectionHeight()
                        
                        // Show/hide empty state
                        self.videosEmptyLabel.isHidden = !self.videos.isEmpty
                        
                        if self.videos.isEmpty {
                            print("📭 ProfileViewController: No videos to display - showing empty state")
                        }
                    }
                    
                case .failure(let error):
                    self.isLoadingVideos = false
                    print("❌ ProfileViewController: Failed to fetch videos: \(error)")
                    print("   - Error details: \(error.localizedDescription)")
                    
                    // Don't show error to user, just leave videos empty
                    self.videos = []
                    if self.contentTypeSegmentedControl.selectedSegmentIndex == 1 {
                        self.videosLoadingIndicator.stopAnimating()
                        self.videosEmptyLabel.isHidden = false
                    }
                }
            }
        }
    }
    
    // MARK: - User Uploads Data Loading
    
    private func fetchUserUploads() {
        guard let userId = user?.id ?? AuthService.shared.getUserId() else {
            print("⚠️ ProfileViewController: No user ID available for fetching uploads")
            isLoadingUploads = false
            uploadsLoadingIndicator.stopAnimating()
            return
        }
        
        print("📷 ProfileViewController: Fetching uploads for user: \(userId)")
        isLoadingUploads = true
        
        GlobalPlaceService.shared.getUserUploads(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.isLoadingUploads = false
                
                switch result {
                case .success(let response):
                    print("✅ ProfileViewController: Successfully fetched \(response.data.count) uploads")
                    self.uploads = response.data
                    
                    // Log upload details for debugging
                    if !response.data.isEmpty {
                        print("📸 ProfileViewController: Upload details:")
                        for (index, upload) in response.data.prefix(3).enumerated() {
                            print("     Upload \(index + 1): \(upload.placeName) - \(upload.imageUrl)")
                        }
                    }
                    
                    // Update uploads collection view
                    if self.contentTypeSegmentedControl.selectedSegmentIndex == 2 {
                        self.uploadsLoadingIndicator.stopAnimating()
                        self.uploadsCollectionView.reloadData()
                        self.updateUploadsCollectionHeight()
                        
                        // Show/hide empty state
                        self.uploadsEmptyLabel.isHidden = !self.uploads.isEmpty
                        
                        if self.uploads.isEmpty {
                            print("📭 ProfileViewController: No uploads to display - showing empty state")
                        }
                    }
                    
                case .failure(let error):
                    self.isLoadingUploads = false
                    print("❌ ProfileViewController: Failed to fetch uploads: \(error)")
                    print("   - Error details: \(error.localizedDescription)")
                    
                    // Don't show error to user, just leave uploads empty
                    self.uploads = []
                    if self.contentTypeSegmentedControl.selectedSegmentIndex == 2 {
                        self.uploadsLoadingIndicator.stopAnimating()
                        self.uploadsEmptyLabel.isHidden = false
                    }
                }
            }
        }
    }
    
    private func displayUser(_ user: User) {
        // Debug logging
        print("🔍 ProfileViewController - Displaying user data:")
        print("   - Display Name: \(user.displayName)")
        print("   - First Name: \(user.firstName ?? "nil")")
        print("   - Last Name: \(user.lastName ?? "nil")")
        print("   - Phone Number: \(user.phoneNumber ?? "nil")")
        print("   - Bio: \(user.bio ?? "nil")")
        print("   - Location: \(user.location ?? "nil")")
        print("   - Circles Count: \(user.circlesCount ?? 0)")
        print("   - Places Count: \(user.placesCount ?? 0)")
        
        // Display initial counts from user object if available (for new users)
        // This ensures counts show immediately after registration
        if let circlesCount = user.circlesCount {
            circlesStatView.configure(number: "\(circlesCount)", title: "Circles")
        }
        if let placesCount = user.placesCount {
            placesStatView.configure(number: "\(placesCount)", title: "Places")
        }
        
        // Update UI with user data
        if let profileImageUrl = user.profilePicture {
            // In a real app, load image from URL
            ImageService.shared.loadImage(from: profileImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        self.profileImageView.tintColor = Constants.Colors.primary
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
        
        // Display username at the top
        usernameLabel.text = user.displayName
        
        // Check if this is the current user
        let isCurrentUser = user.id == AuthService.shared.getUserId()
        
        // Show premium badge for current user if subscribed
        if isCurrentUser {
            Task { @MainActor in
                premiumBadgeView.isHidden = !SubscriptionManager.shared.isSubscribed
            }
        } else {
            // Hide for other users (we don't track their subscription status)
            premiumBadgeView.isHidden = true
        }
        
        // Show location if available
        if let location = user.location, !location.isEmpty {
            // Create attributed string with location icon
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: "location.fill")?.withTintColor(Constants.Colors.secondaryLabel, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: -1, width: 12, height: 12)
            
            let attributedString = NSMutableAttributedString()
            attributedString.append(NSAttributedString(attachment: attachment))
            attributedString.append(NSAttributedString(string: " \(location)", attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: Constants.Colors.secondaryLabel
            ]))
            
            locationLabel.attributedText = attributedString
            locationLabel.isHidden = false
        } else {
            locationLabel.isHidden = true
        }
        
        // Show only bio - displayName is already shown in usernameLabel
        if let bio = user.bio, !bio.isEmpty {
            bioLabel.text = bio
            bioLabel.isHidden = false
        } else {
            bioLabel.text = nil
            bioLabel.isHidden = true
        }
        
        // Show/hide buttons based on whether this is the current user
        editProfileButton.isHidden = !isCurrentUser
        shareProfileButton.isHidden = !isCurrentUser
        visitHistoryButton.isHidden = !isCurrentUser
        suggestedButton.isHidden = !isCurrentUser
        logoutButton.isHidden = !isCurrentUser
        versionLabel.isHidden = !isCurrentUser
        contentTypeSegmentedControl.isHidden = !isCurrentUser
        floatingAddButton.isHidden = !isCurrentUser || contentTypeSegmentedControl.selectedSegmentIndex != 0
        
        // Switch constraints based on user type with animation
        UIView.animate(withDuration: 0.3) {
            if isCurrentUser {
                // Current user - search bar anchored to segmented control, separator to profile
                self.searchBarContainerTopToSeparatorConstraint?.isActive = false
                self.searchBarContainerTopToSegmentedConstraint?.isActive = true
                self.separatorLineTopToNotificationConstraint?.isActive = false
                self.separatorLineTopToProfileConstraint?.isActive = true
                print("📐 Switched to current user layout - no notification section space")
            } else {
                // Connection profile - search bar anchored to separator, separator to notification section
                self.searchBarContainerTopToSegmentedConstraint?.isActive = false
                self.searchBarContainerTopToSeparatorConstraint?.isActive = true
                self.separatorLineTopToProfileConstraint?.isActive = false
                self.separatorLineTopToNotificationConstraint?.isActive = true
                print("📐 Switched to connection profile layout - with notification section space")
            }
            self.view.layoutIfNeeded()
        }
        
        // Update navigation bar items based on profile type
        if isCurrentUser {
            // Current user - show settings and video buttons
            let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsButtonTapped))
            let videoButton = UIBarButtonItem(image: UIImage(systemName: "video.fill"), style: .plain, target: self, action: #selector(videoButtonTapped))
            let checkInButton = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"), style: .plain, target: self, action: #selector(checkInButtonTapped))
            let rewardsButton = UIBarButtonItem(image: UIImage(systemName: "star.circle"), style: .plain, target: self, action: #selector(rewardsButtonTapped))
            navigationItem.rightBarButtonItems = [settingsButton, videoButton, checkInButton, rewardsButton]
        } else {
            // Other user - no navigation bar buttons
            navigationItem.rightBarButtonItems = []
        }
        
        // For other users, check connection status and follow status
        if !isCurrentUser {
            checkConnectionAndFollowStatus()
        } else {
            // Hide connection buttons for current user
            messageButton.isHidden = true
            followButton.isHidden = true
            connectButton.isHidden = true
        }
        
        // Hide activity notifications section for current user (only show for connections)
        notificationsSectionContainer.isHidden = isCurrentUser
        
        // Configure drag and drop based on whether this is the current user
        configureDragAndDrop()
    }
    
    private func fetchUserStats(userId: String) {
        print("🚀 ProfileViewController: fetchUserStats called for userId: \(userId)")
        print("🚀 ProfileViewController: Current user ID: \(AuthService.shared.getUserId() ?? "nil")")
        
        // For current user, fetch their circles
        if userId == AuthService.shared.getUserId() {
            print("✅ ProfileViewController: Fetching stats for current user")
            // Fetch circles
            CircleService.shared.fetchUserCircles { [weak self] result in
                print("📡 ProfileViewController: fetchUserCircles callback received")
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let circles):
                        self.circles = circles
                        print("🔍 ProfileViewController - Fetched \(circles.count) circles")
                        
                        // Calculate total places from the same fetch
                        var totalPlaces = 0
                        for circle in self.circles {
                            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
                            totalPlaces += placeCount
                            print("   Circle '\(circle.name)': placesCount=\(circle.placesCount ?? -1), places array=\(circle.places?.count ?? 0)")
                        }
                        
                        // Update both stats
                        self.circlesStatView.configure(number: "\(self.circles.count)", title: "Circles")
                        self.placesStatView.configure(number: "\(totalPlaces)", title: "Places")
                        print("   Total places calculated: \(totalPlaces)")
                        
                        self.circlesCollectionView.reloadData()
                        self.updateCollectionViewHeight()
                        
                        // Also fetch videos
                        self.fetchUserVideos()
                        
                        // Load all places for search functionality
                        self.loadAllPlacesFromCircles(circles)
                    case .failure(let error):
                        self.circles = []
                        self.circlesStatView.configure(number: "0", title: "Circles")
                        self.placesStatView.configure(number: "0", title: "Places")
                        self.circlesCollectionView.reloadData()
                        self.updateCollectionViewHeight()
                        
                        // Also fetch videos
                        self.fetchUserVideos()
                        self.showErrorWithRetry(error) {
                            self.loadUserProfile(completion: nil)
                        }
                    }
                }
            }
            
            // Fetch connections count
            let connectionsCount = NetworkManager.shared.connections.count
            print("🔍 ProfileViewController - Connections count: \(connectionsCount)")
            connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
            
            // Add followers/following stats from user data
            if let user = self.user {
                let followersCount = user.followersCount ?? 0
                let followingCount = user.followingCount ?? 0
                followersStatView.configure(number: "\(followersCount)", title: "Followers")
                followingStatView.configure(number: "\(followingCount)", title: "Following")
                print("🔍 ProfileViewController - Followers: \(followersCount), Following: \(followingCount)")
            } else {
                followersStatView.configure(number: "0", title: "Followers")
                followingStatView.configure(number: "0", title: "Following")
            }
        } else {
            // For other users, fetch their public circles
            fetchOtherUserCircles(userId: userId)
        }
    }
    
    private func fetchOtherUserCircles(userId: String) {
        // Prevent multiple simultaneous requests for the same user
        guard !isFetchingOtherUserCircles else {
            print("🔍 Already fetching circles for user \(userId), skipping duplicate request")
            return
        }
        
        isFetchingOtherUserCircles = true
        
        // Fetch circles from network endpoint for other users
        let endpoint = "network/user-circles/\(userId)"
        let completion = createAPICompletion { (result: Result<UserCirclesResponse, Error>) in
            DispatchQueue.main.async {
                // Reset the flag when request completes
                self.isFetchingOtherUserCircles = false
                
                switch result {
                case .success(let response):
                    self.circles = response.data.circles
                    
                    // Calculate total places
                    var totalPlaces = 0
                    for circle in response.data.circles {
                        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
                        totalPlaces += placeCount
                    }
                    
                    // Update stats
                    self.circlesStatView.configure(number: "\(response.data.circles.count)", title: "Circles")
                    self.placesStatView.configure(number: "\(totalPlaces)", title: "Places")
                
                    // Use user data for followers/following/connections
                    let user = response.data.user
                    let connectionsCount = user.connectionsCount ?? 0
                    let followersCount = user.followersCount ?? 0
                    let followingCount = user.followingCount ?? 0
                    
                    self.connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
                    self.followersStatView.configure(number: "\(followersCount)", title: "Followers")
                    self.followingStatView.configure(number: "\(followingCount)", title: "Following")
                    
                    // Update user data to get latest info
                    self.user = user
                    
                    // Re-check connection and follow status with fresh data
                    self.checkConnectionAndFollowStatus()
                    
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                    
                    // Load all places for search functionality
                    self.loadAllPlacesFromCircles(response.data.circles)
                    
                case .failure(let error):
                    print("Failed to load other user circles: \(error)")
                    
                    // Handle rate limiting gracefully
                    if case APIError.rateLimited(let retryAfter) = error {
                        print("🔍 Rate limited loading user circles, will retry in \(retryAfter ?? 0) seconds")
                        // Don't show error to user for rate limiting - just use cached/default data
                    } else {
                        // Show error for other types of failures
                        print("❌ Non-rate-limit error loading user circles: \(error)")
                    }
                    
                    // Show default stats on error
                    self.circlesStatView.configure(number: "0", title: "Circles")
                    self.placesStatView.configure(number: "0", title: "Places")
                    self.connectionsStatView.configure(number: "0", title: "Connections")
                    self.followersStatView.configure(number: "0", title: "Followers")
                    self.followingStatView.configure(number: "0", title: "Following")
                    
                    self.circles = []
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                }
            }
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true,
            completion: completion
        )
    }
    
    private func displayDefaultProfile() {
        // Fallback default display
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = Constants.Colors.primary
        
        usernameLabel.text = "User"
        locationLabel.isHidden = true
        bioLabel.text = "No bio available"
        bioLabel.isHidden = false
        
        circlesStatView.configure(number: "0", title: "Circles")
        placesStatView.configure(number: "0", title: "Places")
        connectionsStatView.configure(number: "0", title: "Connections")
        followersStatView.configure(number: "0", title: "Followers")
        followingStatView.configure(number: "0", title: "Following")
    }
    
    private func displayAppVersion() {
        // Get app version from Info.plist
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        versionLabel.text = "Version \(appVersion) (\(buildNumber))"
    }
    
    private func setupNotificationObservers() {
        // Listen for circle deletion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCircleDeleted(_:)),
            name: .circleDeleted,
            object: nil
        )
        
        // Listen for refresh circles notification (e.g., when a place is added)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefreshCircles),
            name: NSNotification.Name("RefreshCircles"),
            object: nil
        )
        
        // Listen for connections loaded notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionsLoaded),
            name: .connectionsLoaded,
            object: nil
        )
        
        // Listen for keyboard notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc private func handleCircleDeleted(_ notification: Notification) {
        guard let circleId = notification.userInfo?["circleId"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Remove the circle from our local array
            if let index = self.circles.firstIndex(where: { $0.id == circleId }) {
                self.circles.remove(at: index)
                self.circlesCollectionView.reloadData()
                self.updateCollectionViewHeight()
                
                // Update stats
                self.circlesStatView.configure(number: "\(self.circles.count)", title: "Circles")
            }
        }
    }
    
    @objc private func handleRefreshCircles() {
        // Refresh user stats to get updated circle counts
        if let userId = self.user?.id {
            fetchUserStats(userId: userId)
        }
    }
    
    @objc private func handleConnectionsLoaded() {
        // Update connections count when NetworkManager finishes loading
        if let userId = self.user?.id, userId == AuthService.shared.getUserId() {
            let connectionsCount = NetworkManager.shared.connections.count
            print("🔍 ProfileViewController - Updated connections count after load: \(connectionsCount)")
            connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
        }
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
        
        UIView.animate(withDuration: animationDuration) {
            self.scrollView.contentInset = contentInsets
            self.scrollView.scrollIndicatorInsets = contentInsets
            
            // If search results are showing, scroll to make them visible
            if !self.searchResultsTableView.isHidden && self.isSearching {
                let searchBarFrame = self.searchBar.convert(self.searchBar.bounds, to: self.view)
                let visibleHeight = self.view.frame.height - keyboardHeight
                
                if searchBarFrame.maxY > visibleHeight {
                    let scrollOffset = searchBarFrame.maxY - visibleHeight + 20
                    self.scrollView.contentOffset.y += scrollOffset
                }
            }
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        UIView.animate(withDuration: animationDuration) {
            self.scrollView.contentInset = .zero
            self.scrollView.scrollIndicatorInsets = .zero
        }
    }
    
    private func logout() {
        // Log out the user
        AuthService.shared.logout()
        
        // Show login screen
        let loginVC = LoginViewController()
        let navController = UINavigationController(rootViewController: loginVC)
        
        // Get the scene from the current window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController = navController
            window.makeKeyAndVisible()
        }
    }
    
    private func updateCollectionViewHeight() {
        // Calculate required height based on number of circles (3-column grid)
        let itemsPerRow: CGFloat = 3
        let interitemSpacing: CGFloat = 12 // Match the actual spacing from flow layout delegate
        let lineSpacing: CGFloat = 16 // Match the actual line spacing from flow layout delegate
        
        // Use collection view's actual width for accurate calculation
        let collectionWidth = circlesCollectionView.bounds.width > 0 ? circlesCollectionView.bounds.width : UIScreen.main.bounds.width
        let totalHorizontalSpacing = interitemSpacing * (itemsPerRow - 1)
        let itemWidth = (collectionWidth - totalHorizontalSpacing) / itemsPerRow
        let itemHeight = itemWidth + 50 // Square cells + 50 for labels (matching flow layout delegate)
        
        let rows = ceil(CGFloat(circles.count) / itemsPerRow)
        let totalHeight = (rows * itemHeight) + ((rows - 1) * lineSpacing)
        
        // Ensure minimum height of 400 to prevent cutoff
        let finalHeight = max(totalHeight, 400)
        
        print("🔍 ProfileViewController - Updating circles collection height:")
        print("   - Circles count: \(circles.count)")
        print("   - Rows needed: \(rows)")
        print("   - Collection width: \(collectionWidth)")
        print("   - Item dimensions: \(itemWidth) x \(itemHeight)")
        print("   - Total calculated height: \(totalHeight)")
        print("   - Final height: \(finalHeight)")
        
        circlesCollectionHeightConstraint?.constant = finalHeight
        
        // Force layout update for both collection view and scroll view
        UIView.animate(withDuration: 0.3) {
            self.circlesCollectionView.layoutIfNeeded()
            self.scrollView.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Video Methods
    
    private func updateVideosCollectionHeight() {
        // For 3-column grid layout, calculate height based on number of rows
        guard !videos.isEmpty else {
            videosCollectionHeightConstraint?.constant = 100 // Minimum height for empty state
            return
        }
        
        // Calculate grid dimensions
        let spacing: CGFloat = 2
        let numberOfColumns: CGFloat = 3
        let totalSpacing = spacing * (numberOfColumns - 1)
        let collectionWidth = videosCollectionView.bounds.width > 0 ? videosCollectionView.bounds.width : UIScreen.main.bounds.width
        let itemWidth = (collectionWidth - totalSpacing) / numberOfColumns
        let itemHeight = itemWidth // Square items
        
        // Calculate number of rows
        let numberOfRows = ceil(Double(videos.count) / Double(numberOfColumns))
        let totalRowSpacing = spacing * (CGFloat(numberOfRows) - 1)
        let totalHeight = (CGFloat(numberOfRows) * itemHeight) + totalRowSpacing + 20 // Add some padding
        
        videosCollectionHeightConstraint?.isActive = true
        videosCollectionHeightConstraint?.constant = totalHeight
        
        // Force layout update
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
        
        print("📐 ProfileViewController: Updated videos collection height to \(totalHeight) for \(videos.count) videos in \(numberOfRows) rows")
    }
    
    private func updateUploadsCollectionHeight() {
        // For 3-column grid layout, calculate height based on number of rows
        guard !uploads.isEmpty else {
            uploadsCollectionHeightConstraint?.constant = 100 // Minimum height for empty state
            return
        }
        
        // Calculate grid dimensions
        let spacing: CGFloat = 2
        let numberOfColumns: CGFloat = 3
        let totalSpacing = spacing * (numberOfColumns - 1)
        let collectionWidth = uploadsCollectionView.bounds.width > 0 ? uploadsCollectionView.bounds.width : UIScreen.main.bounds.width
        let itemWidth = (collectionWidth - totalSpacing) / numberOfColumns
        let itemHeight = itemWidth // Square items
        
        // Calculate number of rows
        let numberOfRows = ceil(Double(uploads.count) / Double(numberOfColumns))
        let totalRowSpacing = spacing * (CGFloat(numberOfRows) - 1)
        let totalHeight = (CGFloat(numberOfRows) * itemHeight) + totalRowSpacing + 20 // Add some padding
        
        uploadsCollectionHeightConstraint?.isActive = true
        uploadsCollectionHeightConstraint?.constant = totalHeight
        
        // Force layout update
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
        
        print("📐 ProfileViewController: Updated uploads collection height to \(totalHeight) for \(uploads.count) uploads in \(numberOfRows) rows")
    }
    
    // MARK: - Navigation Helpers
    
    private func navigateToPlaceDetail(from upload: UserUploadedPhoto) {
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Loading place details...", from: self)
        
        // Fetch complete global place data
        GlobalPlaceService.shared.getGlobalPlace(id: upload.placeId) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let globalPlaceResponse):
                        // Convert GlobalPlace to Place for PlaceDetailViewController
                        let legacyPlace = globalPlaceResponse.globalPlace.toLegacyPlace(withRelation: globalPlaceResponse.userRelation)
                        
                        let placeDetailVC = PlaceDetailViewController(place: legacyPlace)
                        self.navigationController?.pushViewController(placeDetailVC, animated: true)
                        
                    case .failure(let error):
                        print("❌ ProfileViewController: Failed to load place details: \(error)")
                        
                        // Fallback: Create minimal Place object and still navigate
                        let tempPlace = Place(
                            id: upload.placeId,
                            name: upload.placeName,
                            description: nil,
                            address: upload.placeAddress ?? "",
                            location: nil,
                            website: nil,
                            phone: nil,
                            googlePlaceId: nil,
                            photos: [upload.imageUrl],
                            videos: nil,
                            category: upload.placeCategory,
                            customCategoryId: nil,
                            subcategory: nil,
                            rating: nil,
                            userRatingsTotal: nil,
                            notes: nil,
                            privateNotes: nil,
                            publicNotes: nil,
                            tags: [],
                            reviews: nil,
                            openingHours: nil,
                            priceLevel: nil,
                            likes: nil,
                            likesCount: nil,
                            commentsCount: nil,
                            circleId: nil,
                            addedBy: "",
                            addedByUser: nil,
                            privacy: .followCirclePrivacy,
                            createdAt: upload.uploadedAt,
                            updatedAt: upload.uploadedAt,
                            isNew: false
                        )
                        
                        let placeDetailVC = PlaceDetailViewController(place: tempPlace)
                        self.navigationController?.pushViewController(placeDetailVC, animated: true)
                        
                        // Show error message as a toast
                        self.showError("Could not load complete place details")
                    }
                }
            }
        }
    }
    
    private func confirmDeleteVideo(_ video: PlaceVideo, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Content",
            message: "Are you sure you want to delete this \(video.contentType == "photo" ? "photo" : "video")? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteVideo(video, at: indexPath)
        })
        
        present(alert, animated: true)
    }
    
    private func deleteVideo(_ video: PlaceVideo, at indexPath: IndexPath) {
        // Show loading
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting...", from: self)
        
        APIService.shared.deleteVideo(videoId: video.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        // Clear video from cache
                        if let videoUrl = video.videoUrl {
                            MediaCacheService.shared.clearImage(for: videoUrl)
                        }
                        if let thumbnailUrl = video.thumbnailUrl {
                            MediaCacheService.shared.clearImage(for: thumbnailUrl)
                        }
                        if let previewUrl = video.previewUrl {
                            MediaCacheService.shared.clearImage(for: previewUrl)
                        }
                        
                        // Remove from array
                        self.videos.remove(at: indexPath.item)
                        
                        // Update collection view
                        self.videosCollectionView.deleteItems(at: [indexPath])
                        self.updateVideosCollectionHeight()
                        
                        // Update empty state
                        self.videosEmptyLabel.isHidden = !self.videos.isEmpty
                        
                        // Show success
                        self.showSuccess("Content deleted successfully")
                        
                        // Post notification for activity feed cleanup
                        NotificationCenter.default.post(
                            name: Notification.Name("MomentDeleted"),
                            object: nil,
                            userInfo: [
                                "videoId": video.id,
                                "userId": video.userId
                            ]
                        )
                        print("📢 Posted MomentDeleted notification for video: \(video.id)")
                        
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
    
    private func confirmDeleteUpload(_ upload: UserUploadedPhoto, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Photo",
            message: "Are you sure you want to delete this photo from \(upload.placeName)? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteUpload(upload, at: indexPath)
        })
        
        present(alert, animated: true)
    }
    
    private func deleteUpload(_ upload: UserUploadedPhoto, at indexPath: IndexPath) {
        // Show loading
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting photo...", from: self)
        
        GlobalPlaceService.shared.deleteUpload(upload) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        // Clear image from cache
                        ImageService.shared.clearCacheForUrl(upload.imageUrl)
                        
                        // Remove from local array
                        self.uploads.remove(at: indexPath.item)
                        
                        // Update collection view with animation
                        self.uploadsCollectionView.deleteItems(at: [indexPath])
                        self.updateUploadsCollectionHeight()
                        
                        // Show/hide empty state if needed
                        self.uploadsEmptyLabel.isHidden = !self.uploads.isEmpty
                        
                        // Show success
                        self.showSuccess("Photo deleted successfully")
                        
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
    
}

// MARK: - UICollectionViewDataSource
extension ProfileViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == videosCollectionView {
            return videos.count
        } else if collectionView == uploadsCollectionView {
            return uploads.count
        }
        return circles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == videosCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoThumbnailCell", for: indexPath) as! VideoThumbnailCell
            let video = videos[indexPath.item]
            cell.configure(with: video)
            return cell
        } else if collectionView == uploadsCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UploadThumbnailCell", for: indexPath) as! UploadThumbnailCell
            let upload = uploads[indexPath.item]
            cell.configure(with: upload)
            return cell
        }
        
        let circle = circles[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as! CircleCell
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == videosCollectionView {
            // Open full-screen reels viewer
            let reelsVC = VideoReelsViewController(reels: videos, startIndex: indexPath.item)
            reelsVC.modalPresentationStyle = .fullScreen
            present(reelsVC, animated: true)
        } else if collectionView == uploadsCollectionView {
            // Navigate to the place detail for the uploaded image
            let upload = uploads[indexPath.item]
            navigateToPlaceDetail(from: upload)
        } else {
            let circle = circles[indexPath.item]
            let detailVC = CircleDetailViewController(circle: circle)
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Handle context menu for videos
        if collectionView == videosCollectionView {
            let video = videos[indexPath.item]
            
            // Only show delete for user's own videos
            guard video.userId == AuthService.shared.getUserId() else { return nil }
            
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self = self else { return UIMenu(title: "", children: []) }
                
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self.confirmDeleteVideo(video, at: indexPath)
                }
                
                return UIMenu(title: "", children: [deleteAction])
            }
        } else if collectionView == uploadsCollectionView {
            // Handle context menu for uploads
            let upload = uploads[indexPath.item]
            
            // Only show delete for user's own uploads (they should always be the user's own uploads)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self = self else { return UIMenu(title: "", children: []) }
                
                let deleteAction = UIAction(
                    title: "Delete Photo",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self.confirmDeleteUpload(upload, at: indexPath)
                }
                
                return UIMenu(title: "", children: [deleteAction])
            }
        }
        
        // Handle context menu for circles
        let circle = circles[indexPath.item]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return UIMenu(title: "", children: []) }
            
            let editAction = UIAction(
                title: "Edit Circle",
                image: UIImage(systemName: "pencil")
            ) { _ in
                self.editCircle(circle)
            }
            
            let shareAction = UIAction(
                title: "Share Circle",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self.shareCircle(circle, from: indexPath)
            }
            
            let deleteAction = UIAction(
                title: "Delete Circle",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.deleteCircle(circle, at: indexPath)
            }
            
            return UIMenu(title: circle.name, children: [editAction, shareAction, deleteAction])
        }
    }
    
    private func editCircle(_ circle: Circle) {
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    private func shareCircle(_ circle: Circle, from indexPath: IndexPath) {
        var shareText = "🔵 \(circle.name)\n"
        
        if let description = circle.description, !description.isEmpty {
            shareText += "\(description)\n"
        }
        
        // Calculate member count from sharedWith and followers
        let memberCount = 1 + (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        shareText += "\n👥 \(memberCount) members"
        shareText += "\n📍 \(circle.places?.count ?? 0) places"
        
        // Add privacy info
        switch circle.privacy {
        case .public:
            shareText += "\n🌐 Public Circle"
        case .myNetwork:
            shareText += "\n👥 My Network"
        case .private:
            shareText += "\n🔒 Private Circle"
        }
        
        // Add deep link
        shareText += "\n\n📱 Open in Circles: circles://circle/\(circle.id)"
        shareText += "\n🔗 Get Circles App: https://apps.apple.com/us/app/favcircles/id6746807095"
        shareText += "\n\nJoin me on Circles!"
        
        let activityItems: [Any] = [shareText]
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad - set the source view for the popover
        if let popover = activityViewController.popoverPresentationController,
           let cell = circlesCollectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    private func deleteCircle(_ circle: Circle, at indexPath: IndexPath) {
        AlertPresenter.showConfirmation(
            title: "Delete Circle",
            message: "Are you sure you want to delete '\(circle.name)'? This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                
                CircleService.shared.deleteCircle(id: circle.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.didDeleteCircle(circle.id)
                        case .failure(let error):
                            self.showError("Failed to delete circle: \(error.localizedDescription)")
                        }
                    }
                }
            }
        )
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension ProfileViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == videosCollectionView {
            // Instagram-style 3-column grid with square items
            let spacing: CGFloat = 2
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            return CGSize(width: itemWidth, height: itemWidth) // Square items
        } else if collectionView == uploadsCollectionView {
            // Instagram-style 3-column grid with square items (same as videos)
            let spacing: CGFloat = 2
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            return CGSize(width: itemWidth, height: itemWidth) // Square items
        } else {
            // Circular grid with 3 columns
            let spacing: CGFloat = 12
            let numberOfColumns: CGFloat = 3
            let totalSpacing = spacing * (numberOfColumns - 1)
            let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
            let itemHeight = itemWidth + 50 // Extra height for labels below circles
            return CGSize(width: itemWidth, height: itemHeight)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return (collectionView == videosCollectionView || collectionView == uploadsCollectionView) ? 2 : 16
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return (collectionView == videosCollectionView || collectionView == uploadsCollectionView) ? 2 : 12
    }
}

// MARK: - CreateCircleDelegate
extension ProfileViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        circlesCollectionView.reloadData()
        updateCollectionViewHeight()
        
        // Update stats
        circlesStatView.configure(number: "\(circles.count)", title: "Circles")
    }
}

// MARK: - EditCircleDelegate
extension ProfileViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            circlesCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            circlesCollectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            updateCollectionViewHeight()
            
            // Update stats
            circlesStatView.configure(number: "\(circles.count)", title: "Circles")
        }
    }
}


// MARK: - UICollectionViewDragDelegate
extension ProfileViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard collectionView == circlesCollectionView else { return [] }
        
        // Only allow dragging for current user's own circles
        guard user?.id == AuthService.shared.getUserId() else { return [] }
        
        let circle = circles[indexPath.item]
        let itemProvider = NSItemProvider(object: circle.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = circle
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate
extension ProfileViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        guard collectionView == circlesCollectionView else { return false }
        return session.canLoadObjects(ofClass: NSString.self)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard collectionView == circlesCollectionView else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Only allow drops for current user's own profile
        guard user?.id == AuthService.shared.getUserId() else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Check what's being dragged (should be a circle)
        guard let dragItem = session.items.first,
              let _ = dragItem.localObject as? Circle else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        
        // Allow reordering
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
        // Clean up any visual feedback
        collectionView.visibleCells.forEach { cell in
            if let circleCell = cell as? CircleCell {
                circleCell.setDropTargetState(false)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
        // Final cleanup
    }
    
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath,
              let dragItem = coordinator.items.first,
              let sourceCircle = dragItem.dragItem.localObject as? Circle else {
            return
        }
        
        // Find the source index path
        guard let sourceIndexPath = circles.firstIndex(where: { $0.id == sourceCircle.id }).map({ IndexPath(item: $0, section: 0) }) else {
            return
        }
        
        // Perform the reorder
        handleReorder(from: sourceIndexPath, to: destinationIndexPath, coordinator: coordinator)
    }
    
    // MARK: - Drop Handling Methods
    
    private func handleReorder(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath, coordinator: UICollectionViewDropCoordinator) {
        // Safety check: only allow reordering for current user's own profile
        guard user?.id == AuthService.shared.getUserId() else {
            print("❌ ProfileViewController: Attempted to reorder for non-current user")
            return
        }
        
        // Perform the reorder
        circlesCollectionView.performBatchUpdates({
            // Update circles array
            let movedCircle = circles.remove(at: sourceIndexPath.item)
            circles.insert(movedCircle, at: destinationIndexPath.item)
            
            // Move the item in the collection view
            circlesCollectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
        }) { [weak self] _ in
            // Save the new order to the backend
            self?.saveCircleOrder()
        }
        
        // Handle the drop
        if let dragItem = coordinator.items.first?.dragItem {
            coordinator.drop(dragItem, toItemAt: destinationIndexPath)
        }
    }
    
    private func reorderItems(coordinator: UICollectionViewDropCoordinator, destinationIndexPath: IndexPath, collectionView: UICollectionView) {
        if let item = coordinator.items.first,
           let sourceIndexPath = item.sourceIndexPath {
            
            collectionView.performBatchUpdates({
                // Update the data model
                let movedCircle = circles.remove(at: sourceIndexPath.item)
                circles.insert(movedCircle, at: destinationIndexPath.item)
                
                // Update the collection view
                collectionView.deleteItems(at: [sourceIndexPath])
                collectionView.insertItems(at: [destinationIndexPath])
            }) { [weak self] _ in
                // Save the new order to the backend
                self?.saveCircleOrder()
            }
            
            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
        }
    }
    
    private func saveCircleOrder() {
        // Safety check: only allow saving for current user
        guard user?.id == AuthService.shared.getUserId() else {
            print("❌ ProfileViewController: Attempted to save circle order for non-current user")
            return
        }
        
        // Extract the circle IDs in their new order
        let circleIds = circles.map { $0.id }
        
        // Call the API to save the new order
        UserService.shared.reorderCircles(circleIds: circleIds) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("Failed to save circle order: \(error)")
                // Optionally reload circles to restore original order
                self.loadUserCircles()
            } else {
                print("Circle order saved successfully")
            }
        }
    }
    
    private func loadUserCircles() {
        guard let userId = user?.id else { return }
        
        // Fetch circles (same logic as in fetchUserStats)
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let circles):
                    self.circles = circles
                    self.circlesStatView.configure(number: "\(circles.count)", title: "Circles")
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                    
                    // Load all places for search functionality
                    self.loadAllPlacesFromCircles(circles)
                case .failure:
                    self.circles = []
                    self.allPlaces = []
                    self.circlesStatView.configure(number: "0", title: "Circles")
                    self.circlesCollectionView.reloadData()
                    self.updateCollectionViewHeight()
                }
            }
        }
    }
    
    private func removeDuplicatePlaces(_ places: [Place]) -> [Place] {
        var seenPlaceIds = Set<String>()
        var deduplicatedPlaces: [Place] = []
        var duplicatesFound = 0
        
        for place in places {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                duplicatesFound += 1
                print("🔍 ProfileViewController - Skipping duplicate place: '\(place.name)' (ID: \(place.id))")
            }
        }
        
        if duplicatesFound > 0 {
            print("⚠️ ProfileViewController - Found and removed \(duplicatesFound) duplicate places")
        }
        
        return deduplicatedPlaces
    }
    
    private func loadAllPlacesFromCircles(_ circles: [Circle]) {
        print("🔍 [Places Debug] loadAllPlacesFromCircles called with \(circles.count) circles")
        allPlaces.removeAll()
        let dispatchGroup = DispatchGroup()
        
        for circle in circles {
            print("🔍 [Places Debug] Loading places for circle: \(circle.name) (id: \(circle.id))")
            dispatchGroup.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
                guard let self = self else { 
                    dispatchGroup.leave()
                    return 
                }
                
                switch result {
                case .success(let places):
                    print("🔍 [Places Debug] Loaded \(places.count) places from circle: \(circle.name)")
                    DispatchQueue.main.async {
                        self.allPlaces.append(contentsOf: places)
                    }
                case .failure(let error):
                    print("⚠️ [Places Debug] Failed to fetch places for circle \(circle.name): \(error)")
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            print("🔍 [Places Debug] All circles processed, total raw places: \(self.allPlaces.count)")
            
            // Log some sample places and their categories
            if !self.allPlaces.isEmpty {
                print("🔍 [Places Debug] Sample places and categories:")
                for (index, place) in self.allPlaces.prefix(3).enumerated() {
                    print("  \(index + 1). \(place.name) - Category: \(place.category.rawValue), Custom: \(place.customCategoryId ?? "none")")
                }
            }
            
            // Deduplicate places that might exist in multiple circles
            let deduplicatedPlaces = self.removeDuplicatePlaces(self.allPlaces)
            self.allPlaces = deduplicatedPlaces
            
            // Update available categories based on loaded places
            self.updateAvailableCategories()
            
            print("🔍 ProfileViewController - Loaded \(self.allPlaces.count) total unique places for search (after deduplication)")
            // Update map with all places by default
            self.filterPlaces()
        }
    }
    
    private func updateAvailableCategories() {
        print("🔍 [Categories Debug] updateAvailableCategories called with \(allPlaces.count) places")
        
        // Get unique categories from all places, including custom categories
        availableCategories = PlaceCategory.uniqueCategories(from: allPlaces)
        
        print("🔍 [Categories Debug] Found \(availableCategories.count) unique categories:")
        for (index, category) in availableCategories.enumerated() {
            print("  \(index + 1). \(category.displayName) (\(category.isCustom ? "custom" : "standard"))")
        }
        
        // The hamburger chip's menu rebuilds itself on every open, so no
        // explicit menu refresh is needed here
    }
}


// MARK: - SSEServiceDelegate
extension ProfileViewController: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        guard let currentUserId = AuthService.shared.getUserId(),
              let userId = user?.id,
              userId == currentUserId else {
            // Only update stats for current user's profile
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch event.type {
            case .followerAdded, .followerRemoved:
                if let followersCount = event.data["followersCount"] as? Int {
                    self.followersStatView.configure(number: "\(followersCount)", title: "Followers")
                }
            case .followingAdded, .followingRemoved:
                print("🔔 SSE Event: \(event.type) - Data: \(event.data)")
                let followingCount = event.data["followingCount"] as? Int
                if let followingCount = followingCount {
                    self.followingStatView.configure(number: "\(followingCount)", title: "Following")
                }
                // Update the cached current user's following array
                if let following = event.data["following"] as? [String],
                   var currentUser = AuthService.shared.currentUser {
                    // Create updated user with new following array
                    let updatedUser = currentUser.copy(
                        following: following,
                        followingCount: followingCount ?? currentUser.followingCount
                    )
                    AuthService.shared.updateCurrentUser(updatedUser)
                    
                    // Only re-check follow status if we're viewing someone else's profile
                    // (not when we just clicked follow/unfollow)
                    if self.user?.id != currentUserId {
                        self.checkConnectionAndFollowStatus()
                    }
                }
            default:
                break
            }
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
    }
}

// MARK: - MKMapViewDelegate
extension ProfileViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }
        
        guard let placeAnnotation = annotation as? PlaceAnnotation else {
            return nil
        }
        
        let identifier = "PlaceAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            
            // Add detail button
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
        }
        
        // Customize marker appearance based on category
        if let markerView = annotationView {
            markerView.markerTintColor = placeAnnotation.place.category.color
            markerView.glyphImage = UIImage(systemName: placeAnnotation.place.category.systemIconName)
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { return }
        
        // Navigate to place detail view
        let placeDetailVC = PlaceDetailViewController(place: placeAnnotation.place)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
}

// MARK: - UISearchBarDelegate
extension ProfileViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBar(searchBar, textDidChange: searchText)
        // Update collection view to show/hide content during search
        circlesCollectionView.reloadData()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation  
        (self as PlaceSearchable).searchBarCancelButtonClicked(searchBar)
        // Update collection view after clearing search
        circlesCollectionView.reloadData()
        // Ensure keyboard is dismissed
        view.endEditing(true)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarSearchButtonClicked(searchBar)
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarTextDidBeginEditing(searchBar)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarTextDidEndEditing(searchBar)
    }
}

// MARK: - PlaceSearchable Navigation
extension ProfileViewController {
    func navigateToPlace(_ place: Place) {
        // Find the circle this place belongs to
        guard let circle = circles.first(where: { $0.id == place.circleId }) else {
            print("⚠️ Could not find circle for place: \(place.name)")
            return
        }
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate for Search Results
extension ProfileViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == searchResultsTableView {
            return numberOfRowsInSearchResults()
        }
        if tableView == mapPlacesListTableView {
            return mapDistanceSortedPlaces.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            configureSearchResultCell(cell, at: indexPath)
            return cell
        }
        if tableView == mapPlacesListTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProfilePlaceListCell", for: indexPath) as! QuickAccessPlaceCell
            guard indexPath.row < mapDistanceSortedPlaces.count else { return cell }
            let entry = mapDistanceSortedPlaces[indexPath.row]
            let distanceText = entry.distance.map { mapListDistanceFormatter.string(fromDistance: $0) }
            cell.configure(with: entry.place, isSelected: false, distanceText: distanceText)
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == searchResultsTableView {
            handleSearchResultSelection(at: indexPath)
        }
        if tableView == mapPlacesListTableView {
            tableView.deselectRow(at: indexPath, animated: true)
            guard indexPath.row < mapDistanceSortedPlaces.count else { return }
            // Same destination as tapping a pin's callout on this map
            let placeDetailVC = PlaceDetailViewController(place: mapDistanceSortedPlaces[indexPath.row].place)
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension ProfileViewController {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        controller.dismiss(animated: true) {
            let placeDetailVC = PlaceDetailViewController(place: place)
            self.navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}

// MARK: - ContentUploadDelegate
extension ProfileViewController: ContentUploadDelegate {
    func contentUploadDidFinish(with moment: PlaceMoment) {
        showSuccess("Moment shared successfully!")
        
        // Refresh videos/moments if on Moments tab
        if contentTypeSegmentedControl.selectedSegmentIndex == 1 {
            fetchUserVideos() // This will reload the moments collection
        }
        
        // Track activity
        NotificationCenter.default.post(
            name: Notification.Name("MomentUploaded"),
            object: nil,
            userInfo: ["moment": moment]
        )
        
        // Navigate to home tab to show the new moment in the feed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Find the tab bar controller and switch to home tab
            if let tabBarController = self?.tabBarController {
                print("🏠 Navigating to home tab after successful moment upload")
                tabBarController.selectedIndex = 0 // Home tab is index 0
            } else if let navController = self?.navigationController,
                      let tabBarController = navController.tabBarController {
                print("🏠 Navigating to home tab via nav controller after successful moment upload")
                tabBarController.selectedIndex = 0
            } else {
                print("⚠️ Could not find tab bar controller for navigation")
            }
        }
    }
    
    func contentUploadDidCancel() {
        // User cancelled - nothing to do
    }
}

