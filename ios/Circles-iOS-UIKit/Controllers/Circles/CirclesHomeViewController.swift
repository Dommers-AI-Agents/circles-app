import UIKit
import CoreLocation
import UniformTypeIdentifiers
import MapKit
import AVFoundation
import SafariServices

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Response Types
struct CirclesDataResponse: Codable {
    let success: Bool
    let data: [Circle]
}

// MARK: - Search Scope
enum SearchScope: CaseIterable {
    case myPlaces
    case networkPlaces
    
    var title: String {
        switch self {
        case .myPlaces:
            return "Search your places"
        case .networkPlaces:
            return "Search all places in your network"
        }
    }
    
    var placeholder: String {
        switch self {
        case .myPlaces:
            return "Search your places..."
        case .networkPlaces:
            return "Search network places..."
        }
    }
}

// MARK: - Enhanced Home Screen Data Models
struct EnhancedHomeScreenData: Codable {
    let success: Bool
    let data: HomeScreenContent
}

struct HomeScreenContent: Codable {
    let myCircles: [Circle]
    let networkCircles: [Circle]
    let activities: [Activity]
    let userList: [UserListItem]
    let mapData: MapData?
    let stats: HomeScreenStats

    init(myCircles: [Circle], networkCircles: [Circle], activities: [Activity],
         userList: [UserListItem], mapData: MapData?, stats: HomeScreenStats) {
        self.myCircles = myCircles
        self.networkCircles = networkCircles
        self.activities = activities
        self.userList = userList
        self.mapData = mapData
        self.stats = stats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.myCircles = try container.decode(LossyDecodableArray<Circle>.self, forKey: .myCircles).elements
        self.networkCircles = try container.decode(LossyDecodableArray<Circle>.self, forKey: .networkCircles).elements
        // Lossy + drop unknown types: one malformed or unrecognized activity
        // must not blank the whole feed
        self.activities = try container.decode(LossyDecodableArray<Activity>.self, forKey: .activities).elements
            .filter { $0.type != .unknown }
        self.userList = try container.decode(LossyDecodableArray<UserListItem>.self, forKey: .userList).elements
        self.mapData = try container.decodeIfPresent(MapData.self, forKey: .mapData)
        self.stats = try container.decode(HomeScreenStats.self, forKey: .stats)
    }
}

struct UserListItem: Codable {
    let _id: String
    let displayName: String
    let profileImageUrl: String?
    let isOnline: Bool
}

struct MapData: Codable {
    let places: [MapPlace]
    let center: MapCoordinate
    let bounds: MapBounds?
}

struct MapPlace: Codable {
    let _id: String
    let name: String
    let coordinates: MapCoordinate
    let circleId: String
    let imageUrl: String?
    let category: String?
}

struct MapCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct MapBounds: Codable {
    let north: Double
    let south: Double
    let east: Double
    let west: Double
}

struct HomeScreenStats: Codable {
    let totalCircles: Int
    let totalPlaces: Int
    let totalActivities: Int
    let totalUsers: Int?
    let mapPlaces: Int?
    let loadTimeMs: Int
}

// Response type for the fast homescreen API endpoint
struct HomeScreenResponse: Codable {
    let success: Bool
    let data: HomeScreenData?
}

struct HomeScreenData: Codable {
    let userList: [UserListItem]?
    let recentActivities: [Activity]?
    let stats: FastAPIStats?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userList = (try? container.decode(LossyDecodableArray<UserListItem>.self, forKey: .userList))?.elements
        self.recentActivities = (try? container.decode(LossyDecodableArray<Activity>.self, forKey: .recentActivities))?.elements
            .filter { $0.type != .unknown }
        self.stats = try container.decodeIfPresent(FastAPIStats.self, forKey: .stats)
    }
}

struct FastAPIStats: Codable {
    let loadTimeMs: Int?
    let totalUsers: Int?
    let totalActivities: Int?
    let source: String?
}

// MARK: - Progressive Loading Stages
enum ProgressiveLoadingStage {
    case userListLoaded
    case activitiesLoaded
    case mapDataLoaded
    case allDataLoaded
}

// MARK: - Optimized Cache System
class HomeScreenCache {
    var cachedData: HomeScreenContent?
    var cacheExpiry: Date?
    let cacheValidityMinutes: TimeInterval = 3 // 3 minutes for memory cache
    
    var isValid: Bool {
        guard let expiry = cacheExpiry else { return false }
        return Date() < expiry
    }
    
    func store(_ data: HomeScreenContent) {
        // Store in memory
        cachedData = data
        cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
        Logger.debug("📦 [Memory Cache] Stored home screen data, valid until \(cacheExpiry!)")
        
        // Store in disk cache for longer persistence
        CacheService.shared.cacheHomeScreenData(data)
    }
    
    func retrieve() -> HomeScreenContent? {
        // First try memory cache
        if isValid, let data = cachedData {
            Logger.debug("📦 [Memory Cache] Retrieved valid cached data")
            return data
        }
        
        // Try disk cache as fallback
        if let diskData = CacheService.shared.getCachedHomeScreenData(maxAgeMinutes: 10) {
            Logger.debug("📦 [Disk Cache] Retrieved valid cached data from disk")
            // Store in memory for next access
            cachedData = diskData
            cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
            return diskData
        }
        
        Logger.debug("📦 [Cache] No valid cache found")
        cachedData = nil
        cacheExpiry = nil
        return nil
    }
    
    func invalidate() {
        cachedData = nil
        cacheExpiry = nil
        Logger.debug("📦 [Cache] Memory cache invalidated")
        // Note: Disk cache remains for offline scenarios
    }
}

class CirclesHomeViewController: BaseViewController, PlaceSearchable, SSEServiceDelegate {
    
    // MARK: - Properties
    var circles: [Circle] = []
    var networkCircles: [Circle] = []
    var isShowingNetworkCircles = false
    var allPlaces: [Place] = []
    var filteredPlaces: [Place] = []
    var isSearching = false
    var selectedCategory: UnifiedCategory?
    var mapUpdateTimer: Timer? // Debounce timer for map updates
    var notificationBadgeTimer: Timer? // Periodic refresh timer for notification badge
    var isReturningFromFullScreenMap = false // Prevent map updates when returning from full screen
    var isLoadingCircles = false // Track when circles are being loaded
    var isLoadingPlaces = false // Track when places are being loaded
    var isPerformingInitialLoad = false // Track if we're in the middle of initial loading
    var isShowingLoadingUI = false // Track if loading UI is currently shown
    static var hasLoadedInitialData = false // Track if we've loaded data at least once this session
    var hasStartedLoading = false // Instance flag to prevent multiple loads in the same instance
    var isMapDataReady = false // Track if map data is ready to be displayed
    
    // MARK: - Place Detail Deduplication Properties
    var lastPresentedPlaceId: String?
    var lastPresentationTime: TimeInterval = 0
    let presentationDebounceInterval: TimeInterval = 1.0 // 1 second to prevent double-taps
    
    // MARK: - Enhanced Performance Properties
    var optimizedCache: HomeScreenCache = HomeScreenCache()
    var isUsingFastLoad = false // Track if we're using optimized fast loading
    var skeletonLoadingView: HomeScreenSkeletonView? // Progressive loading skeleton
    
    // Instance-based cache with expiry
    var placesCacheExpiry: Date?
    var cachedPlaces: [Place] = []
    var userOwnPlaces: [Place] = [] { // Separate array for user's own places only
        didSet {
            // Keep the embedded map informed so it can center on the user's favorites
            mapViewController?.ownPlaceIds = Set(userOwnPlaces.map { $0.id })
        }
    }
    
    // MARK: - Helper Methods
    /// Helper function to create a type-safe completion handler for API requests
    func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
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
    let cacheExpiryMinutes: TimeInterval = 5 // 5 minutes cache expiry
    var loadDebounceTimer: Timer? // Debounce timer to prevent rapid successive loads
    var preloadedData: PreloadedData? // Store preloaded data from splash screen
    var preloadedConnections: [Connection]? // Store preloaded connections for userListView
    var notificationBadgeLabel: UILabel? // Badge label for notification count
    var notificationBarButton: UIBarButtonItem? // Store reference to notification button
    var rewardsBadgeLabel: UILabel? // Badge label showing reward points balance
    var rewardsBarButton: UIBarButtonItem? // Store reference to rewards ($) button
    
    // Search scope properties
    var currentSearchScope: SearchScope = .myPlaces
    var networkPlaces: [Place] = [] // Cache for network places
    var isLoadingNetworkPlaces = false

    // Unified search: places (local, instant) + people (server, debounced).
    // People results are the PEOPLE section of the search overlay; tapping one
    // filters the map to a connection/followee, or opens a stranger's profile.
    var searchedUsers: [User] = []
    var userSearchWorkItem: DispatchWorkItem?

    // MARK: - Viewport-Based Network Place Loading
    // When true, network places load on demand for the visible map region
    // instead of the per-circle fan-out. Flip to false to restore old behavior.
    let useViewportNetworkLoading = true
    var fetchedViewportCircles: [(center: CLLocationCoordinate2D, radiusM: Double)] = []
    var isFetchingViewport = false
    
    // Suggested users overlay
    var suggestedUsersOverlay: SuggestedUsersOverlayView?
    var visitTrackingPermissionOverlay: VisitTrackingPermissionView?
    var addPlaceTutorialOverlay: AddFirstPlaceTutorialView?
    
    // Welcome tour tracking
    var isShowingWelcomeTour = false
    
    // Reaction picker tracking
    var currentReactionActivity: Activity?
    
    // MARK: - BaseViewController Configuration (DISABLED for debugging)
    override var loadsDataOnViewDidLoad: Bool { false } // Disable auto-loading to prevent conflicts
    override var reloadsDataOnAppear: Bool { false } // We handle this manually
    override var showsLoadingIndicator: Bool { false } // We have custom loading UI
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // Define response structure for network circles
    struct NetworkCirclesResponse: Codable {
        let success: Bool
        let data: [Circle]
    }
    
    // MARK: - UI Elements
    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = Constants.Colors.background
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()
    
    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.background
        return view
    }()
    
    let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search places and people"
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    let searchScopeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let searchScopeDropdownView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 8
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let searchScopeTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.layer.cornerRadius = 8
        tableView.isScrollEnabled = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // Quick-access bar (Home / Places / Work cards) removed from the home page —
    // it added visual weight above the map and connections without earning it.
    
    let filterContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let userListView: HorizontalUserListView = {
        let view = HorizontalUserListView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    let emptyStateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.dashed")
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "You don't have any circles yet"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Direct CTAs so a brand-new user can act from the empty state
    lazy var emptyStateButtonsStack: UIStackView = {
        let addButton = UIButton.smallActionButton(title: "Add Your Places", style: .primary)
        addButton.addTarget(self, action: #selector(openQuickStartAddPlaces), for: .touchUpInside)

        let findButton = UIButton.smallActionButton(title: "Find Friends", style: .secondary)
        findButton.addTarget(self, action: #selector(emptyStateFindFriendsTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [addButton, findButton])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    
    let quickAddPlaceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.setTitle(" Add Place", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = Constants.Colors.primary
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addShadow(opacity: 0.2, radius: 5, offset: CGSize(width: 0, height: 2))
        return button
    }()
    
    
    let mapContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = false
        return view
    }()
    
    let mapLoadingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()
    
    let mapLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        indicator.layer.cornerRadius = 20
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    let mapLoadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Loading your places..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let mapLoadingProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = Constants.Colors.primary
        progressView.trackTintColor = Constants.Colors.primary.withAlphaComponent(0.2)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        progressView.progress = 0.0
        return progressView
    }()
    
    let mapExpandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let mapPlaceCountLabel: UIButton = {
        let button = UIButton(type: .custom)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.isUserInteractionEnabled = false
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    var mapViewController: FullScreenMapViewController?
    // The modally-presented full map (weak: auto-clears on dismissal). Data
    // refreshes must reach it too, not just the embedded child above.
    weak var presentedFullScreenMap: FullScreenMapViewController?
    
    let filterStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = false
        return stack
    }()
    
    lazy var mapMenuButton: UIButton = {
        let button = UIButton.iconButton(systemName: "line.3.horizontal", pointSize: 15)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self = self else {
                    completion([])
                    return
                }
                completion(self.buildMapMenuElements())
            }
        ])
        return button
    }()

    // Toggles between the map and a distance-sorted list of the same places
    lazy var listToggleButton: UIButton = {
        let button = UIButton.iconButton(systemName: "list.bullet", pointSize: 15)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.addTarget(self, action: #selector(listToggleTapped), for: .touchUpInside)
        return button
    }()

    lazy var placesListTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.secondaryBackground
        tableView.separatorStyle = .none
        tableView.isHidden = true
        // Start content below the floating filter chips (12pt inset + 36pt chips + 8pt gap)
        tableView.contentInset = UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)
        tableView.register(QuickAccessPlaceCell.self, forCellReuseIdentifier: "HomePlaceListCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    var isShowingPlacesList = false
    var distanceSortedPlaces: [(place: Place, distance: CLLocationDistance?)] = []
    let listDistanceFormatter = MKDistanceFormatter()

    lazy var myPlacesToggleButton: UIButton = {
        // Icon stacked over a "Me" label, matching the main navigation's profile tab
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
        button.addTarget(self, action: #selector(myPlacesToggleTapped), for: .touchUpInside)
        return button
    }()

    var selectedConnectionId: String? = nil // Default to All Connections
    var selectedConnectionUser: User? = nil // Set only when a specific connection is filtered

    /// Whose places are on the map: the selected connection's avatar shown as
    /// the first chip beside the map controls (hidden when no connection
    /// filter is active). Tapping opens their profile.
    lazy var selectedConnectionAvatarButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.clipsToBounds = true
        button.imageView?.contentMode = .scaleAspectFill
        button.tintColor = Constants.Colors.primary
        button.isHidden = true
        button.accessibilityLabel = "Selected connection"
        button.addTarget(self, action: #selector(selectedConnectionAvatarTapped), for: .touchUpInside)
        return button
    }()

    func updateSelectedConnectionAvatar() {
        guard let user = selectedConnectionUser,
              let id = selectedConnectionId, id != "my_places_only" else {
            selectedConnectionAvatarButton.isHidden = true
            return
        }
        selectedConnectionAvatarButton.isHidden = false
        selectedConnectionAvatarButton.setImage(UIImage(systemName: "person.crop.circle.fill"), for: .normal)
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            let expectedUserId = user.id
            ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: "profile_\(user.id)_\(profilePicture)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, let image = image,
                          self.selectedConnectionUser?.id == expectedUserId else { return }
                    self.selectedConnectionAvatarButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                }
            }
        }
    }

    @objc func selectedConnectionAvatarTapped() {
        guard let user = selectedConnectionUser else { return }
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    // Search results table view
    let searchResultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Constants.Colors.background
        tableView.layer.cornerRadius = 12
        tableView.layer.shadowColor = UIColor.black.cgColor
        tableView.layer.shadowOpacity = 0.15
        tableView.layer.shadowOffset = CGSize(width: 0, height: 4)
        tableView.layer.shadowRadius = 8
        tableView.isHidden = true
        tableView.alpha = 0
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        return tableView
    }()
    
    var searchResultsHeightConstraint: NSLayoutConstraint?
    
    let locationStatusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Loading places..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let loadingContentView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let loadingContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    var availableCategories: [UnifiedCategory] = []
    var mapHeightConstraint: NSLayoutConstraint?
    
    // Search scope dropdown properties
    var isSearchScopeDropdownOpen = false
    var searchScopeDropdownHeightConstraint: NSLayoutConstraint?
    
    // Activity Feed Properties
    // Any mutation re-derives the grouped feed rows — several load paths
    // (cache apply, fast-path load) reload the table without going through
    // updateActivityFeed(), and the table renders from feedItems
    var activities: [Activity] = [] {
        didSet { regroupActivities() }
    }
    var isLoadingActivities = false
    var activityTableHeightConstraint: NSLayoutConstraint?
    
    // Daily Summary Properties
    var dailySummaryCard: DailySummaryCardView?
    var hasDailySummaryData = false
    
    // Reels Properties
    var reels: [PlaceVideo] = []
    var isLoadingReels = false
    var reelsOffset = 0
    var hasMoreReels = true
    var isLoadingMoreReels = false
    
    // Suggested Users Overlay
    var hasCheckedForSuggestedUsers = false
    var hasCheckedTutorialAndOverlay = false
    var tutorialCheckRetryCount = 0
    let maxTutorialCheckRetries = 3
    
    // Pagination properties
    var currentOffset = 0
    var hasMoreActivities = true
    var isLoadingMoreActivities = false
    
    // Activity Feed UI Elements
    let activityFeedSection: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let activityHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "Recent Activity"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Segmented control for Activity/Moments/Specials tabs
    let contentSegmentedControl: UISegmentedControl = {
        let items = ["Activity", "Moments", "Specials"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    // Camera button for Moments tab
    let momentsCameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = Constants.Colors.primary
        button.tintColor = .white
        button.setImage(UIImage(systemName: "video.fill"), for: .normal)
        button.layer.cornerRadius = 28
        button.isHidden = true // Hidden by default, shown when Moments tab is selected
        button.translatesAutoresizingMaskIntoConstraints = false
        // Add shadow for better visibility over the segment
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 3
        return button
    }()
    
    let activityTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.isScrollEnabled = true // Enable scrolling for proper display
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    // Specials tab: live offers and announcements from participating venues,
    // one row per deal in the server's order (saved venues first, then nearest)
    let specialsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.isHidden = true // Hidden until the Specials tab is selected
        return tableView
    }()

    var specials: [SpecialItem] = []
    var isLoadingSpecials = false

    // Reels collection view for vertical video feed
    let reelsCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never // Use .never for full-screen video display like VideoReelsViewController
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isHidden = true // Hidden by default
        return collectionView
    }()
    
    // Track current video index for auto-play
    var currentReelIndex = 0
    var reelPlayers: [Int: AVPlayer] = [:]
    
    // Track video loading states to prevent index misalignment
    enum VideoLoadState {
        case notLoaded
        case loading
        case ready
        case failed
    }
    var reelVideoStates: [Int: VideoLoadState] = [:]
    
    let activityEmptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No recent activity from your network"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    let activityLoadingContainer: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        container.layer.cornerRadius = 12
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.1
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Add loading indicator as subview
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = false
        container.addSubview(indicator)
        
        // Center indicator in container
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        // Store reference to indicator for later access
        container.tag = 999 // Use tag to retrieve indicator later
        
        return container
    }()
    
    var activityLoadingIndicator: UIActivityIndicatorView {
        // Get the indicator from the container using the tag
        return activityLoadingContainer.subviews.first(where: { $0 is UIActivityIndicatorView }) as? UIActivityIndicatorView ?? UIActivityIndicatorView()
    }
    
    // Floating record button for Reels tab
    let floatingRecordButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = Constants.Colors.primary
        button.tintColor = .white
        button.setImage(UIImage(systemName: "video.fill"), for: .normal)
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true // Hidden by default, shown only on Reels tab
        return button
    }()
    
    let loadMoreIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = Constants.Colors.primary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        return view
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Logger.debug("🟡 CirclesHomeViewController viewDidLoad called")
        Logger.debug("🟡 Instance: \(ObjectIdentifier(self))")
        
        setupUI()
        setupNavigationBar()
        setupNotifications()
        setupSearchBar()
        setupDropdownViews()
        
        // Setup user list delegate
        userListView.delegate = self
        
        // Setup SSE delegate
        SSEService.shared.addDelegate(self)
        
        // Configure reels collection view layout
        if let flowLayout = reelsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.scrollDirection = .vertical
            flowLayout.minimumInteritemSpacing = 0
            flowLayout.minimumLineSpacing = 0
            flowLayout.sectionInset = .zero
            // Don't set item size here - let the delegate method handle it
        }
        
        // Keep map container visible but show loading overlay
        // This prevents the black screen issue
        mapContainerView.isHidden = false
        filterStackView.isHidden = true
        filterContainer.isHidden = true
        mapExpandButton.isHidden = true
        
        // Don't hide the map initially - show it immediately
        mapLoadingView.isHidden = true
        
        // Don't load connections here - will be handled in viewWillAppear
        // This prevents loading connections before checking for preloaded data
        
        // Don't show loading state here - let fetchCircles handle it
        // The loading will be shown when fetchAllPlacesFromCircles is called
        
        // Start with empty state hidden until data loads
        emptyStateView.isHidden = true
        
        // Hide activity loading container initially - will be shown when fetchActivities is called
        activityLoadingContainer.isHidden = true
        
        // Store cached places but don't display them yet
        // Wait for circles to load before displaying any places to ensure consistency
        if !cachedPlaces.isEmpty {
            Logger.debug("🟡 Found cached places: \(cachedPlaces.count) - storing for later display")
            self.allPlaces = cachedPlaces
            // Note: userOwnPlaces will be populated later when circles are loaded
        }
        // Don't show loading state here - performInitialDataLoad will handle it
        
        // Don't fetch circles here - it will be called in viewWillAppear
        
        // Step 2: Start background image preloading for better performance
        startBackgroundImagePreloading()
    }
    
    deinit {
        // Clean up timers
        mapUpdateTimer?.invalidate()
        loadDebounceTimer?.invalidate()
        notificationBadgeTimer?.invalidate()
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        // Remove SSE delegate
        SSEService.shared.removeDelegate(self)
        // Reset loading flag if this instance was loading
        if isPerformingInitialLoad {
            isPerformingInitialLoad = false
        }
    }
    
    // MARK: - Enhanced Data Loading (BaseViewController Override) - DISABLED
    // Temporarily disabled to restore original loading behavior
    /*
    override func loadData(completion: (() -> Void)? = nil) {
        Logger.debug("⚡ [Enhanced] loadData called - attempting optimized loading")
        
        // Show progressive skeleton loading immediately
        showProgressiveSkeletonLoading()
        
        // Check cache first for ultra-fast loading
        if let cachedContent = optimizedCache.retrieve() {
            Logger.debug("⚡ [Cache Hit] Using cached data for instant loading")
            isUsingFastLoad = true
            applyHomeScreenData(cachedContent)
            hideProgressiveSkeletonLoading()
            completion?()
            return
        }
        
        // Try fast homescreen API for immediate display data
        loadHomeScreenDataFast { [weak self] success in
            guard let self = self else { return }
            
            if success {
                Logger.debug("⚡ [Fast API] Successfully loaded via homescreen endpoint")
                self.isUsingFastLoad = true
                self.hideProgressiveSkeletonLoading()
                
                // Background load full data for completeness
                DispatchQueue.global(qos: .background).async {
                    self.loadFullDashboardData()
                }
            } else {
                Logger.debug("⚡ [Fallback] Fast API failed, using full dashboard")
                self.loadFullDashboardData()
            }
            
            completion?()
        }
    }
    */
    
    // MARK: - Safe Cache Optimization (Step 1)
    func tryLoadFromCache() {
        // Only try cache if we haven't started loading yet
        guard !hasStartedLoading && circles.isEmpty else { 
            Logger.debug("📦 [SafeCache] Skipping - already loading or have data")
            return 
        }
        
        // Check if we have cached data
        if let cachedContent = optimizedCache.retrieve() {
            Logger.debug("📦 [SafeCache] Found cached data - applying as background enhancement")
            
            // Apply cached circles and places for immediate map population
            if !cachedContent.myCircles.isEmpty && circles.isEmpty {
                self.circles = cachedContent.myCircles
                self.networkCircles = cachedContent.networkCircles
                Logger.debug("📦 [SafeCache] Applied \(cachedContent.myCircles.count) cached circles")
                
                // Extract places from cached circles for immediate map display
                extractAndShowCachedPlaces()
            }
            
            // Apply cached activities to show something immediately
            if !cachedContent.activities.isEmpty && activities.isEmpty {
                self.activities = cachedContent.activities
                DispatchQueue.main.async {
                    self.activityTableView.reloadData()
                    // Hide optional skeleton since we have data
                    self.hideOptionalSkeletonLoading()
                }
                Logger.debug("📦 [SafeCache] Applied \(cachedContent.activities.count) cached activities")
            }
            
            // Start background image preloading
            DispatchQueue.global(qos: .background).async {
                self.preloadImagesFromCache(cachedContent)
            }
        }
    }
    
    func preloadImagesFromCache(_ data: HomeScreenContent) {
        var imageUrls: [String] = []
        
        // Collect user profile images
        imageUrls.append(contentsOf: data.userList.compactMap { $0.profileImageUrl })
        
        // Collect activity-related images
        for activity in data.activities {
            if let actor = activity.actor, let profilePicture = actor.profilePicture {
                if !profilePicture.starts(with: "sf-symbol:") {
                    imageUrls.append(profilePicture)
                }
            }
        }
        
        let uniqueUrls = Array(Set(imageUrls))
        
        guard !uniqueUrls.isEmpty else { return }
        
        Logger.debug("📦 [SafeCache] Preloading \(uniqueUrls.count) images in background")
        
        CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
            Logger.debug("📦 [SafeCache] Preloaded \(loadedCount)/\(uniqueUrls.count) images")
        }
    }
    
    // MARK: - Background Image Preloading (Step 2)
    func startBackgroundImagePreloading() {
        DispatchQueue.global(qos: .background).async {
            // Check if we have any data to preload from
            if !self.allPlaces.isEmpty {
                self.preloadPlaceImages()
            }
            
            // Clean up expired cache periodically
            CacheService.shared.cleanExpiredCache()
        }
    }
    
    func preloadPlaceImages() {
        let imageUrls = allPlaces.compactMap { place in
            // Extract first photo URL from Place model
            return place.photos?.first
        }
        
        let uniqueUrls = Array(Set(imageUrls))
        
        guard !uniqueUrls.isEmpty else { return }
        
        Logger.debug("🖼️ [BackgroundPreload] Starting preload of \(uniqueUrls.count) place images")
        
        CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
            Logger.debug("🖼️ [BackgroundPreload] Completed: \(loadedCount)/\(uniqueUrls.count) place images cached")
        }
    }
    
    // MARK: - Optional Skeleton Loading (Step 3)
    var skeletonTimer: Timer?
    
    func scheduleOptionalSkeletonLoading() {
        // Only show skeleton if we have no data and loading takes longer than 1.5 seconds
        guard circles.isEmpty && activities.isEmpty else { return }
        
        skeletonTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Only show if we still have no data
            if self.circles.isEmpty && self.activities.isEmpty && !self.hasStartedLoading {
                Logger.debug("💀 [OptionalSkeleton] Loading is slow - showing skeleton")
                self.showOptionalSkeletonLoading()
            }
        }
    }
    
    func showOptionalSkeletonLoading() {
        guard skeletonLoadingView == nil else { return }
        
        Logger.debug("💀 [OptionalSkeleton] Showing skeleton for slow connection")
        
        // Create and show skeleton view
        skeletonLoadingView = showSkeletonLoading(in: view)
        
        // Hide main content initially
        mapContainerView.alpha = 0.3 // Keep slightly visible
        activityTableView.alpha = 0.3
        userListView.alpha = 0.3
    }
    
    func hideOptionalSkeletonLoading() {
        skeletonTimer?.invalidate()
        skeletonTimer = nil
        
        guard let skeleton = skeletonLoadingView else { return }
        
        Logger.debug("💀 [OptionalSkeleton] Hiding skeleton - data loaded")
        
        // Animate content in and skeleton out
        UIView.animate(withDuration: 0.4, animations: {
            self.mapContainerView.alpha = 1.0
            self.activityTableView.alpha = 1.0
            self.userListView.alpha = 1.0
        })
        
        hideSkeletonLoading(skeleton)
        skeletonLoadingView = nil
    }
    
    // MARK: - Step 4: Fast API Integration as Alternative Data Source
    var hasTriedFastAPI = false
    
    func tryFastAPIAsAlternative() {
        // Only try once per session and only if we don't have data yet
        guard !hasTriedFastAPI && circles.isEmpty && activities.isEmpty else { return }
        
        hasTriedFastAPI = true
        Logger.debug("🚀 [Step4] Attempting fast API as alternative data source")
        
        // Try the optimized homescreen endpoint
        APIService.shared.request(
            endpoint: "home/homescreen",
            method: .get,
            queryParams: nil
        ) { [weak self] (result: Result<HomeScreenResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    Logger.debug("🚀 [Step4] Fast API succeeded - applying alternative data")
                    
                    // Apply the fast data as an alternative source
                    if let userList = response.data?.userList, !userList.isEmpty {
                        // Refresh user list view to show updated data
                        self.userListView.refresh()
                        Logger.debug("🚀 [Step4] Applied \\(userList.count) users from fast API")
                    }
                    
                    if let activities = response.data?.recentActivities, !activities.isEmpty && self.activities.isEmpty {
                        self.activities = activities
                        self.activityTableView.reloadData()
                        self.activityLoadingContainer.isHidden = true
                        Logger.debug("🚀 [Step4] Applied \\(activities.count) activities from fast API")
                    }
                    
                    // Cache this data for future use
                    if let data = response.data {
                        let stats = HomeScreenStats(
                            totalCircles: 0,
                            totalPlaces: 0, 
                            totalActivities: data.recentActivities?.count ?? 0,
                            totalUsers: data.userList?.count ?? 0,
                            mapPlaces: 0,
                            loadTimeMs: data.stats?.loadTimeMs ?? 0
                        )
                        let content = HomeScreenContent(
                            myCircles: [],
                            networkCircles: [],
                            activities: data.recentActivities ?? [],
                            userList: data.userList ?? [],
                            mapData: nil,
                            stats: stats
                        )
                        self.optimizedCache.store(content)
                    }
                    
                    // Hide skeleton if showing
                    self.hideOptionalSkeletonLoading()
                    
                case .failure(let error):
                    Logger.debug("🚀 [Step4] Fast API failed, will continue with regular loading: \\(error)")
                    // Don't show error to user - this is just an optimization attempt
                    // Regular loading will continue normally
                }
            }
        }
    }
    
    // MARK: - Progressive Skeleton Loading
    func showProgressiveSkeletonLoading() {
        guard skeletonLoadingView == nil else { return }
        
        Logger.debug("💀 [Skeleton] Showing progressive loading skeleton")
        
        // Create and show skeleton view
        skeletonLoadingView = showSkeletonLoading(in: view)
        
        // Hide main content initially
        mapContainerView.alpha = 0
        activityTableView.alpha = 0
        userListView.alpha = 0
    }
    
    func hideProgressiveSkeletonLoading() {
        guard let skeleton = skeletonLoadingView else { return }
        
        Logger.debug("💀 [Skeleton] Hiding progressive loading skeleton")
        
        // Animate content in and skeleton out
        UIView.animate(withDuration: 0.3, animations: {
            self.mapContainerView.alpha = 1.0
            self.activityTableView.alpha = 1.0
            self.userListView.alpha = 1.0
        })
        
        hideSkeletonLoading(skeleton)
        skeletonLoadingView = nil
    }
    
    func updateProgressiveLoading(stage: ProgressiveLoadingStage) {
        Logger.debug("💀 [Progressive] Loading stage: \(stage)")
        
        switch stage {
        case .userListLoaded:
            // Show user list with animation
            UIView.animate(withDuration: 0.2) {
                self.userListView.alpha = 1.0
            }
            
        case .activitiesLoaded:
            // Show activity feed with animation
            UIView.animate(withDuration: 0.2) {
                self.activityTableView.alpha = 1.0
            }
            
        case .mapDataLoaded:
            // Show map with animation
            UIView.animate(withDuration: 0.2) {
                self.mapContainerView.alpha = 1.0
            }
            
        case .allDataLoaded:
            // Hide skeleton completely
            hideProgressiveSkeletonLoading()
        }
    }
    
    // MARK: - Ultra-Fast Home Screen Loading
    func loadHomeScreenDataFast(completion: @escaping (Bool) -> Void) {
        Logger.debug("⚡ [FastLoad] Fetching ultra-fast home screen data...")
        
        APIService.shared.request(
            endpoint: "home/homescreen",
            method: .get,
            queryParams: nil,
            body: nil,
            requiresAuth: true
        ) { [weak self] (result: Result<EnhancedHomeScreenData, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let loadTime = response.data.stats.loadTimeMs
                    Logger.debug("⚡ [FastLoad] Success in \(loadTime)ms - Users: \(response.data.userList.count), Activities: \(response.data.activities.count)")
                    
                    // Apply user list immediately for horizontal scroll
                    self.applyFastUserList(response.data.userList)
                    
                    // Apply recent activities immediately
                    self.applyFastActivities(response.data.activities)
                    
                    // Show UI immediately
                    self.showHomeScreenUI()
                    
                    completion(true)
                    
                case .failure(let error):
                    Logger.debug("⚡ [FastLoad] Failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Full Dashboard Data Loading (Background)
    func loadFullDashboardData() {
        Logger.debug("📊 [FullLoad] Loading complete dashboard data...")
        
        APIService.shared.request(
            endpoint: "home/dashboard",
            method: .get,
            queryParams: ["includeMapData": "true", "includeUserList": "true"],
            body: nil,
            requiresAuth: true
        ) { [weak self] (result: Result<EnhancedHomeScreenData, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let loadTime = response.data.stats.loadTimeMs
                    Logger.debug("📊 [FullLoad] Success in \(loadTime)ms - Full data loaded")
                    
                    // Cache the full data for next time
                    self.optimizedCache.store(response.data)
                    
                    // Apply full data (this will enhance what's already displayed)
                    self.applyHomeScreenData(response.data)
                    
                    // Update map with places if available
                    if let mapData = response.data.mapData {
                        self.applyMapData(mapData)
                    }
                    
                case .failure(let error):
                    Logger.debug("📊 [FullLoad] Failed: \(error.localizedDescription)")
                    // Fallback to legacy loading if needed
                    if !self.isUsingFastLoad {
                        self.fetchCircles()
                    }
                }
            }
        }
    }
    
    // MARK: - Fast Data Application Methods
    func applyFastUserList(_ userList: [UserListItem]) {
        Logger.debug("⚡ [FastApply] Applying user list with \(userList.count) users")
        
        // For now, trigger a refresh of the user list view to show the most recent data
        // The HorizontalUserListView will load its own connection data
        userListView.refresh()
        userListView.isHidden = userList.isEmpty
        
        // Trigger progressive loading update
        updateProgressiveLoading(stage: .userListLoaded)
        
        Logger.debug("⚡ [FastApply] User list updated and visible")
    }
    
    func applyFastActivities(_ activities: [Activity]) {
        Logger.debug("⚡ [FastApply] Applying \(activities.count) activities")
        
        self.activities = activities
        
        // Update activity table immediately
        activityTableView.reloadData()
        activityLoadingContainer.isHidden = true
        
        // Show activity view
        activityTableView.isHidden = false
        
        // Trigger progressive loading update
        updateProgressiveLoading(stage: .activitiesLoaded)
        
        Logger.debug("⚡ [FastApply] Activities updated and visible")
    }
    
    func showHomeScreenUI() {
        Logger.debug("⚡ [FastApply] Showing home screen UI")
        
        // Hide loading states
        hideLoadingState()
        activityLoadingContainer.isHidden = true
        
        // Show main UI components
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
        
        // Update empty state
        updateEmptyState()
        
        Logger.debug("⚡ [FastApply] Home screen UI visible")
    }
    
    func applyHomeScreenData(_ data: HomeScreenContent) {
        Logger.debug("📊 [FullApply] Applying complete home screen data")
        
        // Apply circles data
        self.circles = data.myCircles
        self.networkCircles = data.networkCircles
        
        // Note: Places will be loaded separately through the existing fetchAllPlacesFromCircles method
        // The optimized API provides circle data, but places need to be fetched separately
        // This maintains compatibility with the existing place loading architecture
        
        // Apply activities if not already showing fast-loaded ones
        if !isUsingFastLoad || self.activities.isEmpty {
            self.activities = data.activities
            activityTableView.reloadData()
        }
        
        // Apply user list if not already showing fast-loaded one
        if !isUsingFastLoad {
            applyFastUserList(data.userList)
        }
        
        // Start background image preloading
        preloadImages(from: data)
        
        // Mark as loaded
        CirclesHomeViewController.hasLoadedInitialData = true
        hasStartedLoading = true
        
        // Update UI
        showHomeScreenUI()
        updateUIAfterDataLoad()
        
        Logger.debug("📊 [FullApply] Complete data applied - Activities: \(data.activities.count)")
    }
    
    // MARK: - Image Preloading
    func preloadImages(from data: HomeScreenContent) {
        var imageUrls: [String] = []
        
        // Collect user profile images
        imageUrls.append(contentsOf: data.userList.compactMap { $0.profileImageUrl })
        
        // Collect activity-related images (actor profiles)
        // Note: We'll skip place images for now since we need to load places separately
        for activity in data.activities {
            if let actor = activity.actor, let profilePicture = actor.profilePicture {
                // Only add actual URLs, not SF Symbol references
                if !profilePicture.starts(with: "sf-symbol:") {
                    imageUrls.append(profilePicture)
                }
            }
        }
        
        // Remove duplicates
        let uniqueUrls = Array(Set(imageUrls))
        
        guard !uniqueUrls.isEmpty else { return }
        
        Logger.debug("📷 [Preload] Starting background preload of \(uniqueUrls.count) images")
        
        // Preload images in background
        DispatchQueue.global(qos: .background).async {
            CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
                Logger.debug("📷 [Preload] Completed: \(loadedCount)/\(uniqueUrls.count) images cached")
            }
        }
    }
    
    func applyMapData(_ mapData: MapData) {
        Logger.debug("🗺️ [MapApply] Applying map data with \(mapData.places.count) places")
        
        // Set map region immediately for better UX
        if let bounds = mapData.bounds {
            // TODO: Set map region once the correct map view property is identified
            Logger.debug("🗺️ [MapApply] Map region update requested (deferred)")
        }
        
        // Start progressive place loading
        loadMapPlacesProgressively(mapData.places)
    }
    
    // MARK: - Progressive Map Loading
    func loadMapPlacesProgressively(_ mapPlaces: [MapPlace]) {
        Logger.debug("🗺️ [Progressive] Starting progressive map loading for \(mapPlaces.count) places")
        
        // Load places in batches for smooth performance
        let batchSize = 10
        let batches = mapPlaces.chunked(into: batchSize)
        
        var loadedPlaces: [Place] = []
        var batchIndex = 0
        
        func loadNextBatch() {
            guard batchIndex < batches.count else {
                Logger.debug("🗺️ [Progressive] Completed loading all \(loadedPlaces.count) places")
                isMapDataReady = true
                return
            }
            
            let currentBatch = batches[batchIndex]
            Logger.debug("🗺️ [Progressive] Loading batch \(batchIndex + 1)/\(batches.count) (\(currentBatch.count) places)")
            
            // Convert current batch to Place objects
            // TODO: This will be implemented once place data structure is confirmed
            let batchPlaces: [Place] = []
            
            // Add to loaded places
            loadedPlaces.append(contentsOf: batchPlaces)
            
            // Update map with current batch (async to prevent UI blocking)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Update map with accumulated places
                self.updateMapWithPlaces(loadedPlaces)
                
                batchIndex += 1
                
                // Schedule next batch with small delay for smooth loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadNextBatch()
                }
            }
        }
        
        // Start loading
        loadNextBatch()
    }
    
    // MARK: - Async Map Updates
    func updateMapWithPlaces(_ places: [Place], animated: Bool = false) {
        Logger.debug("🗺️ [UpdateMap] Map update requested for \(places.count) places")
        
        // Update the embedded map controller with smooth loading
        guard let mapVC = mapViewController else {
            Logger.debug("🗺️ [UpdateMap] No map controller available, skipping update")
            return
        }
        
        // Use the embedded map controller's smooth update method
        mapVC.updatePlaces(places)
        
        Logger.debug("🗺️ [UpdateMap] Map update delegated to embedded map controller")
    }
    
    func updateUIAfterDataLoad() {
        // TODO: Re-enable these methods once they're identified in the existing codebase
        // For now, we'll skip these updates to get the basic functionality working
        
        // Update empty state
        updateEmptyState()
        
        // Update notification badge  
        updateNotificationBadge()
        
        Logger.debug("📊 [UpdateUI] UI updates completed")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Invalidate reels collection view layout to ensure proper sizing
        if reelsCollectionView.bounds.width > 0 {
            reelsCollectionView.collectionViewLayout.invalidateLayout()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // Invalidate collection view layout on rotation
        coordinator.animate(alongsideTransition: { _ in
            self.reelsCollectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Logger.debug("🟢 CirclesHomeViewController viewWillAppear called")
        Logger.debug("🟢 Instance: \(ObjectIdentifier(self))")
        Logger.debug("   hasStartedLoading: \(hasStartedLoading)")
        Logger.debug("   isReturningFromFullScreenMap: \(isReturningFromFullScreenMap)")
        Logger.debug("   circles.count: \(circles.count)")
        Logger.debug("   allPlaces.count: \(allPlaces.count)")
        Logger.debug("   preloadedData: \(preloadedData != nil)")
        
        // Step 1: Safe cache optimization - check if we have cached data to speed up loading
        tryLoadFromCache()
        
        // Step 3: Optional skeleton loading - only for slow connections
        scheduleOptionalSkeletonLoading()
        
        // Step 4: Try fast API as alternative data source
        tryFastAPIAsAlternative()
        
        // IMMEDIATE MAP LOADING FEEDBACK: Show loading state immediately
        // This prevents users from seeing an empty confusing map
        showMapLoadingStateImmediate()
        
        // Update notification badge - always refresh when view appears
        Logger.debug("🔔 CirclesHomeViewController: Updating notification badge on viewWillAppear")
        updateNotificationBadge()
        startNotificationBadgeRefresh()
        updateRewardsBadge()
        
        // Update navigation bar for subscription status
        updateNavigationBarForSubscription()
        
        // Check for daily summary data
        checkForDailySummary()
        
        // Ensure Activity tab is selected when returning to home
        if contentSegmentedControl.selectedSegmentIndex != 0 {
            contentSegmentedControl.selectedSegmentIndex = 0
            contentSegmentChanged()
        }
        
        // If returning from full screen map, skip updates
        if isReturningFromFullScreenMap {
            isReturningFromFullScreenMap = false
            hideOptionalSkeletonLoading() // Clean up any skeleton
            hideMapLoadingState() // Also hide map loading state
            return
        }
        
        // Cancel any existing timer first
        loadDebounceTimer?.invalidate()
        
        // If we have preloaded data, use it instead of loading
        if let preloadedData = preloadedData {
            Logger.debug("🟢 Using preloaded data from splash screen")
            hasStartedLoading = true  // Mark as loaded
            usePreloadedData(preloadedData)
            self.preloadedData = nil // Clear after use
            
            // Hide map loading state since we have data
            hideMapLoadingState()
            
            // Still need to refresh connections to get properly sorted data with message timestamps
            userListView.refresh()
            
            return  // Exit early, no timer needed
        }
        
        // Simple check: if this instance has already started loading, don't load again
        if hasStartedLoading {
            Logger.debug("🟢 Skipping load - this instance has already started loading")
            // Hide loading state if we already have data
            if !allPlaces.isEmpty {
                hideMapLoadingState()
            }
            return
        }
        
        // Mark that this instance has started loading
        hasStartedLoading = true
        
        // NOW create the debounce timer (only if we didn't have preloaded data)
        loadDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Logger.debug("🟢 Starting initial data load (after debounce)")
            // Start data load without refreshing user list yet
            // User list will be refreshed after all data is loaded
            self.performInitialDataLoad()
        }
        
        // Don't show filter stack here - let hideMapLoadingState handle it
        // This prevents the filter from showing then hiding again
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Check if onboarding needs to be retried
        checkAndRetryOnboardingIfNeeded()

        // Surface the sign-in-time duplicate-account hint (once per login)
        promptForDuplicateAccountsIfNeeded()
        
        // Listen for connections to be loaded before checking tutorial/overlay.
        // Remove-before-add: this runs on every appearance but the handler only
        // removes the observer when the notification actually fires, so without
        // this the observer would accumulate across appearances.
        NotificationCenter.default.removeObserver(self, name: .connectionsLoaded, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionsLoadedHandler),
            name: .connectionsLoaded,
            object: nil
        )
        
        // Also check after a delay in case connections are already loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkTutorialAndOverlay()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop Moments audio the moment the user leaves this screen (switching
        // bottom tabs, opening a moment full-screen, presenting any modal).
        // Without this the currently-playing reel keeps playing — its audio
        // bleeds into whatever screen the user moved to. Segment changes within
        // the tab already pause; this covers navigating away entirely.
        pauseAllVideos()
    }

    func checkAndRetryOnboardingIfNeeded() {
        // If user has no circles and data has loaded, try onboarding
        if circles.isEmpty && !isLoadingCircles {
            APIService.shared.request(
                endpoint: "users/me/complete-onboarding",
                method: .post,
                body: [:] // Empty dictionary for POST with no body
            ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
                switch result {
                case .success(let response):
                    if response.success {
                        Logger.info("Onboarding completed, reloading circles")
                        // Reload circles to show the newly created ones
                        DispatchQueue.main.async {
                            self?.loadData()
                        }
                    }
                case .failure(let error):
                    // Onboarding might have already been done or failed
                    Logger.debug("Onboarding check result: \(error)")
                }
            }
        }
    }
    
    @objc func connectionsLoadedHandler() {
        Logger.debug("🔔 Connections loaded notification received")
        // Remove observer to prevent multiple calls
        NotificationCenter.default.removeObserver(self, name: .connectionsLoaded, object: nil)
        
        // Check tutorial and overlay now that connections are loaded
        checkTutorialAndOverlay()
    }
    
    func checkTutorialAndOverlay() {
        // Only check once per session
        guard !hasCheckedTutorialAndOverlay else {
            Logger.debug("⚠️ Already checked tutorial and overlay")
            return
        }
        hasCheckedTutorialAndOverlay = true
        
        // If no relationship data has loaded yet, wait a bit longer for async data
        let hasAnyLoadedData = NetworkManager.shared.connections.count > 0 || 
                              NetworkManager.shared.pendingConnections.count > 0 || 
                              userListView.connectionCount > 0
        
        if !hasAnyLoadedData && tutorialCheckRetryCount < maxTutorialCheckRetries {
            tutorialCheckRetryCount += 1
            Logger.debug("🔍 No relationship data loaded yet, scheduling retry \(tutorialCheckRetryCount)/\(maxTutorialCheckRetries) in 2 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                // Reset flag and try again with hopefully loaded data
                self?.hasCheckedTutorialAndOverlay = false
                self?.checkTutorialAndOverlay()
            }
            return
        }
        
        // First check if user has 0 total relationships (connections + following + pending) - show suggested users overlay if so
        let acceptedConnectionCount = NetworkManager.shared.connections.count
        let pendingConnectionCount = NetworkManager.shared.pendingConnections.count
        let horizontalViewCount = userListView.connectionCount
        
        // Total relationships = accepted connections + following relationships (from horizontal view)
        // We also count pending connections as proof the user isn't "new"
        let totalRelationshipCount = acceptedConnectionCount + horizontalViewCount + pendingConnectionCount
        
        Logger.debug("🔍 checkTutorialAndOverlay - Accepted connections: \(acceptedConnectionCount), Following: \(horizontalViewCount), Pending: \(pendingConnectionCount), Total: \(totalRelationshipCount)")
        
        // Additional safety check: also check user profile counts as backup
        let currentUser = AuthService.shared.currentUser
        let profileFollowingCount = currentUser?.followingCount ?? 0
        let profileConnectionsCount = currentUser?.connectionsCount ?? 0
        let profileTotalRelationships = profileFollowingCount + profileConnectionsCount
        
        Logger.debug("🔍 Profile backup check - Following: \(profileFollowingCount), Connections: \(profileConnectionsCount), Profile total: \(profileTotalRelationships)")
        
        // Only show overlay if BOTH the loaded data AND profile data indicate no relationships
        let shouldConsiderAsNewUser = totalRelationshipCount == 0 && profileTotalRelationships == 0
        
        if shouldConsiderAsNewUser {
            Logger.debug("✅ User has 0 total relationships in both loaded data and profile - checking if should show overlay")
            // For users with 0 total relationships, always show the overlay unless they've explicitly dismissed it this session
            // Reset the flag for users with 0 relationships to ensure they see it
            if !hasCheckedForSuggestedUsers {
                hasCheckedForSuggestedUsers = true  // Set the flag to prevent repeated showing
                // Enable the overlay for users with 0 relationships
                OnboardingManager.shared.enableSuggestedUsersOverlay()
                Logger.debug("✅ Enabled suggested users overlay for user with 0 relationships")
            }
            
            if OnboardingManager.shared.shouldShowSuggestedUsers {
                Logger.debug("✅ Should show suggested users overlay - calling showSuggestedUsersOverlay()")
                showSuggestedUsersOverlay()
                return
            } else {
                Logger.debug("❌ Suggested users overlay disabled in settings")
            }
        } else {
            Logger.debug("✅ User has relationships (loaded: \(totalRelationshipCount), profile: \(profileTotalRelationships)) - skipping new user overlay")
        }
        
        // Check tutorial status from backend
        OnboardingManager.shared.checkIfUserNeedsTutorial { [weak self] needsTutorial in
            guard let self = self, needsTutorial else {
                // If no tutorial needed and not already shown overlay, check for suggested users
                if NetworkManager.shared.connections.count > 0 {
                    self?.checkAndShowSuggestedUsers()
                }
                // One-time hint explaining avatar tap vs long press (skipped if
                // the suggested-users overlay took the screen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.maybeShowConnectionAvatarHint()
                }
                return
            }
            
            // User needs tutorial - start it
            OnboardingManager.shared.startTutorial()
            
            // Show tutorial for new users who haven't completed the welcome step
            if !OnboardingManager.shared.hasCompletedStep(.welcome) {
                DispatchQueue.main.async {
                    // Show tutorial after a brief delay for UI to settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        OnboardingManager.shared.showTutorialStep(
                            .welcome,
                            targetView: self.quickAddPlaceButton,
                            in: self,
                            arrowDirection: .bottom
                        )
                    }
                }
            }
        }
    }
    
    func checkAndShowSuggestedUsers() {
        // Only check once per session
        guard !hasCheckedForSuggestedUsers else { 
            Logger.debug("⚠️ checkAndShowSuggestedUsers - Already checked this session")
            return 
        }
        hasCheckedForSuggestedUsers = true
        
        // Get connection count from NetworkManager
        let connectionCount = NetworkManager.shared.connections.count
        Logger.debug("🔍 checkAndShowSuggestedUsers - Connection count: \(connectionCount)")
        
        // Check if should show suggested users
        if OnboardingManager.shared.shouldShowSuggestedUsersOverlay(connectionCount: connectionCount) {
            Logger.debug("✅ Should show suggested users overlay - calling showSuggestedUsersOverlay()")
            showSuggestedUsersOverlay()
        } else {
            Logger.debug("❌ Should NOT show suggested users overlay")
        }
    }
    
    /// One-time bubble pointing at the connections avatar row explaining the
    /// two gestures: tap shows that person's places on the map, long press
    /// opens their profile. Marked as shown immediately so it only ever
    /// appears once.
    func maybeShowConnectionAvatarHint() {
        guard OnboardingManager.shared.shouldShowConnectionAvatarHint(),
              !userListView.isHidden,
              userListView.connectionCount > 0,
              suggestedUsersOverlay == nil else { return }
        OnboardingManager.shared.markConnectionAvatarHintShown()

        let bubble = BubbleView()
        bubble.configureHint(
            title: "Your Connections",
            description: "Tap an avatar to see that person's places on the map. Long press to view their profile.",
            arrowDirection: .top
        )
        bubble.onNext = { [weak bubble] in
            bubble?.dismiss {
                bubble?.removeFromSuperview()
            }
        }

        view.addSubview(bubble)
        bubble.pointTo(userListView, in: view)
        bubble.show()
    }

    func showSuggestedUsersOverlay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Don't show if already showing
            guard self.suggestedUsersOverlay == nil else { return }
            
            let overlay = SuggestedUsersOverlayView()
            overlay.delegate = self
            self.suggestedUsersOverlay = overlay
            
            // Show overlay
            overlay.show(in: self.view)
        }
    }
    
    func showAddPlaceTutorialIfNeeded() {
        // Check if should show add place tutorial
        // (Visit-tracking card intentionally removed from first-run onboarding)
        guard OnboardingManager.shared.shouldShowAddPlaceTutorial() else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Don't show if already showing
            guard self.addPlaceTutorialOverlay == nil else { return }
            
            let overlay = AddFirstPlaceTutorialView()
            overlay.delegate = self
            self.addPlaceTutorialOverlay = overlay
            
            // Show overlay with the Add Place button as target
            overlay.show(in: self.view, targetButton: self.quickAddPlaceButton)
        }
    }
    
    // MARK: - Forced Display Methods (for Welcome Tour)
    
    func forceShowSuggestedUsersOverlay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Dismiss any existing overlay first
            if let existingOverlay = self.suggestedUsersOverlay {
                existingOverlay.dismiss()
                self.suggestedUsersOverlay = nil
            }
            
            // Create and show new overlay without any checks
            let overlay = SuggestedUsersOverlayView()
            overlay.delegate = self
            self.suggestedUsersOverlay = overlay
            
            // Show overlay
            overlay.show(in: self.view)
        }
    }
    
    func forceShowAddPlaceTutorial() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Dismiss any existing overlay first
            if let existingOverlay = self.addPlaceTutorialOverlay {
                existingOverlay.dismiss()
                self.addPlaceTutorialOverlay = nil
            }
            
            // Create and show new overlay without any checks
            let overlay = AddFirstPlaceTutorialView()
            overlay.delegate = self
            self.addPlaceTutorialOverlay = overlay
            
            // Show overlay with the Add Place button as target
            overlay.show(in: self.view, targetButton: self.quickAddPlaceButton)
        }
    }
    
    func showVisitTrackingPermissionIfNeeded() {
        // Check if should show visit tracking permission
        guard OnboardingManager.shared.shouldShowVisitTrackingPermission() else {
            // Continue with normal flow
            checkTutorialAndOverlay()
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Don't show if already showing
            guard self.visitTrackingPermissionOverlay == nil else { return }
            
            let overlay = VisitTrackingPermissionView()
            overlay.delegate = self
            self.visitTrackingPermissionOverlay = overlay
            
            // Show overlay
            overlay.show(in: self.view)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update colors when dark mode changes
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAppearance()
        }
    }
    
    func updateAppearance() {
        // Update border colors that don't automatically adapt
        mapMenuButton.layer.borderColor = Constants.Colors.separator.cgColor
        listToggleButton.layer.borderColor = Constants.Colors.separator.cgColor
        updateMyPlacesToggleAppearance()
    }
    
    // MARK: - UI Setup
    func setupUI() {
        view.backgroundColor = Constants.Colors.background
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        // Removed redundant title - tab bar already shows "My Circles"
        
        // Create custom view for notification button with badge
        setupNotificationBadge()
        
        // Setup empty state view
        emptyStateView.addSubview(emptyStateImageView)
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateView.addSubview(emptyStateButtonsStack)

        // Add scroll view
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add search bar to main view (not scrolling)
        view.addSubview(searchBar)
        view.addSubview(searchScopeButton)
        searchScopeButton.isHidden = true // unified search: scope dropdown retired
        view.addSubview(quickAddPlaceButton)
        
        // Add search scope dropdown
        view.addSubview(searchScopeDropdownView)
        searchScopeDropdownView.addSubview(searchScopeTableView)
        
        // Add content to scroll view
        contentView.addSubview(userListView)
        contentView.addSubview(mapContainerView)
        contentView.addSubview(filterContainer)
        filterContainer.addSubview(filterStackView)
        contentView.addSubview(mapLoadingView)
        mapLoadingView.addSubview(mapLoadingIndicator)
        mapLoadingView.addSubview(mapLoadingLabel)
        mapLoadingView.addSubview(mapLoadingProgressView)
        contentView.addSubview(mapExpandButton)
        contentView.addSubview(mapPlaceCountLabel)
        contentView.addSubview(placesListTableView)
        
        // Add small loading indicator directly to map container for better UX
        mapContainerView.addSubview(mapLoadingIndicator)
        contentView.addSubview(locationStatusLabel)
        // Avatar first so "who is being mapped" reads before the controls
        filterStackView.addArrangedSubview(selectedConnectionAvatarButton)
        filterStackView.addArrangedSubview(mapMenuButton)
        filterStackView.addArrangedSubview(myPlacesToggleButton)
        filterStackView.addArrangedSubview(listToggleButton)
        contentView.addSubview(emptyStateView)
        
        // Add activity feed section
        contentView.addSubview(activityFeedSection)
        activityFeedSection.addSubview(activityHeaderLabel)
        activityFeedSection.addSubview(contentSegmentedControl)
        activityFeedSection.addSubview(momentsCameraButton)
        activityFeedSection.addSubview(activityTableView)
        activityFeedSection.addSubview(reelsCollectionView)
        activityFeedSection.addSubview(specialsTableView)
        activityFeedSection.addSubview(activityEmptyStateLabel)
        activityFeedSection.addSubview(activityLoadingContainer)
        
        // Ensure loading container is on top
        activityFeedSection.bringSubviewToFront(activityLoadingContainer)
        // Ensure camera button is on top of segmented control
        activityFeedSection.bringSubviewToFront(momentsCameraButton)
        
        // Add loading container
        view.addSubview(loadingContainerView)
        loadingContainerView.addSubview(loadingContentView)
        loadingContentView.addSubview(loadingIndicator)
        loadingContentView.addSubview(loadingLabel)
        
        // Add search results table view
        view.addSubview(searchResultsTableView)
        
        // Add floating record button (for Reels tab) - now hidden in favor of camera button
        view.addSubview(floatingRecordButton)
        floatingRecordButton.addTarget(self, action: #selector(recordReelTapped), for: .touchUpInside)
        floatingRecordButton.isHidden = true // Always hidden now that we have the camera button
        
        // Add action to camera button
        momentsCameraButton.addTarget(self, action: #selector(recordReelTapped), for: .touchUpInside)
        
        // Bring elements to proper z-order - filters and expand button above map
        contentView.bringSubviewToFront(filterContainer)
        contentView.bringSubviewToFront(mapExpandButton)
        
        // Ensure loading view is on top
        view.bringSubviewToFront(loadingContainerView)
        
        // Add tap gesture to dismiss dropdowns and keyboard when clicking outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissDropdowns(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        NSLayoutConstraint.activate([
            // Search bar (fixed at top). Unified search removed the scope
            // dropdown button, so the bar now runs to the quick-add button.
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            searchBar.trailingAnchor.constraint(equalTo: quickAddPlaceButton.leadingAnchor, constant: -Constants.Spacing.small),
            searchBar.heightAnchor.constraint(equalToConstant: 44),

            // Scope button retired (unified search): collapsed to zero size and
            // hidden. Kept in the hierarchy so the (now dormant) dropdown
            // constraints/wiring still resolve without a layout rewrite.
            searchScopeButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchScopeButton.trailingAnchor.constraint(equalTo: quickAddPlaceButton.leadingAnchor),
            searchScopeButton.widthAnchor.constraint(equalToConstant: 0),
            searchScopeButton.heightAnchor.constraint(equalToConstant: 0),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Quick Add Place button
            quickAddPlaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            quickAddPlaceButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            quickAddPlaceButton.heightAnchor.constraint(equalToConstant: 40),
            quickAddPlaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            // User list view (now the first content section; quick-access bar removed)
            userListView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            userListView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            userListView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            userListView.heightAnchor.constraint(equalToConstant: 118),
            
            // Filter container - positioned to overlay the map
            filterContainer.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: Constants.Spacing.small),
            filterContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            filterContainer.trailingAnchor.constraint(lessThanOrEqualTo: mapExpandButton.leadingAnchor, constant: -Constants.Spacing.small),
            filterContainer.heightAnchor.constraint(equalToConstant: 36),
            
            // Filter stack - compact layout in filter container
            filterStackView.topAnchor.constraint(equalTo: filterContainer.topAnchor, constant: 2),
            filterStackView.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor, constant: 6),
            filterStackView.trailingAnchor.constraint(equalTo: filterContainer.trailingAnchor, constant: -6),
            filterStackView.bottomAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: -2),
            
            // Map container - directly after userListView
            mapContainerView.topAnchor.constraint(equalTo: userListView.bottomAnchor),
            mapContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Map loading view - same position as map container
            mapLoadingView.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
            mapLoadingView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            mapLoadingView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            mapLoadingView.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor),
            
            // Map loading indicator - bottom left corner like place count
            mapLoadingIndicator.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor, constant: 16),
            mapLoadingIndicator.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: -16),
            mapLoadingIndicator.widthAnchor.constraint(equalToConstant: 40),
            mapLoadingIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Map loading label
            mapLoadingLabel.topAnchor.constraint(equalTo: mapLoadingIndicator.bottomAnchor, constant: 16),
            mapLoadingLabel.leadingAnchor.constraint(equalTo: mapLoadingView.leadingAnchor, constant: 20),
            mapLoadingLabel.trailingAnchor.constraint(equalTo: mapLoadingView.trailingAnchor, constant: -20),
            
            // Map loading progress view
            mapLoadingProgressView.topAnchor.constraint(equalTo: mapLoadingLabel.bottomAnchor, constant: 12),
            mapLoadingProgressView.leadingAnchor.constraint(equalTo: mapLoadingView.leadingAnchor, constant: 40),
            mapLoadingProgressView.trailingAnchor.constraint(equalTo: mapLoadingView.trailingAnchor, constant: -40),
            mapLoadingProgressView.heightAnchor.constraint(equalToConstant: 4),
            
            // Map expand button
            mapExpandButton.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: Constants.Spacing.small),
            mapExpandButton.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor, constant: -Constants.Spacing.small),
            mapExpandButton.widthAnchor.constraint(equalToConstant: 36),
            mapExpandButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Map place count label - above zoom buttons on right side
            mapPlaceCountLabel.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: -70),
            mapPlaceCountLabel.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor, constant: -Constants.Spacing.small),
            mapPlaceCountLabel.heightAnchor.constraint(equalToConstant: 40),
            mapPlaceCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            emptyStateView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: mapContainerView.centerYAnchor),
            emptyStateView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.8),
            
            emptyStateImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyStateImageView.widthAnchor.constraint(equalToConstant: 100),
            emptyStateImageView.heightAnchor.constraint(equalToConstant: 100),
            
            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateImageView.bottomAnchor, constant: Constants.Spacing.medium),
            emptyStateLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),

            emptyStateButtonsStack.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: Constants.Spacing.medium),
            emptyStateButtonsStack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateButtonsStack.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
            
            // Loading container constraints - full screen overlay
            loadingContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Loading content view - centered card
            loadingContentView.centerXAnchor.constraint(equalTo: loadingContainerView.centerXAnchor),
            loadingContentView.centerYAnchor.constraint(equalTo: loadingContainerView.centerYAnchor),
            loadingContentView.widthAnchor.constraint(equalToConstant: 200),
            loadingContentView.heightAnchor.constraint(equalToConstant: 120),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingContentView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: loadingContentView.topAnchor, constant: 20),
            
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 12),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingContentView.leadingAnchor, constant: 16),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingContentView.trailingAnchor, constant: -16),
            loadingLabel.bottomAnchor.constraint(lessThanOrEqualTo: loadingContentView.bottomAnchor, constant: -20),
            
            // Filter button width constraints
            mapMenuButton.widthAnchor.constraint(equalToConstant: 36),
            myPlacesToggleButton.widthAnchor.constraint(equalToConstant: 36),
            listToggleButton.widthAnchor.constraint(equalToConstant: 36),
            selectedConnectionAvatarButton.widthAnchor.constraint(equalToConstant: 36),

            // Places list overlays the map exactly
            placesListTableView.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
            placesListTableView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            placesListTableView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            placesListTableView.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor),

            // Location status label
            locationStatusLabel.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: 16),
            locationStatusLabel.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor, constant: -16),
            locationStatusLabel.heightAnchor.constraint(equalToConstant: 28),
            
            // Activity feed section
            activityFeedSection.topAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: Constants.Spacing.xsmall),
            activityFeedSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            activityFeedSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            activityFeedSection.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large),
            
            // Activity header
            activityHeaderLabel.topAnchor.constraint(equalTo: activityFeedSection.topAnchor, constant: Constants.Spacing.tiny),
            activityHeaderLabel.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.medium),
            activityHeaderLabel.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Segmented control - full width
            contentSegmentedControl.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.small),
            contentSegmentedControl.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.medium),
            contentSegmentedControl.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Camera button for Moments - overlay on the right side of Moments segment
            momentsCameraButton.centerYAnchor.constraint(equalTo: contentSegmentedControl.centerYAnchor),
            momentsCameraButton.trailingAnchor.constraint(equalTo: contentSegmentedControl.trailingAnchor, constant: -5),
            momentsCameraButton.widthAnchor.constraint(equalToConstant: 56),
            momentsCameraButton.heightAnchor.constraint(equalToConstant: 56),
            
            // Activity table view
            activityTableView.topAnchor.constraint(equalTo: contentSegmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            activityTableView.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor),
            activityTableView.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor),
            activityTableView.bottomAnchor.constraint(equalTo: activityFeedSection.bottomAnchor),
            
            // Reels collection view (full width for video experience)
            reelsCollectionView.topAnchor.constraint(equalTo: contentSegmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            reelsCollectionView.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor),
            reelsCollectionView.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor),
            reelsCollectionView.bottomAnchor.constraint(equalTo: activityFeedSection.bottomAnchor),

            // Specials table (same slot as the other content views)
            specialsTableView.topAnchor.constraint(equalTo: contentSegmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            specialsTableView.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor),
            specialsTableView.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor),
            specialsTableView.bottomAnchor.constraint(equalTo: activityFeedSection.bottomAnchor),

            // Activity empty state
            activityEmptyStateLabel.centerXAnchor.constraint(equalTo: activityFeedSection.centerXAnchor),
            activityEmptyStateLabel.centerYAnchor.constraint(equalTo: activityTableView.centerYAnchor),
            activityEmptyStateLabel.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.large),
            activityEmptyStateLabel.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Activity loading container
            activityLoadingContainer.centerXAnchor.constraint(equalTo: activityFeedSection.centerXAnchor),
            activityLoadingContainer.centerYAnchor.constraint(equalTo: activityTableView.centerYAnchor),
            activityLoadingContainer.widthAnchor.constraint(equalToConstant: 80),
            activityLoadingContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Floating record button - positioned at top left
            floatingRecordButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            floatingRecordButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            floatingRecordButton.widthAnchor.constraint(equalToConstant: 56),
            floatingRecordButton.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        // Create height constraints - reduced for iPhone 16 Pro to show more activity content
        mapHeightConstraint = mapContainerView.heightAnchor.constraint(equalToConstant: 320)
        mapHeightConstraint?.isActive = true
        
        // Set a reasonable height for the activity table to allow scrolling
        activityTableHeightConstraint = activityTableView.heightAnchor.constraint(equalToConstant: 600)
        activityTableHeightConstraint?.isActive = true
        
        // Search results table view constraints
        NSLayoutConstraint.activate([
            searchResultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            searchResultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            searchResultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        searchResultsHeightConstraint = searchResultsTableView.heightAnchor.constraint(equalToConstant: 0)
        searchResultsHeightConstraint?.isActive = true
        
        // Search scope dropdown constraints
        NSLayoutConstraint.activate([
            searchScopeDropdownView.topAnchor.constraint(equalTo: searchScopeButton.bottomAnchor, constant: 4),
            searchScopeDropdownView.trailingAnchor.constraint(equalTo: searchScopeButton.trailingAnchor),
            searchScopeDropdownView.widthAnchor.constraint(equalToConstant: 250),
            
            searchScopeTableView.topAnchor.constraint(equalTo: searchScopeDropdownView.topAnchor),
            searchScopeTableView.leadingAnchor.constraint(equalTo: searchScopeDropdownView.leadingAnchor),
            searchScopeTableView.trailingAnchor.constraint(equalTo: searchScopeDropdownView.trailingAnchor),
            searchScopeTableView.bottomAnchor.constraint(equalTo: searchScopeDropdownView.bottomAnchor)
        ])
        
        searchScopeDropdownHeightConstraint = searchScopeDropdownView.heightAnchor.constraint(equalToConstant: 0)
        searchScopeDropdownHeightConstraint?.isActive = true
        
        // Setup search results table view
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.rowHeight = UITableView.automaticDimension
        searchResultsTableView.estimatedRowHeight = 60
        
        quickAddPlaceButton.addTarget(self, action: #selector(quickAddPlaceButtonTapped), for: .touchUpInside)
        mapExpandButton.addTarget(self, action: #selector(expandMapButtonTapped), for: .touchUpInside)
        searchScopeButton.addTarget(self, action: #selector(searchScopeButtonTapped), for: .touchUpInside)
        
        setupMapView()
        setupActivityFeed()
    }
    
    func setupMapView() {
        let mapVC = FullScreenMapViewController()
        mapVC.viewMode = .allPlaces
        mapVC.delegate = self
        mapVC.ownPlaceIds = Set(userOwnPlaces.map { $0.id })
        
        addChild(mapVC)
        mapContainerView.addSubview(mapVC.view)
        mapVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapVC.view.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
            mapVC.view.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            mapVC.view.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            mapVC.view.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor)
        ])
        mapVC.didMove(toParent: self)
        
        mapViewController = mapVC
        
        // Ensure filter container, expand button, and place count stay above the map
        contentView.bringSubviewToFront(filterContainer)
        contentView.bringSubviewToFront(mapExpandButton)
        contentView.bringSubviewToFront(mapPlaceCountLabel)
    }
    
    func setupDropdownViews() {
        // Distance-sorted places list (map/list toggle)
        placesListTableView.delegate = self
        placesListTableView.dataSource = self

        // Also configure search results table view
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.delaysContentTouches = false
        searchResultsTableView.canCancelContentTouches = true
        
        // Configure search scope table view
        searchScopeTableView.delegate = self
        searchScopeTableView.dataSource = self
        searchScopeTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchScopeCell")
        searchScopeTableView.delaysContentTouches = false
        searchScopeTableView.canCancelContentTouches = true
    }
    
    func setupActivityFeed() {
        // Setup activity table view
        activityTableView.delegate = self
        activityTableView.dataSource = self
        activityTableView.register(ActivityFeedCell.self, forCellReuseIdentifier: ActivityFeedCell.identifier)
        
        // Enable automatic row height calculation
        activityTableView.rowHeight = UITableView.automaticDimension
        activityTableView.estimatedRowHeight = 120
        
        // Setup reels collection view
        reelsCollectionView.delegate = self
        reelsCollectionView.dataSource = self
        reelsCollectionView.register(VideoReelCell.self, forCellWithReuseIdentifier: "VideoReelCell")

        specialsTableView.delegate = self
        specialsTableView.dataSource = self
        specialsTableView.register(SpecialItemCell.self, forCellReuseIdentifier: SpecialItemCell.identifier)

        // Setup segmented control
        contentSegmentedControl.addTarget(self, action: #selector(contentSegmentChanged), for: .valueChanged)
        
        // Set scroll view delegate for pagination
        scrollView.delegate = self
        
        // Add refresh control to scroll view
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshActivityFeed), for: .valueChanged)
        scrollView.refreshControl = refreshControl
    }
    
    func setupSearchBar() {
        searchBar.delegate = self
        
        // Add toolbar with Done button to search bar
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        
        toolbar.items = [flexSpace, doneButton]
        searchBar.inputAccessoryView = toolbar
    }
    
    @objc func dismissKeyboard() {
        // Called from Done button, always dismiss
        searchBar.resignFirstResponder()
    }
    
    // Navigation title tap removed since we no longer show the title

    // MARK: - Cache Management
    
    func isCacheValid() -> Bool {
        guard let expiry = placesCacheExpiry else { return false }
        return Date() < expiry && !cachedPlaces.isEmpty
    }
    
    func invalidateCache() {
        cachedPlaces.removeAll()
        userOwnPlaces.removeAll()
        placesCacheExpiry = nil
        Logger.debug("🗑️ Places cache invalidated")
    }
    
    func shouldUseCachedData() -> Bool {
        return isCacheValid() && !isPerformingInitialLoad
    }
    
    // MARK: - Preloaded Data
    func setPreloadedData(_ data: PreloadedData) {
        // Store connections separately so they're available when userListView is lazily created
        self.preloadedConnections = data.connections
        self.preloadedData = data
    }
    
    func usePreloadedData(_ data: PreloadedData) {
        // Set circles and places
        self.circles = data.circles
        
        // Set activities and moments from preloaded data
        self.activities = data.activities
        self.reels = data.moments
        
        Logger.debug("📍 usePreloadedData: Got \(data.circles.count) circles")
        Logger.debug("📍 usePreloadedData: Got \(data.allPlaces.count) places (INCOMPLETE!)")
        Logger.debug("📍 usePreloadedData: Got \(data.connections.count) connections")
        Logger.debug("📍 usePreloadedData: Got \(data.activities.count) activities")
        Logger.debug("📍 usePreloadedData: Got \(data.moments.count) moments")
        Logger.debug("📍 usePreloadedData: Should have 124 places according to profile")
        
        // Don't set initial connections from preloaded data since they don't have message timestamps
        // The connections will be properly loaded with all data in viewWillAppear via refresh()
        Logger.debug("✅ usePreloadedData: Skipping initial connections - will load with proper data via refresh()")
        
        // Don't use preloaded places - they're incomplete!
        // Instead, trigger a full fetch of all places
        self.allPlaces = [] // Clear places
        self.cachedPlaces = [] // Clear cache
        self.userOwnPlaces = [] // Clear user places
        
        CirclesHomeViewController.hasLoadedInitialData = false // Force a proper load
        
        // Mark that we've loaded circles but need to fetch places
        hasStartedLoading = true
        
        // Update UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Show map and filter UI
            self.mapContainerView.isHidden = false
            self.filterStackView.isHidden = false
            self.filterContainer.isHidden = false
            self.mapExpandButton.isHidden = false
            
            // Set default filter (All Connections)
            self.selectedConnectionId = nil
            self.selectedConnectionUser = nil

            // Don't mark as ready - we need to fetch places
            self.isMapDataReady = false
            
            // Apply filters and update map
            // Don't update map yet - we need to fetch all places first
            
            // Update empty state visibility
            self.updateEmptyState()
            
            // Reload activity and moments UI if we have data
            if !self.activities.isEmpty {
                self.activityTableView.reloadData()
                self.activityLoadingContainer.isHidden = true
                self.activityEmptyStateLabel.isHidden = true
            }
            
            if !self.reels.isEmpty {
                self.reelsCollectionView.reloadData()
            }

            // A slimmed preload may complete before the non-critical feed calls
            // finish; fetch whatever is missing so the feed never stays empty.
            if self.activities.isEmpty {
                self.fetchActivities()
            }
            if self.reels.isEmpty {
                self.fetchReels()
            }

            Logger.debug("✅ Preloaded data applied successfully")
            Logger.debug("   - Circles: \(self.circles.count)")
            Logger.debug("   - Places: \(self.allPlaces.count) (INCOMPLETE - need to fetch all)")
            Logger.debug("   - Filtered places: \(self.filteredPlaces.count)")
            Logger.debug("   - Activities: \(self.activities.count)")
            Logger.debug("   - Moments: \(self.reels.count)")
            
            // Now fetch ALL places from circles
            self.fetchAllPlacesFromCircles()
        }
    }
    
    // MARK: - Activity Feed Methods
    @objc func refreshActivityFeed() {
        // Refresh the horizontal user list
        userListView.refresh()
        
        // Check for daily summary data
        checkForDailySummary()
        
        // Refresh content based on selected tab
        switch contentSegmentedControl.selectedSegmentIndex {
        case 0:
            fetchActivities()
        case 1:
            fetchReels()
        default:
            fetchSpecials(force: true)
        }
        
        // Also refresh circles data for consistency
        if isShowingNetworkCircles {
            fetchNetworkCircles()
        } else {
            fetchCircles()
        }
    }
    
    @objc func contentSegmentChanged() {
        let selectedIndex = contentSegmentedControl.selectedSegmentIndex

        switch selectedIndex {
        case 0:
            // Show Activity feed
            activityTableView.isHidden = false
            reelsCollectionView.isHidden = true
            specialsTableView.isHidden = true
            momentsCameraButton.isHidden = true
            activityHeaderLabel.text = "Recent Activity"

            // Pause any playing videos
            pauseAllVideos()

            // Load activities if needed
            if activities.isEmpty {
                fetchActivities()
            }
        case 1:
            // Show Reels feed
            activityTableView.isHidden = true
            reelsCollectionView.isHidden = false
            specialsTableView.isHidden = true

            // Reset to first video
            currentReelIndex = 0

            // Force layout update before showing collection view
            view.layoutIfNeeded()

            // Invalidate layout to ensure proper sizing
            reelsCollectionView.collectionViewLayout.invalidateLayout()

            // Reset collection view to top to fix Y offset issue
            reelsCollectionView.setContentOffset(.zero, animated: false)

            // Scroll to first item explicitly
            if !reels.isEmpty {
                let firstIndexPath = IndexPath(item: 0, section: 0)
                reelsCollectionView.scrollToItem(at: firstIndexPath, at: .top, animated: false)
            }

            momentsCameraButton.isHidden = false
            activityHeaderLabel.text = "Moments"

            // Always refresh reels when switching to Moments tab to get latest videos
            fetchReels()

            // Note: fetchReels will handle playing the first video after loading
        default:
            // Show Specials (live offers + announcements from participating venues)
            activityTableView.isHidden = true
            reelsCollectionView.isHidden = true
            specialsTableView.isHidden = false
            momentsCameraButton.isHidden = true
            activityHeaderLabel.text = "Specials"

            // Pause any playing videos (may be arriving from Moments)
            pauseAllVideos()

            // Load once; pull-to-refresh refetches
            if specials.isEmpty {
                fetchSpecials()
            }
        }
    }

    // MARK: - Specials Methods

    /// Loads live deals from participating venues and flattens them into one
    /// row per offer/announcement, preserving the server's venue order
    /// (saved venues first, then nearest).
    func fetchSpecials(force: Bool = false) {
        guard !isLoadingSpecials else { return }
        isLoadingSpecials = true

        if specials.isEmpty {
            activityLoadingContainer.isHidden = false
            activityLoadingIndicator.startAnimating()
            activityEmptyStateLabel.isHidden = true
        }

        // Location improves ordering but is optional — denied/unavailable
        // falls back to the server's alphabetical order
        LocationService.shared.getCurrentLocation { [weak self] location in
            RewardsService.shared.getOffers(
                lat: location?.coordinate.latitude,
                lng: location?.coordinate.longitude
            ) { result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoadingSpecials = false
                    self.activityLoadingIndicator.stopAnimating()
                    self.activityLoadingContainer.isHidden = true
                    self.scrollView.refreshControl?.endRefreshing()

                    // Only touch shared UI if Specials is still the visible tab
                    let onSpecialsTab = self.contentSegmentedControl.selectedSegmentIndex == 2

                    switch result {
                    case .success(let data):
                        self.specials = data.venues.flatMap { venue -> [SpecialItem] in
                            let offerItems = venue.offers.map {
                                SpecialItem(venue: venue, kind: .offer($0))
                            }
                            let announcementItems = (venue.announcements ?? []).map {
                                SpecialItem(venue: venue, kind: .announcement($0))
                            }
                            return offerItems + announcementItems
                        }
                        self.specialsTableView.reloadData()

                        if onSpecialsTab {
                            if self.specials.isEmpty {
                                self.activityEmptyStateLabel.text = "No specials right now — check back soon"
                                self.activityEmptyStateLabel.isHidden = false
                            } else {
                                self.activityEmptyStateLabel.isHidden = true
                            }
                        }

                    case .failure:
                        if self.specials.isEmpty && onSpecialsTab {
                            self.activityEmptyStateLabel.text = "Couldn't load specials — pull to refresh"
                            self.activityEmptyStateLabel.isHidden = false
                        }
                    }
                }
            }
        }
    }

    /// Opens the tapped deal's place page — same resolution as the Rewards
    /// screen: canonical global place by id, venue-built fallback otherwise.
    func openSpecialPlace(_ venue: OfferVenue) {
        guard let placeId = venue.globalPlaceId ?? venue.googlePlaceId else {
            pushSpecialPlaceFallback(venue)
            return
        }

        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.globalPlace.toLegacyPlace(withRelation: response.userRelation)
                        let detailVC = PlaceDetailViewController(place: place)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure:
                        self.pushSpecialPlaceFallback(venue)
                    }
                }
            }
        }
    }

    /// Long-press share on a Specials row: the deal's text plus the venue's
    /// place link (or the App Store link when the venue has no linked place)
    func shareSpecial(_ item: SpecialItem) {
        var shareText: String
        switch item.kind {
        case .offer(let offer):
            shareText = "🎁 \(offer.title) at \(item.venue.venueName) — redeem it with points on Circles!"
        case .announcement(let announcement):
            shareText = "📣 \(announcement.title) at \(item.venue.venueName)"
            if !announcement.message.isEmpty {
                shareText += "\n\(announcement.message)"
            }
            shareText += "\nSeen on Circles:"
        }

        // The /place page resolves both save-doc and globalPlaces ids — a
        // googlePlaceId won't resolve, so fall back to the App Store link
        let url: URL = item.venue.globalPlaceId.map { ShareLinks.place(id: $0) } ?? ShareLinks.appStoreURL

        let activityVC = UIActivityViewController(activityItems: [shareText, url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = specialsTableView
        present(activityVC, animated: true)
    }

    func pushSpecialPlaceFallback(_ venue: OfferVenue) {
        var location: GeoLocation?
        if let coordinate = venue.location {
            // GeoJSON order: [longitude, latitude]
            location = GeoLocation(type: "Point", coordinates: [coordinate.lng, coordinate.lat])
        }

        let place = Place(
            id: venue.globalPlaceId ?? venue.googlePlaceId ?? venue.venueId,
            globalPlaceId: venue.globalPlaceId,
            name: venue.placeName ?? venue.venueName,
            description: nil,
            address: venue.placeAddress ?? "",
            location: location,
            website: nil,
            phone: nil,
            googlePlaceId: venue.googlePlaceId,
            photos: nil,
            videos: nil,
            category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: nil,
            addedBy: "",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date()
        )
        let detailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func fetchActivities(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isLoadingActivities && !isLoadingMoreActivities else { 
            Logger.debug("🔄 Already loading activities, skipping...")
            completion?(false)
            return 
        }
        
        // Don't load more if we've reached the end
        if loadMore && !hasMoreActivities {
            Logger.debug("📊 No more activities to load")
            completion?(false)
            return
        }
        
        Logger.debug("📊 Starting to fetch activities... (loadMore: \(loadMore))")
        Logger.debug("📊 activityLoadingContainer.isHidden before: \(activityLoadingContainer.isHidden)")
        Logger.debug("📊 activityLoadingIndicator.isAnimating before: \(activityLoadingIndicator.isAnimating)")
        
        // Check if user needs notification prompt when viewing activity feed
        if !loadMore && activities.isEmpty {
            NotificationPromptManager.shared.checkAndPromptIfNeeded(in: self, context: .activityFeed)
        }
        
        if loadMore {
            isLoadingMoreActivities = true
            // Show loading footer
            activityTableView.tableFooterView = loadMoreIndicatorView
        } else {
            isLoadingActivities = true
            activityLoadingContainer.isHidden = false
            activityLoadingIndicator.startAnimating()
            activityEmptyStateLabel.isHidden = true
            
            // Hide the table view while loading initial activities
            if activities.isEmpty {
                activityTableView.isHidden = true
            }
            
            Logger.debug("📊 activityLoadingContainer.isHidden after: \(activityLoadingContainer.isHidden)")
            Logger.debug("📊 activityLoadingIndicator.isAnimating after: \(activityLoadingIndicator.isAnimating)")
            Logger.debug("📊 activityTableView.isHidden: \(activityTableView.isHidden)")
            currentOffset = 0 // Reset offset for fresh load
            hasMoreActivities = true
        }
        
        let offset = loadMore ? currentOffset : 0
        
        ActivityService.shared.getNetworkActivities(limit: 20, offset: offset) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if loadMore {
                    self.isLoadingMoreActivities = false
                } else {
                    self.isLoadingActivities = false
                    self.activityLoadingIndicator.stopAnimating()
                    self.activityLoadingContainer.isHidden = true
                }
                
                switch result {
                case .success(let response):
                    Logger.debug("✅ Successfully fetched \(response.activities.count) activities")
                    
                    if loadMore {
                        // Append to existing activities, skipping any already
                        // shown — SSE prepends shift the pagination offset, so
                        // the next page can overlap what's on screen
                        let existingIds = Set(self.activities.map { $0.id })
                        let newActivities = response.activities.filter { !existingIds.contains($0.id) }
                        self.activities.append(contentsOf: newActivities)
                    } else {
                        // Replace activities
                        self.activities = response.activities
                    }
                    
                    // Update pagination state
                    self.currentOffset = self.activities.count ?? 0
                    self.hasMoreActivities = response.hasMore
                    
                    Logger.debug("📊 Total activities: \(self.activities.count ?? 0), hasMore: \(response.hasMore)")
                    
                    self.updateActivityFeed()
                    
                case .failure(let error):
                    Logger.debug("❌ Error fetching activities: \(error)")
                    Logger.debug("🔍 Error details: \(error.localizedDescription)")
                    
                    if !loadMore {
                        self.activities = []
                        self.updateActivityFeed()
                    }
                }
                
                self.scrollView.refreshControl?.endRefreshing()
                completion?(true)
            }
        }
    }
    
    // MARK: - Activity Feed Grouping

    /// A feed row: either one activity, or a burst of activities by the same
    /// actor within an hour, collapsed into a summary row.
    enum ActivityFeedItem {
        case single(Activity)
        case group([Activity])
        // An expanded group's member row — rendered indented under its
        // summary header so the burst reads as one nested block
        case groupChild(Activity)
    }

    /// Derived render model for the activity table. Rebuilt from `activities`
    /// in updateActivityFeed() — never mutated directly.
    var feedItems: [ActivityFeedItem] = []
    /// Groups the user has expanded inline, keyed by the group's first activity id
    var expandedGroupKeys: Set<String> = []

    /// Place-added rows are the feed's core content — never grouped
    func isStandaloneActivity(_ activity: Activity) -> Bool {
        return activity.type == .placeAdded || activity.type == .checkIn
    }

    /// Collapses consecutive same-actor activities (rolling 60-minute window)
    /// into groups of ≥2. Standalone rows interleaved in a burst don't break
    /// the surrounding group: the group is inserted back at the position of
    /// its newest member.
    func regroupActivities() {
        var items: [ActivityFeedItem] = []
        var pendingGroup: [Activity] = []
        var pendingStartIndex: Int?

        func flushGroup() {
            guard !pendingGroup.isEmpty else { return }
            let insertAt = min(pendingStartIndex ?? items.count, items.count)
            if pendingGroup.count >= 2 {
                var groupRows: [ActivityFeedItem] = [.group(pendingGroup)]
                if expandedGroupKeys.contains(pendingGroup[0].id) {
                    groupRows.append(contentsOf: pendingGroup.map { .groupChild($0) })
                }
                items.insert(contentsOf: groupRows, at: insertAt)
            } else {
                items.insert(.single(pendingGroup[0]), at: insertAt)
            }
            pendingGroup = []
            pendingStartIndex = nil
        }

        for activity in activities {
            if isStandaloneActivity(activity) {
                items.append(.single(activity))
                continue
            }
            if let last = pendingGroup.last {
                // Feed is newest-first: `activity` is older than `last`
                let sameActor = activity.actorId == pendingGroup[0].actorId
                let withinWindow = last.timestamp.timeIntervalSince(activity.timestamp) <= 3600
                if sameActor && withinWindow {
                    pendingGroup.append(activity)
                    continue
                }
                flushGroup()
            }
            pendingStartIndex = items.count
            pendingGroup.append(activity)
        }
        flushGroup()

        feedItems = items
    }

    func activityFeedItem(at row: Int) -> ActivityFeedItem? {
        return row < feedItems.count ? feedItems[row] : nil
    }

    /// The single activity backing a row, or nil for group summary rows
    func singleActivity(at row: Int) -> Activity? {
        switch activityFeedItem(at: row) {
        case .single(let activity), .groupChild(let activity):
            return activity
        default:
            return nil
        }
    }

    func toggleActivityGroup(withKey key: String) {
        let expanding = !expandedGroupKeys.contains(key)
        if expanding {
            expandedGroupKeys.insert(key)
        } else {
            expandedGroupKeys.remove(key)
        }

        // Animate the member rows in/out under their header so it's obvious
        // what the tap revealed (vs. the untouched rows below the group)
        let itemsBefore = feedItems
        regroupActivities()
        func headerIndex(in items: [ActivityFeedItem]) -> Int? {
            return items.firstIndex {
                if case .group(let g) = $0 { return g.first?.id == key }
                return false
            }
        }
        guard let header = headerIndex(in: feedItems),
              headerIndex(in: itemsBefore) == header,
              case .group(let group) = feedItems[header] else {
            activityTableView.reloadData()
            return
        }
        let childPaths = (1...group.count).map { IndexPath(row: header + $0, section: 0) }
        activityTableView.performBatchUpdates {
            if expanding {
                activityTableView.insertRows(at: childPaths, with: .fade)
            } else {
                activityTableView.deleteRows(at: childPaths, with: .fade)
            }
        }
        // Refresh the header's "Show all / Show less" state
        activityTableView.reloadRows(at: [IndexPath(row: header, section: 0)], with: .none)
    }

    func updateActivityFeed() {
        regroupActivities()
        isLoadingActivities = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show table view if Activity tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 0 {
            activityTableView.isHidden = false
        }
        
        // Update empty state
        activityEmptyStateLabel.isHidden = !activities.isEmpty
        
        // Update table footer for loading more
        if isLoadingMoreActivities && hasMoreActivities {
            activityTableView.tableFooterView = loadMoreIndicatorView
        } else {
            activityTableView.tableFooterView = nil
        }
        
        // Reload table
        activityTableView.reloadData()
        
        // Table view now handles its own scrolling with fixed height
        view.layoutIfNeeded()
    }
    
    // MARK: - Reels Methods
    func fetchReels(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isLoadingReels && !isLoadingMoreReels else {
            completion?(false)
            return
        }
        
        if loadMore && !hasMoreReels {
            completion?(false)
            return
        }
        
        if loadMore {
            isLoadingMoreReels = true
        } else {
            isLoadingReels = true
            activityLoadingContainer.isHidden = false
            activityLoadingIndicator.startAnimating()
            activityEmptyStateLabel.isHidden = true
            reelsOffset = 0
            hasMoreReels = true
            
            // Clear existing players and states when loading fresh data
            for player in reelPlayers.values {
                player.pause()
            }
            reelPlayers.removeAll()
            reelVideoStates.removeAll()
        }
        
        let offset = loadMore ? reelsOffset : 0
        let endpoint = "videos/reels/feed?limit=20&offset=\(offset)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideosResponse, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if loadMore {
                    self.isLoadingMoreReels = false
                } else {
                    self.isLoadingReels = false
                    self.activityLoadingIndicator.stopAnimating()
                    self.activityLoadingContainer.isHidden = true
                }
                
                switch result {
                case .success(let response):
                    // Filter out failed uploads and videos without URLs
                    let validReels = response.data.filter { video in
                        let hasValidUrl = video.contentType == "photo" ? video.thumbnailUrl != nil : video.videoUrl != nil
                        return video.uploadStatus == .ready && hasValidUrl
                    }
                    
                    if loadMore {
                        self.reels.append(contentsOf: validReels)
                    } else {
                        self.reels = validReels
                    }
                    
                    self.reelsOffset = self.reels.count
                    self.hasMoreReels = response.hasMore
                    self.updateReelsFeed()
                    
                case .failure(let error):
                    Logger.debug("❌ Error fetching reels: \(error)")
                    
                    // Handle specific error types gracefully
                    var isHandledError = false
                    
                    if case APIError.serverError = error {
                        // Check if this is the "too many disjunctions" error
                        let errorString = error.localizedDescription
                        if errorString.contains("Too many disjunctions") || errorString.contains("32 disjunctions") {
                            Logger.debug("🔍 Detected Firestore disjunction limit error - showing user-friendly message")
                            
                            if !loadMore {
                                self.showFirestoreQueryLimitError()
                                isHandledError = true
                            }
                        }
                    } else if case APIError.rateLimited = error {
                        Logger.debug("🔍 Rate limited loading Moments feed - showing fallback content")
                        
                        if !loadMore {
                            self.showMomentsFeedFallback()
                            isHandledError = true
                        }
                    }
                    
                    // Only show empty state if error wasn't handled with a specific fallback
                    if !isHandledError && !loadMore {
                        self.reels = []
                        self.updateReelsFeed()
                    }
                }
                
                self.scrollView.refreshControl?.endRefreshing()
                completion?(true)
            }
        }
    }
    
    func updateReelsFeed() {
        isLoadingReels = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show collection view if Moments tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 1 {
            reelsCollectionView.isHidden = false
        }
        
        // Update empty state
        if reels.isEmpty {
            activityEmptyStateLabel.text = "No moments yet. Be the first to share a moment!"
            activityEmptyStateLabel.isHidden = false
        } else {
            activityEmptyStateLabel.isHidden = true
        }
        
        // Reset to first video when loading new data
        currentReelIndex = 0
        
        // Force layout update
        view.layoutIfNeeded()
        
        // Invalidate layout to ensure proper sizing
        reelsCollectionView.collectionViewLayout.invalidateLayout()
        
        // Reload collection
        reelsCollectionView.reloadData()
        
        // Preload video for first visible item after reload
        if !reels.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.reels[0].contentType != "photo" && self.reelVideoStates[0] == nil {
                    self.reelVideoStates[0] = .loading
                    self.loadReelVideo(at: 0)
                }
            }
        }
        
        // Reset scroll position to top after loading new data
        reelsCollectionView.setContentOffset(.zero, animated: false)
        
        // Ensure we're at the first item
        if !reels.isEmpty {
            let firstIndexPath = IndexPath(item: 0, section: 0)
            reelsCollectionView.scrollToItem(at: firstIndexPath, at: .top, animated: false)
            
            // Start playing the first video after a short delay to ensure layout is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.playVideo(at: 0)
            }
        }
        
        view.layoutIfNeeded()
        
        // Start playing the first video if this is the visible tab
        if contentSegmentedControl.selectedSegmentIndex == 1 && !reels.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.playVideo(at: 0)
            }
        }
    }
    
    func showFirestoreQueryLimitError() {
        isLoadingReels = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show collection view if Moments tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 1 {
            reelsCollectionView.isHidden = false
        }
        activityEmptyStateLabel.text = "Too much content to load right now! Try refreshing in a few moments, or check back later for your Moments feed."
        activityEmptyStateLabel.isHidden = false
        
        Logger.debug("🔍 Showing user-friendly message for Firestore query limit")
        
        // Clear reels array to show empty state
        reels = []
        reelsCollectionView.reloadData()
        
        // Auto-retry after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            Logger.debug("🔍 Auto-retrying Moments feed after Firestore error")
            self?.fetchReels()
        }
    }
    
    func showMomentsFeedFallback() {
        isLoadingReels = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show collection view if Moments tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 1 {
            reelsCollectionView.isHidden = false
        }
        activityEmptyStateLabel.text = "Feed temporarily unavailable due to high activity. Pull to refresh to try again!"
        activityEmptyStateLabel.isHidden = false
        
        Logger.debug("🔍 Showing fallback message for rate limited Moments feed")
        
        // Clear reels array to show empty state
        reels = []
        reelsCollectionView.reloadData()
        
        // Enable pull-to-refresh for immediate retry
        scrollView.refreshControl?.isEnabled = true
    }
    
    // MARK: - Data Fetching
    func performInitialDataLoad() {
        
        // Unified method to load both circles and places
        Logger.debug("🚀 Starting OPTIMIZED initial data load")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Ensure connections are loaded in NetworkManager
        NetworkManager.shared.loadConnections()
        
        // Show loading state once if not already showing and no cached data
        if !isCacheValid() {
            // Only show loading states if we don't have cached data
            showLoadingState()
            showMapLoadingState()
        }
        
        // Load all data in parallel for better performance
        let group = DispatchGroup()
        
        var myCirclesResult: [Circle] = []
        var networkCirclesResult: [Circle] = []
        var activitiesResult: [Activity] = []
        var reelsResult: [PlaceVideo] = []
        var allFetchedPlaces: [Place] = []
        
        // 1. Load my circles
        group.enter()
        CircleService.shared.fetchUserCircles { [weak self] result in
            switch result {
            case .success(let circles):
                myCirclesResult = circles
                Logger.debug("✅ Fetched \(circles.count) user circles")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch user circles: \(error)")
            }
            group.leave()
        }
        
        // 2. Load network circles (parallel)
        group.enter()
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CirclesDataResponse, APIError>) in
            switch result {
            case .success(let response):
                networkCirclesResult = response.data
                Logger.debug("✅ Fetched \(response.data.count) network circles")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch network circles: \(error)")
            }
            group.leave()
        }
        
        // 3. Load activities (parallel)
        group.enter()
        ActivityService.shared.getNetworkActivities(limit: 20, offset: 0) { result in
            switch result {
            case .success(let response):
                activitiesResult = response.activities
                Logger.debug("✅ Fetched \(response.activities.count) activities")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch activities: \(error)")
            }
            group.leave()
        }
        
        // 4. Load initial moments/reels (parallel)
        group.enter()
        APIService.shared.request(
            endpoint: "videos/reels/feed?limit=20&offset=0",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            switch result {
            case .success(let response):
                reelsResult = response.data
                Logger.debug("✅ Fetched \(reelsResult.count) moments")
            case .failure(let error):
                Logger.debug("❌ Failed to fetch moments: \(error)")
            }
            group.leave()
        }
        
        // First phase completion - process circles, activities, and moments
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Update circles
            self.circles = myCirclesResult
            self.networkCircles = networkCirclesResult
            self.activities = activitiesResult
            self.reels = reelsResult
            
            let circleLoadTime = CFAbsoluteTimeGetCurrent() - startTime
            Logger.debug("⏱️ Phase 1 completed in \(String(format: "%.2f", circleLoadTime)) seconds")
            
            // Update UI
            self.updateEmptyState()
            self.updateActivityFeed()
            
            // Now fetch places from all circles in parallel.
            // With viewport loading, network circle places arrive on demand for the
            // visible map region instead — only own circles are fan-out fetched.
            let allCircles = self.useViewportNetworkLoading ? myCirclesResult : myCirclesResult + networkCirclesResult
            guard !allCircles.isEmpty else {
                self.isMapDataReady = true
                self.updateMapWhenReady()
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false
                self.hideLoadingState()
                self.userListView.refresh()
                
                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Logger.debug("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds (no circles)")
                return
            }
            
            // Phase 2: Fetch places in parallel with concurrency limit
            let placeGroup = DispatchGroup()
            let placeSemaphore = DispatchSemaphore(value: 5) // Max 5 concurrent requests
            var placesArray = [[Place]]()
            let placesLock = NSLock()
            
            for circle in allCircles {
                placeGroup.enter()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    placeSemaphore.wait()
                    
                    PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                        switch result {
                        case .success(let places):
                            placesLock.lock()
                            placesArray.append(places)
                            
                            // PROGRESSIVE LOADING: Show places as they become available
                            let currentPlaces = placesArray.flatMap { $0 }
                            placesLock.unlock()
                            
                            // Update map progressively with newly loaded places
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                // Deduplicate current places
                                var uniquePlaces: [Place] = []
                                var seenIds = Set<String>()
                                for place in currentPlaces {
                                    if !seenIds.contains(place.id) {
                                        seenIds.insert(place.id)
                                        uniquePlaces.append(place)
                                    }
                                }
                                
                                // Update map with progressive data
                                self.allPlaces = uniquePlaces
                                self.filteredPlaces = self.applyFiltersToPlaces(uniquePlaces)
                                self.mapViewController?.updatePlaces(self.filteredPlaces)
                                
                                // Trigger map region adjustment for progressive loading
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                                    self?.mapViewController?.adjustMapRegion()
                                }
                                
                                self.updatePlaceCountLabel(count: self.filteredPlaces.count)
                                
                                // Update loading message with progress and animation
                                let totalCircles = allCircles.count
                                let loadedCircles = placesArray.count
                                let progressPercentage = Int((Double(loadedCircles) / Double(totalCircles)) * 100)
                                let progressFloat = Float(loadedCircles) / Float(totalCircles)
                                
                                // Update progress bar with smooth animation
                                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                                    self.mapLoadingProgressView.setProgress(progressFloat, animated: true)
                                }
                                
                                // Update loading text with better messaging
                                UIView.transition(with: self.mapLoadingLabel, duration: 0.2, options: .transitionCrossDissolve, animations: {
                                    if uniquePlaces.count > 0 {
                                        self.mapLoadingLabel.text = "Loading places... \(uniquePlaces.count) found (\(loadedCircles)/\(totalCircles) areas)"
                                    } else {
                                        self.mapLoadingLabel.text = "Loading places... \(progressPercentage)% (\(loadedCircles)/\(totalCircles) areas)"
                                    }
                                })
                                
                                Logger.debug("🗺️ [Progressive] Updated map with \(uniquePlaces.count) places (\(loadedCircles)/\(totalCircles) circles loaded)")
                            }
                            
                        case .failure(let error):
                            Logger.debug("❌ Failed to fetch places for circle '\(circle.name)': \(error)")
                        }
                        
                        placeSemaphore.signal()
                        placeGroup.leave()
                    }
                }
            }
            
            placeGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                // Progressive loading already handled most of this in the individual callbacks
                // This is just final cleanup and optimization
                
                // Final deduplication and data integrity check
                let allPlaces = placesArray.flatMap { $0 }
                var uniquePlaces: [Place] = []
                var seenIds = Set<String>()
                
                for place in allPlaces {
                    if !seenIds.contains(place.id) {
                        seenIds.insert(place.id)
                        uniquePlaces.append(place)
                    }
                }
                
                // Final data assignment
                self.allPlaces = uniquePlaces
                
                // Update available categories now that we have all places
                self.updateAvailableCategories()
                
                // Extract user's own places
                let userCircleIds = Set(myCirclesResult.map { $0.id })
                self.userOwnPlaces = uniquePlaces.filter { place in
                    if let circleId = place.circleId {
                        return userCircleIds.contains(circleId)
                    }
                    return false
                }
                
                // Cache the final places data
                self.cachedPlaces = uniquePlaces
                self.placesCacheExpiry = Date().addingTimeInterval(5 * 60) // 5 minutes
                
                // Final map update with complete data (progressive loading already showed most places)
                self.isMapDataReady = true
                let finalPlaces = self.applyFiltersToPlaces(uniquePlaces)
                self.filteredPlaces = finalPlaces
                self.mapViewController?.updatePlaces(finalPlaces)
                
                // Trigger final map region adjustment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.mapViewController?.adjustMapRegion()
                }
                
                self.updatePlaceCountLabel(count: finalPlaces.count)
                
                // Hide loading state - places are fully loaded
                self.hideMapLoadingState()
                
                // Final cleanup
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false
                self.hideLoadingState()
                self.userListView.refresh()
                CirclesHomeViewController.hasLoadedInitialData = true
                
                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Logger.debug("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds")
                Logger.debug("   - My circles: \(myCirclesResult.count)")
                Logger.debug("   - Network circles: \(networkCirclesResult.count)")
                Logger.debug("   - Total places: \(uniquePlaces.count)")
                Logger.debug("   - Activities: \(activitiesResult.count)")
                Logger.debug("   - Moments: \(reelsResult.count)")
            }
        }
    }
    
    func showMapLoadingState() {
        // Prevent showing loading state multiple times
        guard !isShowingLoadingUI else { 
            Logger.debug("🗺️ Map loading state already showing")
            return 
        }
        
        Logger.debug("🗺️ Showing map with loading indicator")
        isShowingLoadingUI = true
        
        // Show map immediately but hide the loading overlay
        mapLoadingView.isHidden = true
        mapContainerView.isHidden = false
        
        // Show filters and expand button immediately
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
        
        // Just show a small loading indicator in the corner
        mapLoadingIndicator.startAnimating()
        
        // Hide place count labels until loaded
        mapViewController?.hidePlaceCount()
        mapPlaceCountLabel.isHidden = true
    }
    
    func hideMapLoadingState() {
        Logger.debug("🗺️ Hiding map loading state, showing populated map")
        Logger.debug("🗺️ About to call fetchActivities from hideMapLoadingState")
        isShowingLoadingUI = false
        
        // Complete the progress bar with satisfaction animation
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.mapLoadingProgressView.setProgress(1.0, animated: true)
        } completion: { _ in
            // Wait a moment to show completion, then fade out
            UIView.animate(withDuration: 0.3, delay: 0.1, animations: {
                self.mapLoadingView.alpha = 0
            }) { _ in
                self.mapLoadingView.isHidden = true
                self.mapLoadingIndicator.stopAnimating()
                self.mapLoadingProgressView.setProgress(0.0, animated: false) // Reset for next time
            }
        }
        
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
        
        // Show place count now that loading is complete with animation.
        // (Only the home's own pill — the embedded map's internal pill stays
        // hidden so two counts never stack in the same corner.)
        mapPlaceCountLabel.alpha = 0
        mapPlaceCountLabel.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.mapPlaceCountLabel.alpha = 1
        }
        
        // Activities and moments are already loaded in performInitialDataLoad
        // No need to fetch again here
    }
    
    // NEW: Immediate loading state to prevent empty map confusion
    func showMapLoadingStateImmediate() {
        Logger.debug("🗺️ [IMMEDIATE] Showing map loading state on viewWillAppear")
        
        // Show map container immediately so it's not empty
        mapContainerView.isHidden = false
        
        // Show loading overlay with informative message
        mapLoadingView.isHidden = false
        mapLoadingIndicator.startAnimating()
        mapLoadingLabel.text = "Loading your places..."
        
        // Reset progress bar to beginning
        mapLoadingProgressView.setProgress(0.0, animated: false)
        
        // Add subtle animation to the loading view
        mapLoadingView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.mapLoadingView.alpha = 1
        }
        
        // Show UI controls so user knows this is the map section
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
        
        // Hide place count until we have data
        mapPlaceCountLabel.isHidden = true
        
        isShowingLoadingUI = true
    }
    
    // PROGRESSIVE PLACE LOADING: Show cached places immediately
    func extractAndShowCachedPlaces() {
        // For now, skip cached place extraction since creating dummy Place objects
        // requires complex initialization. The immediate loading indicator is more important
        // and provides the main UX benefit the user requested.
        
        // Update loading message to indicate we found cached circles
        DispatchQueue.main.async { [weak self] in
            self?.mapLoadingLabel.text = "Found \(self?.circles.count ?? 0) circles, loading places..."
            Logger.debug("📦 [Cache→Map] Found cached circles, will load places next")
        }
    }
    
    // PROGRESSIVE MAP UPDATES: Update map with places as they become available
    func updateMapProgressively(with places: [Place], isFromCache: Bool = false) {
        // Only update if we have places and the map is ready
        guard !places.isEmpty else { return }
        
        // Store places
        if isFromCache {
            // Cached places are temporary - will be replaced with full data
            Logger.debug("🗺️ [Progressive] Showing \(places.count) cached places temporarily")
        } else {
            // Full place data. With viewport loading, merge instead of replacing
            // so already-fetched viewport (network) places aren't wiped out.
            if useViewportNetworkLoading {
                self.allPlaces = removeDuplicatePlaces(places + self.allPlaces)
            } else {
                self.allPlaces = places
            }
            self.userOwnPlaces = places.filter { place in
                circles.contains { circle in
                    circle.places?.contains(place.id) == true
                }
            }
            Logger.debug("🗺️ [Progressive] Populated map with \(places.count) full places")
            
            // Update available categories now that we have places
            self.updateAvailableCategories()
        }
        
        // Apply filters and update map (include merged viewport places, not just the incoming batch)
        let placesToDisplay = applyFiltersToPlaces((useViewportNetworkLoading && !isFromCache) ? allPlaces : places)
        self.filteredPlaces = placesToDisplay

        // Update map with current places
        self.mapViewController?.updatePlaces(placesToDisplay)

        // Trigger map region adjustment for progressive updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.mapViewController?.adjustMapRegion()
        }

        updatePlaceCountLabel(count: placesToDisplay.count)
        
        // If we have full data, hide loading state
        if !isFromCache {
            self.isMapDataReady = true
            self.hideMapLoadingState()
        } else {
            // For cached data, update loading message
            DispatchQueue.main.async { [weak self] in
                self?.mapLoadingLabel.text = "Refreshing place details..."
            }
        }
        
        updateEmptyState()
    }
    
    func fetchCircles(completion: (() -> Void)? = nil) {
        // Only show loading state on the very first app launch
        isLoadingCircles = true
        
        Logger.debug("🔍 DEBUG fetchCircles() called - About to call CircleService.fetchUserCircles")
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            Logger.debug("🔍 DEBUG fetchCircles() completion called")
            DispatchQueue.main.async {
                self.isLoadingCircles = false
                
                switch result {
                case .success(let circles):
                    Logger.debug("✅ Successfully fetched \(circles.count) user circles")
                    Logger.debug("🔍 DEBUG - User Circle Details:")
                    for (index, circle) in circles.enumerated() {
                        Logger.debug("   Circle \(index + 1): '\(circle.name)' (ID: \(circle.id), Places: \(circle.placesCount ?? 0))")
                    }
                    self.circles = circles
                    Logger.debug("🔍 DEBUG - After assignment, self.circles.count: \(self.circles.count)")
                    self.fetchAllPlacesFromCircles()
                    completion?()
                    // Don't mark as loaded here - wait until places are fetched
                case .failure(let error):
                    Logger.debug("❌ Error fetching circles: \(error.localizedDescription)")
                    Logger.debug("❌ Full error: \(error)")
                    completion?()
                    
                    // If it's a duplicate request error, still need to clean up state
                    if case .duplicateRequest = error as? APIError {
                        Logger.debug("❌ Duplicate request detected - cleaning up state")
                        self.isLoadingCircles = false
                        self.isPerformingInitialLoad = false
                        self.hideLoadingState()
                        self.hideMapLoadingState()
                        return
                    }
                    
                    // Don't use sample circles - show empty state instead
                    self.circles = []
                    self.allPlaces = []
                    self.userOwnPlaces = []
                    self.isLoadingCircles = false
                    self.isPerformingInitialLoad = false
                    self.hideLoadingState()
                    self.hideMapLoadingState()
                }
                
                self.updateEmptyState()
            }
        }
    }
    
    func fetchNetworkCircles(completion: (() -> Void)? = nil) {
        // Use CircleService to fetch network circles
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    Logger.debug("✅ Successfully fetched \(response.data.count) network circles")
                    let currentUserId = AuthService.shared.getUserId() ?? ""
                    let normalizedUserId = IDNormalizer.normalize(currentUserId) ?? currentUserId
                    for circle in response.data {
                        let normalizedOwner = IDNormalizer.normalize(circle.owner) ?? circle.owner
                        Logger.debug("📍 Network circle received: \(circle.name) by \(circle.owner) (normalized: \(normalizedOwner)), privacy: \(circle.privacy.rawValue)")
                        if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                            Logger.debug("⚠️ WARNING: Network circles contains user's own circle: \(circle.name)")
                            Logger.debug("   Circle owner: \(circle.owner)")
                            Logger.debug("   Current user: \(currentUserId)")
                            Logger.debug("   Normalized owner: \(normalizedOwner)")
                            Logger.debug("   Normalized user: \(normalizedUserId)")
                        }
                    }
                    self.networkCircles = response.data
                    self.updateEmptyState()
                    completion?()
                case .failure(let error):
                    Logger.debug("❌ Error fetching network circles: \(error.localizedDescription)")
                    completion?()
                    
                    // If it's a duplicate request error, just ignore it
                    if case .duplicateRequest = error {
                        return
                    }
                    
                    self.networkCircles = []
                    self.updateEmptyState()
                }
            }
        }
    }
    
    func createSampleCircles() -> [Circle] {
        let userId = AuthService.shared.getUserId() ?? "user123"
        
        let date = Date()
        
        // Create sample circles
        let travelCircle = Circle(
            id: "circle1",
            name: "New York Trip",
            description: "All my favorite places in NYC",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            editors: nil,
            editorsDetails: nil,
            places: ["place1", "place2", "place3"],
            placesCount: 3,
            placesWithDetails: nil,
            privacy: .private,
            allowNetworkEdit: false,
            category: .travel,
            location: "New York, NY",
            tags: ["travel", "nyc", "vacation"],
            sharedWith: ["friend1", "friend2"],
            followers: nil,
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 7), // 7 days ago
            updatedAt: date.addingTimeInterval(-3600) // 1 hour ago
        )
        
        let foodCircle = Circle(
            id: "circle2",
            name: "Best Restaurants",
            description: "My favorite places to eat",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            editors: nil,
            editorsDetails: nil,
            places: ["place4", "place5"],
            placesCount: 2,
            placesWithDetails: nil,
            privacy: .myNetwork,
            allowNetworkEdit: true,
            category: .food,
            location: nil,
            tags: ["food", "restaurants", "dining"],
            sharedWith: nil,
            followers: ["friend3", "friend4"],
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 14), // 14 days ago
            updatedAt: date.addingTimeInterval(-86400) // 1 day ago
        )
        
        let shoppingCircle = Circle(
            id: "circle3",
            name: "Shopping Spots",
            description: "Best places to shop",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            editors: nil,
            editorsDetails: nil,
            places: ["place6", "place7", "place8", "place9"],
            placesCount: 4,
            placesWithDetails: nil,
            privacy: .public,
            allowNetworkEdit: false,
            category: .shopping,
            location: nil,
            tags: ["shopping", "retail", "fashion"],
            sharedWith: nil,
            followers: ["friend5", "friend6", "friend7"],
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 30), // 30 days ago
            updatedAt: date.addingTimeInterval(-43200) // 12 hours ago
        )
        
        return [travelCircle, foodCircle, shoppingCircle]
    }
    
    func updateEmptyState() {
        // Hide empty state if loading
        if isLoadingCircles || isLoadingPlaces {
            emptyStateView.isHidden = true
            return
        }
        
        if isSearching {
            // The overlay itself shows results; only surface the empty state
            // when NEITHER places nor people matched.
            emptyStateView.isHidden = !(filteredPlaces.isEmpty && searchedUsers.isEmpty)
            emptyStateLabel.text = "No results found"
        } else {
            let isEmpty = isShowingNetworkCircles ? networkCircles.isEmpty : circles.isEmpty
            emptyStateView.isHidden = !isEmpty
            
            // Update empty state message based on filter
            if isShowingNetworkCircles {
                emptyStateLabel.text = "No circles from your network yet"
            } else {
                emptyStateLabel.text = "You don't have any circles yet"
            }
        }
    }
    
    override func showLoadingState() {
        loadingContainerView.alpha = 0
        loadingContainerView.isHidden = false
        loadingIndicator.startAnimating()
        emptyStateView.isHidden = true
        
        // Update loading message based on what's loading
        if isLoadingCircles && isLoadingPlaces {
            loadingLabel.text = "Loading your circles and places..."
        } else if isLoadingCircles {
            loadingLabel.text = "Loading your circles..."
        } else if isLoadingPlaces {
            loadingLabel.text = "Loading places..."
        } else {
            loadingLabel.text = "Loading..."
        }
        
        // Fade in animation
        UIView.animate(withDuration: 0.3) {
            self.loadingContainerView.alpha = 1
        }
    }
    
    override func hideLoadingState() {
        UIView.animate(withDuration: 0.3, animations: {
            self.loadingContainerView.alpha = 0
        }) { _ in
            self.loadingContainerView.isHidden = true
            self.loadingIndicator.stopAnimating()
        }
        updateEmptyState()
    }
    
    func fetchAllPlacesFromCircles() {
        // Reset map data ready flag at the start of any fetch
        isMapDataReady = false
        
        Logger.debug("📍 fetchAllPlacesFromCircles() - Starting fetch process")
        Logger.debug("📍 User circles count: \(circles.count)")
        Logger.debug("📍 Network circles count: \(networkCircles.count)")
        
        // ALWAYS fetch all user places to ensure we have the complete 124 places
        // Don't use cached data for user places as it may be incomplete
        Logger.debug("📍 Fetching all places (cache disabled to ensure complete data)")
        
        // Note: We're commenting out the cache check to ensure we get all 124 user places
        // if shouldUseCachedData() {
        //     Logger.debug("📍 Using cached places data (\(cachedPlaces.count) places)")
        //     self.allPlaces = cachedPlaces
        //     ... cache logic ...
        //     return
        // }
        
        var allFetchedPlaces: [Place] = []
        let group = DispatchGroup()
        
        // Show loading state for places and reset map data ready flag
        isLoadingPlaces = true
        isMapDataReady = false
        
        // Loading state is already shown by performInitialDataLoad, don't show again
        
        Logger.debug("📍 fetchAllPlacesFromCircles called (cache invalid or expired)")
        Logger.debug("📍 User circles count: \(circles.count)")
        Logger.debug("📍 Network circles count: \(networkCircles.count)")
        
        // If no circles at all, just update UI and return
        if circles.isEmpty && networkCircles.isEmpty {
            Logger.debug("📍 No circles to fetch places from")
            self.allPlaces = []
            self.userOwnPlaces = []
            self.filteredPlaces = []
            
            // Mark data as ready (empty) and update map
            self.isMapDataReady = true
            self.updateMapWhenReady()
            
            self.isLoadingPlaces = false
            self.isPerformingInitialLoad = false
            self.hideLoadingState()
            // Don't set hasLoadedInitialData here - we have no data
            return
        }
        
        // Debug network circles
        for circle in networkCircles {
            Logger.debug("📍 Network circle: \(circle.name) by \(circle.owner), privacy: \(circle.privacy)")
        }
        
        // Fetch user's own places
        var userPlacesCount = 0
        Logger.debug("📍 Starting to fetch places from \(circles.count) user circles:")
        for (index, circle) in circles.enumerated() {
            Logger.debug("   Circle \(index + 1)/\(circles.count): '\(circle.name)' (ID: \(circle.id), Expected places: \(circle.placesCount ?? 0))")
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                switch result {
                case .success(let places):
                    Logger.debug("✅ Fetched \(places.count) places from USER circle '\(circle.name)' (expected: \(circle.placesCount ?? 0))")
                    userPlacesCount += places.count
                    allFetchedPlaces.append(contentsOf: places)
                case .failure(let error):
                    Logger.debug("❌ Failed to fetch places for USER circle '\(circle.name)' (id: \(circle.id)): \(error)")
                }
                group.leave()
            }
        }
        
        // Always fetch network circles for map view (need to show connection places)
        // First, fetch network circles if we don't have them
        if networkCircles.isEmpty && !circles.isEmpty {
            group.enter()
            // Fetch network circles first
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.networkCircles = response.data
                    // Now fetch places from network circles
                    // (skipped with viewport loading — places arrive per visible region)
                    if self?.useViewportNetworkLoading != true {
                        for circle in response.data {
                            group.enter()
                            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                                switch result {
                                case .success(let places):
                                    Logger.debug("✅ Found \(places.count) places in network circle: \(circle.name)")
                                    Logger.debug("   Circle owner ID: \(circle.owner)")
                                    allFetchedPlaces.append(contentsOf: places)
                                case .failure(let error):
                                    Logger.debug("Failed to fetch places for network circle \(circle.id): \(error)")
                                }
                                group.leave()
                            }
                        }
                    }
                case .failure(let error):
                    Logger.debug("Failed to fetch network circles: \(error)")
                    // If it's a duplicate request error, retry
                    if case .duplicateRequest = error {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.fetchNetworkCircles()
                        }
                    }
                }
                group.leave()
            }
        } else if !useViewportNetworkLoading {
            // Use existing network circles
            for circle in networkCircles {
                Logger.debug("📍 Fetching places for network circle: \(circle.name) (\(circle.id))")
                group.enter()
                PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                    switch result {
                    case .success(let places):
                        Logger.debug("✅ Found \(places.count) places in network circle: \(circle.name)")
                        Logger.debug("   Circle owner ID: \(circle.owner)")
                        allFetchedPlaces.append(contentsOf: places)
                    case .failure(let error):
                        Logger.debug("❌ Failed to fetch places for network circle \(circle.name) (\(circle.id)): \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main, execute: { [weak self] in
            guard let self = self else { return }
            
            Logger.debug("📍 PLACE FETCH COMPLETE - DETAILED SUMMARY:")
            Logger.debug("   Total raw places fetched: \(allFetchedPlaces.count)")
            Logger.debug("   User places fetched: \(userPlacesCount)")
            Logger.debug("   User circles count: \(self.circles.count)")
            Logger.debug("   Network circles count: \(self.networkCircles.count)")
            
            // Count user places before deduplication
            let currentUserId = AuthService.shared.getUserId() ?? ""
            let userCircleIds = self.circles.map { $0.id }
            
            // Also check by owner ID in case circle IDs don't match
            let userPlacesBeforeDedup = allFetchedPlaces.filter { place in
                // First check if circleId is in user's circles
                if let circleId = place.circleId, userCircleIds.contains(circleId) {
                    return true
                }
                // Also check if the circle this place belongs to is owned by the current user
                // This handles cases where network circles might include user's own circles
                if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                    return IDNormalizer.isSameUser(circle.owner, currentUserId)
                }
                return false
            }
            let networkPlacesBeforeDedup = allFetchedPlaces.filter { place in
                guard let circleId = place.circleId else { return false }
                return !userCircleIds.contains(circleId) && 
                !self.networkCircles.contains(where: { $0.id == circleId && IDNormalizer.isSameUser($0.owner, currentUserId) })
            }
            
            Logger.debug("📍 BEFORE DEDUPLICATION:")
            Logger.debug("   User places: \(userPlacesBeforeDedup.count)")
            Logger.debug("   Network places: \(networkPlacesBeforeDedup.count)")
            
            // Deduplicate places that might exist in multiple circles
            let deduplicatedPlaces = self.removeDuplicatePlaces(allFetchedPlaces)
            self.allPlaces = deduplicatedPlaces
            
            // Count after deduplication using same logic as filter
            let userPlacesAfterDedup = deduplicatedPlaces.filter { place in
                if let circleId = place.circleId, userCircleIds.contains(circleId) {
                    return true
                }
                if let circleId = place.circleId, let circle = self.networkCircles.first(where: { $0.id == circleId }) {
                    return IDNormalizer.isSameUser(circle.owner, currentUserId)
                }
                return false
            }
            let networkPlacesAfterDedup = deduplicatedPlaces.filter { place in
                guard let circleId = place.circleId else { return false }
                return !userCircleIds.contains(circleId) && 
                       !self.networkCircles.contains(where: { $0.id == circleId && IDNormalizer.isSameUser($0.owner, currentUserId) })
            }
            
            Logger.debug("📍 AFTER DEDUPLICATION:")
            Logger.debug("   User places: \(userPlacesAfterDedup.count) (should be 124 according to user)")
            Logger.debug("   Network places: \(networkPlacesAfterDedup.count)")
            Logger.debug("   Total unique places: \(deduplicatedPlaces.count)")
            
            // Store user's own places separately for search filtering
            self.userOwnPlaces = userPlacesAfterDedup
            
            // Cache the deduplicated places with expiry time
            self.cachedPlaces = deduplicatedPlaces
            self.placesCacheExpiry = Date().addingTimeInterval(self.cacheExpiryMinutes * 60)
            
            // Apply filtering to fetched places
            let mapFilteredPlaces = self.applyFiltersToPlaces(deduplicatedPlaces)
            
            // Update location status label
            var placesWithLocation = 0
            for place in mapFilteredPlaces {
                if place.location?.clLocation != nil {
                    placesWithLocation += 1
                }
            }
            let placesWithoutLocation = mapFilteredPlaces.count - placesWithLocation
            
            if placesWithoutLocation > 0 {
                self.locationStatusLabel.text = "\(placesWithoutLocation) place\(placesWithoutLocation == 1 ? "" : "s") couldn't be located on the map"
                self.locationStatusLabel.isHidden = false
            } else {
                self.locationStatusLabel.isHidden = true
            }
            
            Logger.debug("📍 Map Update Summary:")
            Logger.debug("   Total filtered places: \(mapFilteredPlaces.count)")
            Logger.debug("   Places with location: \(placesWithLocation)")
            Logger.debug("   Places without location: \(placesWithoutLocation)")
            
            // Update filteredPlaces for UI consistency (search, empty states, etc.)
            self.filteredPlaces = mapFilteredPlaces
            
            // Use progressive loading instead of waiting for everything
            self.updateMapProgressively(with: deduplicatedPlaces, isFromCache: false)
                
            // Hide loading state
            self.isLoadingPlaces = false
            self.isPerformingInitialLoad = false // Reset initial load flag
            self.hideLoadingState()

            // With viewport loading, re-fetch network places for the current
            // region so refresh paths (place added/edited) pick up changes
            if self.useViewportNetworkLoading, let mapVC = self.mapViewController {
                self.fetchedViewportCircles.removeAll()
                self.fetchViewportPlaces(region: mapVC.currentRegion, for: mapVC)
            }

            // Mark that we've loaded data only if we actually have data
            if !self.circles.isEmpty || !allFetchedPlaces.isEmpty {
                CirclesHomeViewController.hasLoadedInitialData = true
            }
        })
    }
    
    // MARK: - Map Update Coordination
    
    func updateMapWhenReady() {
        // Only update map if data is ready and we have places to display
        guard isMapDataReady else {
            Logger.debug("🗺️ Map data not ready yet, deferring update")
            return
        }
        
        // Apply current filters to get the places to display
        let placesToDisplay = applyFiltersToPlaces(allPlaces)
        
        Logger.debug("🗺️ Updating map with \(placesToDisplay.count) places (data ready)")
        
        // Update the map
        self.mapViewController?.updatePlaces(placesToDisplay)
        
        // Trigger map region adjustment to fit all results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.mapViewController?.adjustMapRegion()
        }
        
        // Update place count label
        updatePlaceCountLabel(count: placesToDisplay.count)
        
        // Hide map loading state and show the map now that data is ready
        self.hideMapLoadingState()
        
        // Update empty state
        self.updateEmptyState()
    }
    
    func updatePlaceCountLabel(count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if count > 0 {
                self.mapPlaceCountLabel.setTitle("\(count)", for: .normal)
                self.mapPlaceCountLabel.isHidden = false
            } else {
                self.mapPlaceCountLabel.isHidden = true
            }
        }
    }
    
    func setupNavigationBar() {
        // Create help button for left side
        let helpButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(helpButtonTapped)
        )

        // Invite/connect button (same share-invite flow as the My Network tab)
        let inviteButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(inviteButtonTapped)
        )
        inviteButton.accessibilityLabel = "Invite Connections"

        navigationItem.leftBarButtonItems = [helpButton, inviteButton]
        
        Task { @MainActor in
            navigationItem.rightBarButtonItems = makeRightBarButtons()
        }
    }

    /// Builds the right nav-bar buttons for BOTH construction sites
    /// (setupNavigationBar and updateNavigationBarForSubscription) so the two
    /// can't drift. Reuses the stored notification/rewards buttons to keep
    /// their badge custom views alive across rebuilds.
    @MainActor
    func makeRightBarButtons() -> [UIBarButtonItem] {
        let checkInButton = UIBarButtonItem(
            image: UIImage(systemName: "checkmark.circle"),
            style: .plain,
            target: self,
            action: #selector(checkInButtonTapped)
        )

        let rewardsButton = self.rewardsBarButton ?? UIBarButtonItem(
            image: UIImage(systemName: "dollarsign.circle"),
            style: .plain,
            target: self,
            action: #selector(rewardsButtonTapped)
        )
        rewardsButton.accessibilityLabel = "Rewards"
        self.rewardsBarButton = rewardsButton

        let notificationButton = self.notificationBarButton ?? UIBarButtonItem(
            image: UIImage(systemName: "bell"),
            style: .plain,
            target: self,
            action: #selector(notificationButtonTapped)
        )
        self.notificationBarButton = notificationButton

        var rightBarButtons = [checkInButton, rewardsButton, notificationButton]

        if !SubscriptionManager.shared.isSubscribed {
            let upgradeButton = UIBarButtonItem(
                image: UIImage(systemName: "crown.fill"),
                style: .plain,
                target: self,
                action: #selector(upgradeButtonTapped)
            )
            upgradeButton.tintColor = Constants.Colors.primary
            rightBarButtons.insert(upgradeButton, at: 0) // Add as first button
        }

        return rightBarButtons
    }
    
    // MARK: - Notifications
    
    func setupNotifications() {
        // Listen for circle deletion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCircleDeleted(_:)),
            name: .circleDeleted,
            object: nil
        )

        // Refresh the $ badge the moment points are earned or spent
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRewardBalanceChanged),
            name: .rewardBalanceChanged,
            object: nil
        )

        // Refresh when the quick-start flow adds places (it's modal, so the
        // usual pop-triggered viewWillAppear refresh doesn't fire)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickStartPlaceAdded),
            name: Notification.Name("PlaceAdded"),
            object: nil
        )
        
        // Listen for refresh circles notification (e.g., when a place is added)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefreshCircles),
            name: NSNotification.Name("RefreshCircles"),
            object: nil
        )
        
        // Invalidate cache when app comes to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // Listen for onboarding tour request from Help view
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnboardingTour),
            name: Notification.Name("ShowOnboardingTour"),
            object: nil
        )
        
        // Listen for moment deletion to update activity feed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMomentDeleted(_:)),
            name: Notification.Name("MomentDeleted"),
            object: nil
        )
    }
    
    @objc func handleCircleDeleted(_ notification: Notification) {
        guard let circleId = notification.userInfo?["circleId"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Remove the circle from our local array
            if let index = self.circles.firstIndex(where: { $0.id == circleId }) {
                self.circles.remove(at: index)
                
                // Reload UI
                if self.isShowingNetworkCircles == false {
                    self.fetchAllPlacesFromCircles()
                }
            }
            
            // Also remove from network circles if present
            if let index = self.networkCircles.firstIndex(where: { $0.id == circleId }) {
                self.networkCircles.remove(at: index)
            }
            
            // Note: CircleManager caching removed - using local arrays only
            
            // Update empty state
            self.updateEmptyState()
        }
    }
    
    @objc func handleRefreshCircles() {
        // Invalidate cache when circles/places are modified
        invalidateCache()
        // Refresh circles to get updated place counts
        refreshData()
    }
    
    @objc func handleAppWillEnterForeground() {
        // Check if cache is expired when app comes to foreground
        if !isCacheValid() {
            Logger.debug("📱 App entering foreground - cache expired, will refresh on next load")
            // Don't refresh automatically, just invalidate cache
            // Data will be refreshed when view appears
        }
    }
    
    @objc func handleMomentDeleted(_ notification: Notification) {
        guard let videoId = notification.userInfo?["videoId"] as? String else { return }
        
        Logger.debug("📢 Received MomentDeleted notification for video: \(videoId)")
        
        // Find the indices of activities to remove
        var indexPathsToRemove: [IndexPath] = []
        var indicesToRemove: [Int] = []
        
        for (index, activity) in activities.enumerated() {
            if activity.targetType == "place_video" && activity.targetId == videoId {
                Logger.debug("🗑️ Found activity to remove at index \(index) for video: \(videoId)")
                indexPathsToRemove.append(IndexPath(row: index, section: 0))
                indicesToRemove.append(index)
            }
        }
        
        // Remove from data source (in reverse order to maintain indices)
        for index in indicesToRemove.reversed() {
            activities.remove(at: index)
        }
        
        if !indexPathsToRemove.isEmpty {
            Logger.debug("✅ Removing \(indexPathsToRemove.count) activity(ies) from feed")
            
            // Update UI if activity feed is visible
            if contentSegmentedControl.selectedSegmentIndex == 0 { // Activity tab
                // Use performBatchUpdates for proper animation and consistency
                activityTableView.performBatchUpdates({
                    activityTableView.deleteRows(at: indexPathsToRemove, with: .fade)
                }) { [weak self] _ in
                    // Update empty state after animation completes
                    self?.activityEmptyStateLabel.isHidden = !(self?.activities.isEmpty ?? true)
                }
            } else {
                // Not visible: keep the hidden table's row count in sync with the
                // shrunk data source so it can't crash when shown again
                activityTableView.reloadData()
                activityEmptyStateLabel.isHidden = activities.isEmpty
            }
        }
    }
    
    @objc func handleShowOnboardingTour(_ notification: Notification) {
        // Called when user taps "Show Welcome Tour" from Help view
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set tour mode flag
            self.isShowingWelcomeTour = true
            
            // Make sure we're on the Home tab
            if let tabBar = self.tabBarController {
                tabBar.selectedIndex = 0
            }
            
            // Force show the suggested users overlay (bypassing all checks)
            self.forceShowSuggestedUsersOverlay()
            
            // The add place tutorial will be shown after suggested users is dismissed
            // through the normal flow in didTapNext/didTapSkip
        }
    }
    
    // MARK: - Actions
    @objc func addButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        // Present modally wrapped in navigation controller for cancel button
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }
    
    @objc func upgradeButtonTapped() {
        SubscriptionManager.shared.showPaywall(from: self, reason: .generalUpgrade)
    }
    
    func updateNavigationBarForSubscription() {
        Task { @MainActor in
            navigationItem.rightBarButtonItems = makeRightBarButtons()
        }
    }
    
    
    
    @objc func expandMapButtonTapped() {
        // Set flag to prevent map updates when returning
        isReturningFromFullScreenMap = true
        
        // If we have a connection filter but no network circles, fetch them first
        if let connectionId = selectedConnectionId, 
           connectionId != "my_places_only",
           networkCircles.isEmpty {
            Logger.debug("📍 Fetching network circles before expanding map...")
            fetchNetworkCircles { [weak self] in
                guard let self = self else { return }
                self.presentFullScreenMapWithCurrentState()
            }
        } else {
            presentFullScreenMapWithCurrentState()
        }
    }
    
    func presentFullScreenMapWithCurrentState() {
        // Present full screen map with current filter states, opening at the
        // same region the embedded map is showing
        let fullScreenMap = FullScreenMapViewController(
            places: allPlaces,
            initialRegion: mapViewController?.currentRegion,
            selectedCategory: selectedCategory,  // Pass current category filter
            selectedConnectionId: selectedConnectionId  // Pass current connection filter
        )
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.selectedConnectionUser = selectedConnectionUser
        fullScreenMap.delegate = self  // Set delegate to handle place selection
        
        // Separate user places from connection places
        let buckets = buildConnectionPlaceBuckets()

        // Update the full screen map with connections data
        fullScreenMap.updatePlacesWithConnections(
            buckets.userPlaces,
            connections: NetworkManager.shared.connections,
            connectionPlaces: buckets.connectionPlaces
        )
        fullScreenMap.modalPresentationStyle = .fullScreen
        presentedFullScreenMap = fullScreenMap
        present(fullScreenMap, animated: true)
    }
    
    @objc func emptyStateFindFriendsTapped() {
        // Jump to My Network and open the contacts import flow
        tabBarController?.selectedIndex = 1
        NotificationCenter.default.post(name: Notification.Name("ShowContactsImport"), object: nil)
    }

    @objc func handleQuickStartPlaceAdded() {
        // Debounced full refetch (places were added outside the normal flow)
        updateMapPlaces()
    }

    /// Opens the lightweight "add 3 places" flow, seeding the default circles
    /// first if the account has none yet.
    @objc func openQuickStartAddPlaces() {
        if let circle = circles.first(where: { $0.name == "Favorite Local Spots" }) ?? circles.first {
            presentQuickStart(with: circle)
            return
        }

        // No circles: retry the (idempotent) server-side default seeding first
        APIService.shared.request(
            endpoint: "users/me/complete-onboarding",
            method: .post,
            body: [:]
        ) { [weak self] (_: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                CircleService.shared.fetchUserCircles { circlesResult in
                    DispatchQueue.main.async {
                        if case .success(let fetched) = circlesResult, !fetched.isEmpty {
                            self.circles = fetched
                            let target = fetched.first(where: { $0.name == "Favorite Local Spots" }) ?? fetched[0]
                            self.presentQuickStart(with: target)
                        } else {
                            self.promptCreateFirstCircle()
                        }
                    }
                }
            }
        }
    }

    func presentQuickStart(with circle: Circle) {
        let quickStartVC = QuickStartAddPlacesViewController(targetCircle: circle)
        let navController = UINavigationController(rootViewController: quickStartVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }

    @objc func quickAddPlaceButtonTapped() {
        // Debug: Log current circle state
        Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - circles.count: \(circles.count)")
        Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - circles.isEmpty: \(circles.isEmpty)")
        Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - isLoadingCircles: \(isLoadingCircles)")
        Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - hasLoadedInitialData: \(CirclesHomeViewController.hasLoadedInitialData)")
        if !circles.isEmpty {
            Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - circles: \(circles.map { $0.name })")
        } else {
            Logger.debug("🔍 DEBUG quickAddPlaceButtonTapped - No circles found! This is why picker isn't showing")
        }
        
        // If user has circles, show circle picker. Otherwise, silently seed the
        // default circles and continue — no "create a circle first" wall
        if circles.isEmpty {
            recoverCirclesThenAddPlace()
        } else if circles.count == 1 {
            // If only one circle, go directly to add place
            let addPlaceVC = AddPlaceViewController(circleId: circles[0].id, circles: circles)
            navigationController?.pushViewController(addPlaceVC, animated: true)
        } else if let lastUsedId = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey),
                  circles.contains(where: { $0.id == lastUsedId }) {
            // Skip the picker: default to the circle the user last added a place to.
            // The add screen's circle dropdown still lets them switch.
            let addPlaceVC = AddPlaceViewController(circleId: lastUsedId, circles: circles)
            navigationController?.pushViewController(addPlaceVC, animated: true)
        } else {
            // Show circle picker
            showCirclePicker()
        }
    }
    
    /// Ensures at least one circle exists (the server-side default seeding is
    /// idempotent), then continues straight into the add-place flow. Only if
    /// seeding fails does the user see the create-circle prompt.
    func recoverCirclesThenAddPlace() {
        APIService.shared.request(
            endpoint: "users/me/complete-onboarding",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    CircleService.shared.fetchUserCircles { [weak self] circlesResult in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            if case .success(let fetched) = circlesResult, !fetched.isEmpty {
                                self.circles = fetched
                                let target = fetched.first(where: { $0.name == "Favorite Local Spots" }) ?? fetched[0]
                                let addPlaceVC = AddPlaceViewController(circleId: target.id, circles: fetched)
                                self.navigationController?.pushViewController(addPlaceVC, animated: true)
                            } else {
                                self.promptCreateFirstCircle()
                            }
                        }
                    }
                case .failure(let error):
                    Logger.debug("Onboarding retry before add-place failed: \(error)")
                    self.promptCreateFirstCircle()
                }
            }
        }
    }

    func promptCreateFirstCircle() {
        let alert = UIAlertController(
            title: "No Circles Yet",
            message: "You need to create a circle first before adding places.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Create Circle", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let createCircleVC = CreateCircleViewController()
            createCircleVC.delegate = self
            let navController = UINavigationController(rootViewController: createCircleVC)
            navController.modalPresentationStyle = .pageSheet
            self.present(navController, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    func showCirclePicker() {
        // Sort circles alphabetically for easy finding
        let sortedCircles = circles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        let circlePickerVC = CirclePickerViewController(circles: sortedCircles)
        circlePickerVC.onCircleSelected = { [weak self] circle in
            let addPlaceVC = AddPlaceViewController(circleId: circle.id, circles: sortedCircles)
            self?.navigationController?.pushViewController(addPlaceVC, animated: true)
        }
        circlePickerVC.onCreateNewCircle = { [weak self] in
            guard let self = self else { return }
            let createCircleVC = CreateCircleViewController()
            createCircleVC.delegate = self
            let navController = UINavigationController(rootViewController: createCircleVC)
            navController.modalPresentationStyle = .pageSheet
            self.present(navController, animated: true)
        }
        
        let navController = UINavigationController(rootViewController: circlePickerVC)
        
        // Set presentation style for modal
        if UIDevice.current.userInterfaceIdiom == .pad {
            navController.modalPresentationStyle = .formSheet
            navController.preferredContentSize = CGSize(width: 400, height: 600)
        } else {
            navController.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                if let sheet = navController.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
            }
        }
        
        present(navController, animated: true)
    }
    
    
    
    func updateMapVisibility() {
        // Map is always visible, just ensure it's shown
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        updateMapPlaces()
    }
    
    func deduplicatePlaces(userPlaces: [Place], networkPlaces: [Place]) -> [Place] {
        var seenPlaceIds = Set<String>()
        var deduplicatedPlaces: [Place] = []
        
        // First, add all user places (these take priority)
        for place in userPlaces {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                Logger.debug("🔍 Skipping duplicate user place: '\(place.name)' (ID: \(place.id))")
            }
        }
        
        // Then, add network places only if we haven't seen their ID
        var duplicatesFound = 0
        for place in networkPlaces {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                duplicatesFound += 1
                Logger.debug("🔍 Skipping duplicate network place: '\(place.name)' (ID: \(place.id)) - already exists in user places")
            }
        }
        
        if duplicatesFound > 0 {
            Logger.debug("⚠️ Found and removed \(duplicatesFound) duplicate places from network data")
        }
        
        Logger.debug("📍 Deduplication summary: \(userPlaces.count) user + \(networkPlaces.count) network = \(deduplicatedPlaces.count) unique places")
        return deduplicatedPlaces
    }
    
    func removeDuplicatePlaces(_ places: [Place]) -> [Place] {
        var seenPlaceIds = Set<String>()
        var deduplicatedPlaces: [Place] = []
        var duplicatesFound = 0
        
        for place in places {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                // No per-place logging here — this runs on the main thread on
                // every place merge, and a line per duplicate flooded the
                // console (hundreds per avatar tap on large place sets).
                duplicatesFound += 1
            }
        }

        if duplicatesFound > 0 {
            Logger.debug("⚠️ Removed \(duplicatesFound) duplicate places (\(places.count) → \(deduplicatedPlaces.count))")
        }
        return deduplicatedPlaces
    }
    
    func fetchNetworkPlacesAndCombineWithCached() {
        var networkPlaces: [Place] = []
        let group = DispatchGroup()

        // Fetch places from network circles
        // (skipped with viewport loading — places arrive per visible region)
        for circle in (useViewportNetworkLoading ? [] : networkCircles) {
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                switch result {
                case .success(let places):
                    Logger.debug("✅ Fetched \(places.count) network places from circle '\(circle.name)'")
                    networkPlaces.append(contentsOf: places)
                case .failure(let error):
                    Logger.debug("❌ Error fetching network places from circle '\(circle.name)': \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // When using cached places, we need to separate user's own places
            let currentUserId = AuthService.shared.getUserId() ?? ""
            let userCircleIds = self.circles.map { $0.id }
            
            // Filter cached places to get only user's own places
            let userPlacesFromCache = self.cachedPlaces.filter { place in
                if let circleId = place.circleId, userCircleIds.contains(circleId) {
                    return true
                }
                if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                    return IDNormalizer.isSameUser(circle.owner, currentUserId)
                }
                return false
            }
            
            // Store user's own places separately
            self.userOwnPlaces = userPlacesFromCache
            
            // Deduplicate places before combining
            let allPlaces = self.deduplicatePlaces(userPlaces: self.cachedPlaces, networkPlaces: networkPlaces)
            Logger.debug("📍 Combined places: \(self.cachedPlaces.count) cached user + \(networkPlaces.count) network = \(allPlaces.count) total (after deduplication)")
            Logger.debug("📍 User's own places: \(self.userOwnPlaces.count)")
            
            self.allPlaces = allPlaces
            self.applyFiltersAndUpdateMap()
        }
    }
    
    func applyFiltersAndUpdateMap() {
        // Apply filtering to all places
        let filteredPlaces = applyFiltersToPlaces(allPlaces)
        self.filteredPlaces = filteredPlaces
        
        // Mark data as ready and update map
        isMapDataReady = true
        updateMapWhenReady()
        
        // Clean up loading states
        isLoadingPlaces = false
        hideLoadingState()
    }
    
    func applyFiltersToPlaces(_ places: [Place]) -> [Place] {
        Logger.debug("📍 Connection filter - selectedConnectionId: \(self.selectedConnectionId ?? "nil")")
        
        // Apply connection filter if selected
        var mapFilteredPlaces = places
        
        if let connectionId = self.selectedConnectionId {
            if connectionId == "my_places_only" {
                // Show only places from user's own circles
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let userCircleIds = self.circles.map { $0.id }
                Logger.debug("📍 FILTER: my_places_only selected")
                Logger.debug("📍 Total places to filter: \(places.count)")
                Logger.debug("📍 User has \(self.circles.count) circles")
                Logger.debug("📍 Current user ID: \(currentUserId)")
                
                if userCircleIds.isEmpty && networkCircles.isEmpty {
                    Logger.debug("⚠️ Warning: No circles loaded, showing empty results")
                    mapFilteredPlaces = []
                } else {
                    // Filter to only include places from user's circles
                    var filteredPlaces: [Place] = []
                    var excludedCount = 0
                    var networkCircleUserPlaces = 0
                    
                    for place in places {
                        var isUserPlace = false
                        
                        // First check if circleId is in user's circles
                        if let circleId = place.circleId, userCircleIds.contains(circleId) {
                            isUserPlace = true
                        } else {
                            // Check if this place's circle is owned by the current user
                            // (handles case where user's circles might be in networkCircles)
                            if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                                    isUserPlace = true
                                    networkCircleUserPlaces += 1
                                    Logger.debug("📍 Found user place in network circle: '\(place.name)' from circle '\(circle.name)'")
                                }
                            }
                        }
                        
                        if isUserPlace {
                            filteredPlaces.append(place)
                        } else {
                            excludedCount += 1
                        }
                    }
                    
                    mapFilteredPlaces = filteredPlaces
                    Logger.debug("📍 FILTER RESULT: Kept \(mapFilteredPlaces.count) places, excluded \(excludedCount) places")
                    Logger.debug("📍 Found \(networkCircleUserPlaces) user places that were in network circles")
                    Logger.debug("📍 User should have 124 places total according to user")
                }
            } else {
                // Show only places from the selected connection
                // Get all places from circles owned by this connection
                Logger.debug("📍 FILTER: Specific connection selected: \(connectionId)")
                var connectionFilteredPlaces: [Place] = []
                var debugCircleOwners = Set<String>()
                
                for place in places {
                    // Find the circle this place belongs to
                    if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                        debugCircleOwners.insert(circle.owner)
                        // Use IDNormalizer to compare IDs properly
                        if IDNormalizer.isSameUser(circle.owner, connectionId) {
                            connectionFilteredPlaces.append(place)
                            Logger.debug("   ✅ Found place '\(place.name)' from circle '\(circle.name)' owned by connection")
                        }
                    } else if IDNormalizer.isSameUser(place.addedBy, connectionId) {
                        // Circle metadata not loaded (e.g. viewport-fetched
                        // place) — match by who added it instead of dropping it
                        connectionFilteredPlaces.append(place)
                    }
                }
                
                mapFilteredPlaces = connectionFilteredPlaces
                Logger.debug("   Available circle owners: \(debugCircleOwners)")
                Logger.debug("   Looking for connectionId: \(connectionId)")
                Logger.debug("   Filtered to connection '\(connectionId)': \(mapFilteredPlaces.count) places")
            }
        } else {
            // "All Connections" selected - show all places (user's + connections')
            mapFilteredPlaces = places
            Logger.debug("   Showing all connections' places: \(mapFilteredPlaces.count) places")
        }
        
        // Apply category filter
        if let category = self.selectedCategory {
            let beforeCategoryFilter = mapFilteredPlaces.count
            mapFilteredPlaces = mapFilteredPlaces.filter { place in
                let matches = category.matches(place: place)
                
                // Debug logging for filter matching
                if !matches {
                    Logger.debug("   🚫 Place '\(place.name)' does not match filter '\(category.displayName)' - place category: \(place.category), customCategoryId: \(place.customCategoryId ?? "none")")
                }
                
                return matches
            }
            Logger.debug("   Category filter '\(category.displayName)' applied: \(beforeCategoryFilter) → \(mapFilteredPlaces.count) places")
        }
        
        Logger.debug("   Final places after filtering: \(mapFilteredPlaces.count)")
        return mapFilteredPlaces
    }
    
    
    func updateMapPlaces() {
        // Skip update if returning from full screen map
        if isReturningFromFullScreenMap {
            return
        }
        
        // Don't trigger another fetch if we're already loading
        if isLoadingPlaces || isPerformingInitialLoad {
            return
        }
        
        // Cancel any existing timer
        mapUpdateTimer?.invalidate()
        
        // Create a new timer with a 0.3 second delay to debounce rapid updates
        mapUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Only fetch if not already loading
            if !(self.isLoadingPlaces ?? false) && !(self.isPerformingInitialLoad ?? false) {
                self.fetchAllPlacesFromCircles()
            }
        }
    }
    
    
    // MARK: - Filter-Only Map Display Updates
    
    /// Updates map display with current filters without re-fetching data
    /// Use this for category/connection filter changes that don't require new data
    /// 
    /// This fixes the issue where selecting categories (like "Coffee work") would 
    /// trigger a full data refetch, losing the applied filter state
    /// Buckets allPlaces into the user's own places and per-connection lists
    /// using circle-owner mapping — the owner id is authoritative here, since
    /// place.addedBy can carry a connection's legacy account id.
    func buildConnectionPlaceBuckets() -> (userPlaces: [Place], connectionPlaces: [String: [Place]]) {
        var userPlaces: [Place] = []
        var connectionPlacesMap: [String: [Place]] = [:]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let userCircleIds = Set(circles.map { $0.id })
        let connections = NetworkManager.shared.connections

        // Map circle owner IDs to connection otherUserIds — handles the ID
        // normalization and connection data issues
        var ownerToConnectionId: [String: String] = [:]
        for connection in connections {
            let otherUserId = connection.otherUserId(currentUserId: currentUserId)
            for circle in networkCircles {
                if IDNormalizer.isSameUser(circle.owner, otherUserId) {
                    ownerToConnectionId[circle.owner] = otherUserId
                }
            }
        }

        for place in allPlaces {
            if let circleId = place.circleId, userCircleIds.contains(circleId) {
                userPlaces.append(place)
            } else if let circleId = place.circleId, let circle = networkCircles.first(where: { $0.id == circleId }) {
                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                    userPlaces.append(place)
                } else {
                    let mapKey = ownerToConnectionId[circle.owner] ?? circle.owner
                    connectionPlacesMap[mapKey, default: []].append(place)
                }
            }
        }

        return (userPlaces, connectionPlacesMap)
    }

    /// If the backend flagged a possible second account at sign-in, offer the
    /// merge flow. Consuming the suggestion means the user is asked at most
    /// once per login.
    func promptForDuplicateAccountsIfNeeded() {
        guard let suggestion = AuthService.shared.consumeDuplicateSuggestion(),
              let candidate = suggestion.duplicateAccounts.first else { return }

        let hint = candidate.displayName ?? candidate.email ?? "another account"
        AlertPresenter.showConfirmation(
            title: "Is this you?",
            message: "It looks like you might have another Circles account (\(hint)). You can merge it so all your places and connections live in one account.",
            confirmTitle: "Review & Merge",
            cancelTitle: "Not Now",
            from: self,
            onConfirm: { [weak self] in
                let mergeVC = AccountMergeViewController()
                self?.navigationController?.pushViewController(mergeVC, animated: true)
            }
        )
    }

    func refreshMapDisplay(adjustRegion: Bool = true) {
        Logger.debug("🗺️ [RefreshMapDisplay] Refreshing map with current filters")

        // Skip if we don't have data yet
        if allPlaces.isEmpty {
            Logger.debug("🗺️ [RefreshMapDisplay] No places data available, skipping refresh")
            return
        }

        // Apply current filters to existing data
        let placesToDisplay = applyFiltersToPlaces(allPlaces)

        Logger.debug("🗺️ [RefreshMapDisplay] Displaying \(placesToDisplay.count) filtered places (from \(allPlaces.count) total)")

        // Update the map immediately (no debouncing needed for filters).
        // updatePlaces zooms exactly once via the annotation pipeline when
        // adjustRegion is true — no extra delayed adjustMapRegion here.
        mapViewController?.updatePlaces(placesToDisplay, adjustRegion: adjustRegion)

        // The presented full map applies its own connection/category filters,
        // so it gets the UNFILTERED set (e.g. a connection's places fetched
        // after it was presented). Refresh its owner-mapped buckets first so
        // late-arriving places filter correctly (addedBy alone misses places
        // saved under a connection's legacy account id). Re-frame only for a
        // specific connection — its adjustMapRegion keeps the camera when pins
        // are already in view, and zooms out (worldwide if needed) when none are.
        if let modal = presentedFullScreenMap {
            let modalShouldZoom = adjustRegion
                && selectedConnectionId != nil
                && selectedConnectionId != "my_places_only"
            modal.updateConnectionBuckets(buildConnectionPlaceBuckets().connectionPlaces)
            modal.updatePlaces(allPlaces, adjustRegion: modalShouldZoom)
        }

        // Keep the distance-sorted list in sync when it's visible
        if isShowingPlacesList {
            rebuildDistanceSortedPlaces()
            placesListTableView.reloadData()
        }

        // Update place count label
        updatePlaceCountLabel(count: placesToDisplay.count)
    }

    // MARK: - Viewport-Based Network Place Loading

    /// Fetches network places for the given map region and merges them into
    /// `allPlaces`. Called (debounced) whenever the map's visible region changes.
    func fetchViewportPlaces(region: MKCoordinateRegion, for controller: FullScreenMapViewController) {
        guard useViewportNetworkLoading else { return }

        // Region → covering circle: half the bounding-box diagonal, +10% pad
        let latMeters = region.span.latitudeDelta * 111_320.0
        let lngMeters = region.span.longitudeDelta * 111_320.0 * cos(region.center.latitude * .pi / 180)
        var radiusM = ((latMeters * latMeters + lngMeters * lngMeters).squareRoot() / 2) * 1.1
        radiusM = min(max(radiusM, 100), 100_000) // match server clamp

        // Skip if an earlier fetch already fully covered this area
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        for fetched in fetchedViewportCircles {
            let prevCenter = CLLocation(latitude: fetched.center.latitude, longitude: fetched.center.longitude)
            if prevCenter.distance(from: center) + radiusM <= fetched.radiusM {
                Logger.debug("🗺️ [Viewport] Region already covered, skipping fetch")
                return
            }
        }

        guard !isFetchingViewport else { return }
        isFetchingViewport = true

        let requestLimit = 200
        Logger.debug("🗺️ [Viewport] Fetching places: center=(\(region.center.latitude), \(region.center.longitude)) radius=\(Int(radiusM))m")

        PlaceService.shared.fetchNetworkPlacesInViewport(
            centerLat: region.center.latitude,
            centerLng: region.center.longitude,
            radiusM: radiusM,
            limit: requestLimit
        ) { [weak self, weak controller] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingViewport = false

                switch result {
                case .success(let places):
                    Logger.debug("🗺️ [Viewport] Received \(places.count) places")

                    // Record coverage only when the result wasn't truncated by the limit
                    if places.count < requestLimit {
                        self.fetchedViewportCircles.append((center: region.center, radiusM: radiusM))
                        if self.fetchedViewportCircles.count > 50 {
                            self.fetchedViewportCircles.removeFirst()
                        }
                    }

                    guard !places.isEmpty else { return }

                    // Merge (never replace) so nothing already loaded disappears
                    let countBefore = self.allPlaces.count
                    self.allPlaces = self.removeDuplicatePlaces(self.allPlaces + places)
                    guard self.allPlaces.count > countBefore else { return }

                    self.cachedPlaces = self.allPlaces
                    self.placesCacheExpiry = Date().addingTimeInterval(self.cacheExpiryMinutes * 60)
                    self.updateAvailableCategories()

                    // Refresh pins without moving the map (prevents a fetch
                    // loop). This also pushes the unfiltered set to the
                    // presented full map, which filters for itself.
                    self.refreshMapDisplay(adjustRegion: false)
                case .failure(let error):
                    // Non-fatal: a later pan retries the fetch
                    Logger.debug("🗺️ [Viewport] Fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Fetches ALL places for one connection (not viewport-bounded) so the map
    /// can zoom to their places when they're selected as the filter.
    /// Uses the same user-circles + per-circle path as the profile map — the
    /// places/batch endpoint re-checks connections by exact id and can silently
    /// drop circles when connection docs and circle owners use different id formats.
    func fetchAllPlacesForConnection(_ connectionId: String) {
        Logger.debug("📍 Fetching circles for connection \(connectionId)")
        APIService.shared.request(
            endpoint: "network/user-circles/\(connectionId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    let connectionCircles = response.data.circles
                    // Register these circles so the connection/category filters
                    // and owner mapping recognize their places
                    let knownIds = Set(self.networkCircles.map { $0.id })
                    self.networkCircles.append(contentsOf: connectionCircles.filter { !knownIds.contains($0.id) })

                    // Adopt the canonical user id the endpoint resolved, so the
                    // owner-matching filter lines up with these circles' owner
                    let canonicalId = response.data.user.id
                    if self.selectedConnectionId == connectionId && canonicalId != connectionId {
                        self.selectedConnectionId = canonicalId
                        self.mapViewController?.setConnectionFilterContext(canonicalId)
                        // The presented full map filters independently - without
                        // the canonical id its added-by match finds nothing
                        self.presentedFullScreenMap?.setConnectionFilterContext(canonicalId)
                        self.userListView.selectedUserId = canonicalId
                    }

                    // The endpoint already embeds each circle's places - use them
                    // directly instead of refetching one request per circle
                    let embeddedPlaces = connectionCircles.flatMap { $0.placesWithDetails ?? [] }
                    if !embeddedPlaces.isEmpty {
                        self.allPlaces = self.removeDuplicatePlaces(self.allPlaces + embeddedPlaces)
                    }

                    // Only fetch circles whose places weren't embedded in the response
                    let circlesMissingPlaces = connectionCircles.filter { circle in
                        circle.placesWithDetails == nil && (circle.placesCount ?? circle.places?.count ?? 0) > 0
                    }
                    if circlesMissingPlaces.isEmpty {
                        self.updateAvailableCategories()
                        // Zoom is wanted here - the map should frame this connection's places
                        self.refreshMapDisplay()
                    } else {
                        self.fetchPlacesForConnectionCircles(circlesMissingPlaces)
                    }
                case .failure(let error):
                    Logger.debug("❌ Failed to fetch circles for connection \(connectionId): \(error.localizedDescription)")
                    self.refreshMapDisplay()
                }
            }
        }
    }

    func fetchPlacesForConnectionCircles(_ connectionCircles: [Circle]) {
        guard !connectionCircles.isEmpty else {
            refreshMapDisplay()
            return
        }

        Logger.debug("📍 Fetching places for \(connectionCircles.count) connection circles")
        var fetchedPlaces: [Place] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for circle in connectionCircles {
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                if case .success(let places) = result {
                    lock.lock()
                    fetchedPlaces.append(contentsOf: places)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            Logger.debug("📍 Connection places fetched: \(fetchedPlaces.count)")
            self.allPlaces = self.removeDuplicatePlaces(self.allPlaces + fetchedPlaces)
            self.updateAvailableCategories()
            // Zoom is wanted here — the map should frame this connection's places
            self.refreshMapDisplay()
        }
    }
    
    
    func buildMapMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        // Connection filter submenu
        let currentUserId = AuthService.shared.getUserId() ?? ""
        var connectionActions: [UIAction] = [
            UIAction(title: "All Connections", state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                self?.selectConnection(id: nil, user: nil)
            },
            UIAction(title: "My Places Only", state: selectedConnectionId == "my_places_only" ? .on : .off) { [weak self] _ in
                self?.selectConnection(id: "my_places_only", user: nil)
            }
        ]
        for connection in NetworkManager.shared.connections {
            let otherUserId = connection.otherUserId(currentUserId: currentUserId)
            connectionActions.append(
                UIAction(
                    title: connection.connectedUser?.displayName ?? "Unknown",
                    state: selectedConnectionId == otherUserId ? .on : .off
                ) { [weak self] _ in
                    self?.selectConnection(id: otherUserId, user: connection.connectedUser)
                }
            )
        }
        let connectionSubtitle = selectedConnectionUser?.displayName
            ?? (selectedConnectionId == "my_places_only" ? "My Places Only" : "All Connections")
        elements.append(UIMenu(
            title: "Connections",
            subtitle: connectionSubtitle,
            image: UIImage(systemName: "person.2"),
            children: connectionActions
        ))

        // Recompute categories so the menu always reflects the current connection filter
        updateAvailableCategories()

        if availableCategories.isEmpty {
            let noCategories = UIAction(title: "No Categories", attributes: .disabled) { _ in }
            elements.append(UIMenu(title: "Category", image: UIImage(systemName: "square.grid.2x2"), children: [noCategories]))
        } else {
            var categoryActions: [UIAction] = [
                UIAction(title: "All Categories", state: selectedCategory == nil ? .on : .off) { [weak self] _ in
                    self?.selectCategory(nil)
                }
            ]
            for category in availableCategories {
                categoryActions.append(
                    UIAction(title: category.displayName, state: selectedCategory == category ? .on : .off) { [weak self] _ in
                        self?.selectCategory(category)
                    }
                )
            }
            elements.append(UIMenu(
                title: "Category",
                subtitle: selectedCategory?.displayName ?? "All Categories",
                image: UIImage(systemName: "square.grid.2x2"),
                children: categoryActions
            ))
        }

        // View Profile: the filtered connection's profile, or the user's own when none is selected
        let profileTitle: String
        if let name = selectedConnectionUser?.displayName, !name.isEmpty {
            profileTitle = "View \(name)'s Profile"
        } else {
            profileTitle = "View My Profile"
        }
        elements.append(UIAction(title: profileTitle, image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in
            self?.openProfileFromMapMenu()
        })

        return elements
    }

    func selectCategory(_ category: UnifiedCategory?) {
        selectedCategory = category
        Logger.debug("📍 Category filter changed to: \(selectedCategory?.displayName ?? "All Categories")")
        refreshMapDisplay()
    }

    func updateAvailableCategories() {
        Logger.debug("🏷️ [Categories] Updating available categories with connection filter: \(selectedConnectionId ?? "none")")
        Logger.debug("🏷️ [Categories] Total allPlaces count: \(allPlaces.count)")
        
        // Apply connection filter first to get only visible places
        let visiblePlaces = applyConnectionFilterToPlaces(allPlaces)
        Logger.debug("🏷️ [Categories] Visible places after connection filter: \(visiblePlaces.count)")
        
        // Get unique categories from visible places only
        var categoriesSet = Set<UnifiedCategory>()
        for place in visiblePlaces {
            let category = UnifiedCategory.from(place: place)
            categoriesSet.insert(category)
            
            // Debug logging for custom categories
            if case .custom(let customName) = category {
                Logger.debug("🏷️ [Categories] Found custom category: '\(customName)' for place: \(place.name)")
            }
        }
        availableCategories = Array(categoriesSet).sorted { $0.displayName < $1.displayName }
        
        Logger.debug("🏷️ [Categories] Available categories after connection filter (\(visiblePlaces.count) places): \(availableCategories.map { $0.displayName })")
        
        // Check if the currently selected category is still available
        if let selectedCategory = self.selectedCategory,
           !availableCategories.contains(selectedCategory) {
            Logger.debug("🏷️ [Categories] Previously selected category '\(selectedCategory.displayName)' no longer available, clearing selection")
            self.selectedCategory = nil
        }
    }
    
    // Helper method to apply only connection filtering (without category filter)
    func applyConnectionFilterToPlaces(_ places: [Place]) -> [Place] {
        var filteredPlaces = places
        
        if let connectionId = self.selectedConnectionId {
            if connectionId == "my_places_only" {
                // Show only places from user's own circles
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let userCircleIds = self.circles.map { $0.id }
                
                if userCircleIds.isEmpty && networkCircles.isEmpty {
                    filteredPlaces = []
                } else {
                    // Filter to only include places from user's circles
                    var userPlaces: [Place] = []
                    
                    for place in places {
                        var isUserPlace = false
                        
                        // First check if circleId is in user's circles
                        if let circleId = place.circleId, userCircleIds.contains(circleId) {
                            isUserPlace = true
                        } else {
                            // Check if this place's circle is owned by the current user
                            if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                                    isUserPlace = true
                                }
                            }
                        }
                        
                        if isUserPlace {
                            userPlaces.append(place)
                        }
                    }
                    
                    filteredPlaces = userPlaces
                }
            } else {
                // Show only places from the selected connection
                var connectionPlaces: [Place] = []
                
                for place in places {
                    if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                        if IDNormalizer.isSameUser(circle.owner, connectionId) {
                            connectionPlaces.append(place)
                        }
                    }
                }
                
                filteredPlaces = connectionPlaces
            }
        }
        // If no connection filter, return all places
        
        return filteredPlaces
    }
    
    func openProfileFromMapMenu() {
        let profileVC = ProfileViewController()
        // Without a configured user, ProfileViewController shows the current user's own profile
        if let user = selectedConnectionUser {
            profileVC.configureWith(user: user)
        }
        navigationController?.pushViewController(profileVC, animated: true)
    }

    @objc func listToggleTapped() {
        isShowingPlacesList.toggle()

        // Flip the icon: show what tapping will switch to
        let iconName = isShowingPlacesList ? "map" : "list.bullet"
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        listToggleButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)

        if isShowingPlacesList {
            rebuildDistanceSortedPlaces()
            placesListTableView.reloadData()
            // Open at the top, below the floating chips
            placesListTableView.setContentOffset(CGPoint(x: 0, y: -placesListTableView.contentInset.top), animated: false)
        }

        // The list fully covers the map; map-only controls hide with it
        placesListTableView.isHidden = !isShowingPlacesList
        mapExpandButton.isHidden = isShowingPlacesList
        mapPlaceCountLabel.isHidden = isShowingPlacesList
    }

    /// Rebuilds the distance-sorted data source for the places list from the
    /// currently filtered places. Places without a location sort last.
    func rebuildDistanceSortedPlaces() {
        let filtered = applyFiltersToPlaces(allPlaces)
        let referenceLocation = mapViewController?.currentUserLocation
            ?? mapViewController.map { CLLocation(latitude: $0.currentRegion.center.latitude, longitude: $0.currentRegion.center.longitude) }

        distanceSortedPlaces = filtered.map { place in
            let distance: CLLocationDistance?
            if let reference = referenceLocation, let placeLocation = place.location?.clLocation {
                distance = reference.distance(from: placeLocation)
            } else {
                distance = nil
            }
            return (place: place, distance: distance)
        }.sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
            }
        }

        // Simple empty state
        if distanceSortedPlaces.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No places to show"
            emptyLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            emptyLabel.textColor = Constants.Colors.secondaryLabel
            emptyLabel.textAlignment = .center
            placesListTableView.backgroundView = emptyLabel
        } else {
            placesListTableView.backgroundView = nil
        }
    }

    /// Resolves the circle a place belongs to: circleId back-reference first
    /// (always present, even when a circle's places array is stale), then
    /// places-array membership. Shared by map pin callouts and the places list.
    func resolveCircle(for place: Place) -> Circle? {
        return circles.first(where: { $0.id == place.circleId })
            ?? circles.first(where: { $0.places?.contains(place.id) == true })
            ?? networkCircles.first(where: { $0.id == place.circleId })
            ?? networkCircles.first(where: { $0.places?.contains(place.id) == true })
    }

    /// Pushes the detail screen for a place (used by the places list).
    func presentDetailForPlace(_ place: Place) {
        guard let circle = resolveCircle(for: place) else {
            Logger.debug("⚠️ Place not found in any circle (circleId: \(place.circleId ?? "nil"))")
            return
        }

        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }

    @objc func myPlacesToggleTapped() {
        if selectedConnectionId == "my_places_only" {
            selectConnection(id: nil, user: nil)
        } else {
            selectConnection(id: "my_places_only", user: nil)
        }
    }

    func updateMyPlacesToggleAppearance() {
        let isActive = selectedConnectionId == "my_places_only"
        var config = myPlacesToggleButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: isActive ? "person.fill" : "person",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        config.baseForegroundColor = isActive ? .white : Constants.Colors.label
        myPlacesToggleButton.configuration = config
        myPlacesToggleButton.backgroundColor = isActive ? Constants.Colors.primary : Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        myPlacesToggleButton.layer.borderColor = isActive ? Constants.Colors.primary.cgColor : Constants.Colors.separator.cgColor
    }

    func selectConnection(id: String?, user: User?) {
        selectedConnectionId = id
        selectedConnectionUser = user
        updateMyPlacesToggleAppearance()
        updateSelectedConnectionAvatar()
        // Keep the expanded map's avatar chip in sync while it's presented
        presentedFullScreenMap?.selectedConnectionUser = user

        // Highlight the selected connection's avatar (nil clears the highlight)
        userListView.selectedUserId = (id == nil || id == "my_places_only") ? nil : id

        Logger.debug("📍 Connection filter changed to: \(selectedConnectionId ?? "All Connections")")

        // Tell the embedded map so it zooms to the selected connection's places
        mapViewController?.setConnectionFilterContext(selectedConnectionId)

        // Update available categories based on new connection filter
        updateAvailableCategories()

        if let connectionId = id, connectionId != "my_places_only" {
            // Re-scope pins with what's already loaded BEFORE any async fetch —
            // otherwise other connections' pins linger until this connection's
            // places arrive. But DEFER the zoom when we're about to fetch this
            // connection's full place set (the viewport path): zooming here to
            // the partial/stale set and again after the fetch made the camera
            // visibly fly twice. Let the post-fetch pass do the one zoom.
            let deferZoom = useViewportNetworkLoading
            refreshMapDisplay(adjustRegion: !deferZoom)

            if networkCircles.isEmpty {
                Logger.debug("📍 Need to fetch network circles for connection filtering")
                fetchNetworkCircles { [weak self] in
                    guard let self = self else { return }
                    self.updateAvailableCategories()
                    if self.useViewportNetworkLoading {
                        // Ensure ALL of this connection's places are loaded (not viewport-bounded)
                        self.fetchAllPlacesForConnection(connectionId)
                    } else {
                        self.updateMapPlaces()
                    }
                }
            } else if useViewportNetworkLoading {
                fetchAllPlacesForConnection(connectionId)
            }
        } else {
            // All Connections / My Places Only: refresh with what's loaded
            refreshMapDisplay()
        }
    }
    
    func showSearchScopeDropdown() {
        // Calculate dropdown height for 2 options
        let numberOfRows = SearchScope.allCases.count
        let dropdownHeight = CGFloat(numberOfRows) * 44
        
        searchScopeDropdownView.isHidden = false
        searchScopeDropdownHeightConstraint?.constant = dropdownHeight
        
        UIView.animate(withDuration: 0.2, animations: {
            self.searchScopeDropdownView.alpha = 1
            self.view.layoutIfNeeded()
            
            // Rotate arrow
            self.searchScopeButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        })
        
        // Bring dropdown to front
        view.bringSubviewToFront(searchScopeDropdownView)
        
        // Reload table view
        searchScopeTableView.reloadData()
    }
    
    func hideSearchScopeDropdown() {
        UIView.animate(withDuration: 0.2, animations: {
            self.searchScopeDropdownView.alpha = 0
            self.searchScopeDropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
            
            // Rotate arrow back
            self.searchScopeButton.imageView?.transform = .identity
        }) { _ in
            self.searchScopeDropdownView.isHidden = true
        }
    }
    
    @objc func dismissDropdowns(_ gesture: UITapGestureRecognizer? = nil) {
        // Handle keyboard dismissal first
        if searchBar.isFirstResponder {
            if let gesture = gesture {
                let location = gesture.location(in: view)
                let searchBarFrame = searchBar.convert(searchBar.bounds, to: view)
                
                // Only dismiss keyboard if tap is outside search bar
                if !searchBarFrame.contains(location) {
                    searchBar.resignFirstResponder()
                }
            }
        }
        
        // Then handle dropdown dismissal
        if isSearchScopeDropdownOpen {
            isSearchScopeDropdownOpen = false
            hideSearchScopeDropdown()
        }
    }

    @objc func searchScopeButtonTapped() {
        isSearchScopeDropdownOpen.toggle()

        if isSearchScopeDropdownOpen {
            showSearchScopeDropdown()
        } else {
            hideSearchScopeDropdown()
        }
    }
    
    @objc func recordReelTapped() {
        let contentUploadVC = ContentUploadViewController()
        contentUploadVC.delegate = self
        let navController = UINavigationController(rootViewController: contentUploadVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc override func refreshData() {
        // Invalidate cache when user manually refreshes
        invalidateCache()
        
        Logger.debug("🚀 Starting OPTIMIZED refresh")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use parallel loading for refresh too
        let refreshGroup = DispatchGroup()
        
        // 1. Refresh user list
        userListView.refresh()
        
        // 2. Refresh activities (parallel)
        refreshGroup.enter()
        fetchActivities { _ in
            refreshGroup.leave()
        }
        
        // 3. Refresh circles based on current view (parallel)
        refreshGroup.enter()
        if isShowingNetworkCircles {
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.networkCircles = response.data
                    self?.fetchAllPlacesFromCircles()
                case .failure(let error):
                    Logger.debug("❌ Failed to refresh network circles: \(error)")
                }
                refreshGroup.leave()
            }
        } else {
            CircleService.shared.fetchUserCircles { [weak self] result in
                switch result {
                case .success(let circles):
                    self?.circles = circles
                    self?.fetchAllPlacesFromCircles()
                case .failure(let error):
                    Logger.debug("❌ Failed to refresh user circles: \(error)")
                }
                refreshGroup.leave()
            }
        }
        
        refreshGroup.notify(queue: .main) { [weak self] in
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            Logger.debug("✅ OPTIMIZED refresh completed in \(String(format: "%.2f", totalTime)) seconds")
        }
    }
    
    @objc func checkInButtonTapped() {
        let checkInVC = CheckInViewController()
        let navController = UINavigationController(rootViewController: checkInVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc func helpButtonTapped() {
        let helpVC = HelpViewController()
        let navController = UINavigationController(rootViewController: helpVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    @objc func inviteButtonTapped() {
        // Same share-invite flow as the My Network tab's person.badge.plus button
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )

        // For iPad: anchor the popover to the invite bar button
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItems?.last
        }

        present(activityViewController, animated: true)
    }
    
    @objc func notificationButtonTapped() {
        let notificationsVC = NotificationsViewController()
        navigationController?.pushViewController(notificationsVC, animated: true)
    }
    
    func setupNotificationBadge() {
        // Create a custom button with badge capability
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "bell"), for: .normal)
        button.addTarget(self, action: #selector(notificationButtonTapped), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        
        // Create badge label
        let badgeLabel = UILabel()
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add badge to button
        button.addSubview(badgeLabel)
        
        // Constraints for badge
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: -4),
            badgeLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 8),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        self.notificationBadgeLabel = badgeLabel
        
        // Update the bar button item with custom view
        notificationBarButton?.customView = button
    }
    
    func updateNotificationBadge() {
        // Always ensure badge is set up first
        if notificationBadgeLabel == nil {
            setupNotificationBadge()
        }

        NotificationService.shared.getUnreadNotificationCount { [weak self] result in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let count):
                    if count > 0 {
                        self.notificationBadgeLabel?.text = count > 99 ? "99+" : "\(count)"
                        self.notificationBadgeLabel?.isHidden = false

                        // Adjust width constraint if needed
                        if count > 9 {
                            self.notificationBadgeLabel?.constraints.forEach { constraint in
                                if constraint.firstAttribute == .width {
                                    constraint.constant = 20
                                }
                            }
                        }
                    } else {
                        self.notificationBadgeLabel?.isHidden = true
                    }
                case .failure(let error):
                    Logger.debug("❌ [updateNotificationBadge] Failed to get unread count: \(error)")
                    self.notificationBadgeLabel?.isHidden = true
                }
            }
        }
    }
    
    @objc func rewardsButtonTapped() {
        let rewardsVC = RewardsViewController()
        navigationController?.pushViewController(rewardsVC, animated: true)
    }

    @objc func handleRewardBalanceChanged() {
        updateRewardsBadge()
    }

    func setupRewardsBadge() {
        // Custom button with a badge, mirroring the notification bell badge
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "dollarsign.circle"), for: .normal)
        button.addTarget(self, action: #selector(rewardsButtonTapped), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        button.accessibilityLabel = "Rewards"

        // Points balance — brand color rather than red: it's a balance, not an alert
        let badgeLabel = UILabel()
        badgeLabel.backgroundColor = Constants.Colors.primary
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: -4),
            badgeLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 8),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16)
        ])

        self.rewardsBadgeLabel = badgeLabel
        rewardsBarButton?.customView = button
    }

    func updateRewardsBadge() {
        if rewardsBadgeLabel == nil {
            setupRewardsBadge()
        }

        RewardsService.shared.getBalance { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if data.balance > 0 {
                        self.rewardsBadgeLabel?.text = data.balance > 999 ? "999+" : "\(data.balance)"
                        self.rewardsBadgeLabel?.isHidden = false
                    } else {
                        self.rewardsBadgeLabel?.isHidden = true
                    }
                case .failure:
                    // Keep whatever was last shown; the badge is best-effort
                    break
                }
            }
        }
    }

    
    // MARK: - Circle Management
    func editCircle(at indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    func deleteCircle(at indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        
        let alert = UIAlertController(
            title: "Delete Circle",
            message: "Are you sure you want to delete '\(circle.name)'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(circle: circle, at: indexPath)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    func performDelete(circle: Circle, at indexPath: IndexPath) {
        CircleService.shared.deleteCircle(id: circle.id) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self.circles.remove(at: indexPath.row)
                    self.updateEmptyState()
                    
                case .failure(let error):
                    self.presentAlert(
                        title: "Error",
                        message: "Failed to delete circle: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
