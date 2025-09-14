import UIKit
import CoreLocation
import UniformTypeIdentifiers
import MapKit
import AVFoundation

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
    private var cachedData: HomeScreenContent?
    private var cacheExpiry: Date?
    private let cacheValidityMinutes: TimeInterval = 3 // 3 minutes for memory cache
    
    var isValid: Bool {
        guard let expiry = cacheExpiry else { return false }
        return Date() < expiry
    }
    
    func store(_ data: HomeScreenContent) {
        // Store in memory
        cachedData = data
        cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
        print("📦 [Memory Cache] Stored home screen data, valid until \(cacheExpiry!)")
        
        // Store in disk cache for longer persistence
        CacheService.shared.cacheHomeScreenData(data)
    }
    
    func retrieve() -> HomeScreenContent? {
        // First try memory cache
        if isValid, let data = cachedData {
            print("📦 [Memory Cache] Retrieved valid cached data")
            return data
        }
        
        // Try disk cache as fallback
        if let diskData = CacheService.shared.getCachedHomeScreenData(maxAgeMinutes: 10) {
            print("📦 [Disk Cache] Retrieved valid cached data from disk")
            // Store in memory for next access
            cachedData = diskData
            cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
            return diskData
        }
        
        print("📦 [Cache] No valid cache found")
        cachedData = nil
        cacheExpiry = nil
        return nil
    }
    
    func invalidate() {
        cachedData = nil
        cacheExpiry = nil
        print("📦 [Cache] Memory cache invalidated")
        // Note: Disk cache remains for offline scenarios
    }
}

class CirclesHomeViewController: BaseViewController, PlaceSearchable, SSEServiceDelegate {
    
    // MARK: - Properties
    var circles: [Circle] = []
    private var networkCircles: [Circle] = []
    private var isShowingNetworkCircles = false
    var allPlaces: [Place] = []
    var filteredPlaces: [Place] = []
    var isSearching = false
    private var selectedCategory: UnifiedCategory?
    private var mapUpdateTimer: Timer? // Debounce timer for map updates
    private var notificationBadgeTimer: Timer? // Periodic refresh timer for notification badge
    private var isReturningFromFullScreenMap = false // Prevent map updates when returning from full screen
    private var isLoadingCircles = false // Track when circles are being loaded
    private var isLoadingPlaces = false // Track when places are being loaded
    private var isPerformingInitialLoad = false // Track if we're in the middle of initial loading
    private var isShowingLoadingUI = false // Track if loading UI is currently shown
    private static var hasLoadedInitialData = false // Track if we've loaded data at least once this session
    private var hasStartedLoading = false // Instance flag to prevent multiple loads in the same instance
    private var isMapDataReady = false // Track if map data is ready to be displayed
    
    // MARK: - Place Detail Deduplication Properties
    private var lastPresentedPlaceId: String?
    private var lastPresentationTime: TimeInterval = 0
    private let presentationDebounceInterval: TimeInterval = 1.0 // 1 second to prevent double-taps
    
    // MARK: - Enhanced Performance Properties
    private var optimizedCache: HomeScreenCache = HomeScreenCache()
    private var isUsingFastLoad = false // Track if we're using optimized fast loading
    private var skeletonLoadingView: HomeScreenSkeletonView? // Progressive loading skeleton
    
    // Instance-based cache with expiry
    private var placesCacheExpiry: Date?
    private var cachedPlaces: [Place] = []
    private var userOwnPlaces: [Place] = [] // Separate array for user's own places only
    
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
    private let cacheExpiryMinutes: TimeInterval = 5 // 5 minutes cache expiry
    private var loadDebounceTimer: Timer? // Debounce timer to prevent rapid successive loads
    private var preloadedData: PreloadedData? // Store preloaded data from splash screen
    private var preloadedConnections: [Connection]? // Store preloaded connections for userListView
    private var notificationBadgeLabel: UILabel? // Badge label for notification count
    private var notificationBarButton: UIBarButtonItem? // Store reference to notification button
    
    // Search scope properties
    private var currentSearchScope: SearchScope = .myPlaces
    private var networkPlaces: [Place] = [] // Cache for network places
    private var isLoadingNetworkPlaces = false
    
    // Suggested users overlay
    private var suggestedUsersOverlay: SuggestedUsersOverlayView?
    private var visitTrackingPermissionOverlay: VisitTrackingPermissionView?
    private var addPlaceTutorialOverlay: AddFirstPlaceTutorialView?
    
    // Welcome tour tracking
    private var isShowingWelcomeTour = false
    
    // Reaction picker tracking
    private var currentReactionActivity: Activity?
    
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
    private struct NetworkCirclesResponse: Codable {
        let success: Bool
        let data: [Circle]
    }
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = Constants.Colors.background
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.background
        return view
    }()
    
    let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search your places..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let searchScopeButton: UIButton = {
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
    
    private let searchScopeDropdownView: UIView = {
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
    
    private let searchScopeTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.layer.cornerRadius = 8
        tableView.isScrollEnabled = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let quickAccessContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let homeCard: UIView = {
        let view = UIView()
        // Google Maps blue color
        view.backgroundColor = UIColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 1.0) // #4285F4
        view.layer.cornerRadius = 8
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let workCard: UIView = {
        let view = UIView()
        // Google Maps blue color
        view.backgroundColor = UIColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 1.0) // #4285F4
        view.layer.cornerRadius = 8
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let quickAccessCard: UIView = {
        let view = UIView()
        // Google Maps blue color
        view.backgroundColor = UIColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 1.0) // #4285F4
        view.layer.cornerRadius = 8
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let homeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let workButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let homeNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let workNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let quickAccessButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let quickAccessNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let filterContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let userListView: HorizontalUserListView = {
        let view = HorizontalUserListView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyStateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.dashed")
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "You don't have any circles yet"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    
    private let quickAddPlaceButton: UIButton = {
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
    
    
    private let mapContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = false
        return view
    }()
    
    private let mapLoadingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()
    
    private let mapLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        indicator.layer.cornerRadius = 20
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private let mapLoadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Loading your places..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let mapLoadingProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = Constants.Colors.primary
        progressView.trackTintColor = Constants.Colors.primary.withAlphaComponent(0.2)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        progressView.progress = 0.0
        return progressView
    }()
    
    private let mapExpandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let mapPlaceCountLabel: UIButton = {
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
    
    private var mapViewController: FullScreenMapViewController?
    
    private let filterStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = false
        return stack
    }()
    
    private let connectionFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Connections", for: .normal)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let connectionDropdownView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 8
        view.isHidden = true
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let connectionDropdownTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.layer.cornerRadius = 12
        tableView.clipsToBounds = true
        return tableView
    }()
    
    private var isConnectionDropdownOpen = false
    private var connectionDropdownHeightConstraint: NSLayoutConstraint?
    private var selectedConnectionId: String? = nil // Default to All Connections
    
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
    
    private let categoryFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Categories", for: .normal)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Dropdown views for filters
    
    
    
    
    private let locationStatusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Loading places..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let loadingContentView: UIView = {
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
    
    private let loadingContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let categoryDropdownView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 8
        view.isHidden = true
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let categoryDropdownTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.layer.cornerRadius = 12
        tableView.clipsToBounds = true
        return tableView
    }()
    
    private var isCategoryDropdownOpen = false
    private var availableCategories: [UnifiedCategory] = []
    private var categoryDropdownHeightConstraint: NSLayoutConstraint?
    private var mapHeightConstraint: NSLayoutConstraint?
    
    // Search scope dropdown properties
    private var isSearchScopeDropdownOpen = false
    private var searchScopeDropdownHeightConstraint: NSLayoutConstraint?
    
    // Activity Feed Properties
    private var activities: [Activity] = []
    private var isLoadingActivities = false
    private var activityTableHeightConstraint: NSLayoutConstraint?
    
    // Daily Summary Properties
    private var dailySummaryCard: DailySummaryCardView?
    private var hasDailySummaryData = false
    
    // Reels Properties
    private var reels: [PlaceVideo] = []
    private var isLoadingReels = false
    private var reelsOffset = 0
    private var hasMoreReels = true
    private var isLoadingMoreReels = false
    
    // Suggested Users Overlay
    private var hasCheckedForSuggestedUsers = false
    private var hasCheckedTutorialAndOverlay = false
    private var tutorialCheckRetryCount = 0
    private let maxTutorialCheckRetries = 3
    
    // Pagination properties
    private var currentOffset = 0
    private var hasMoreActivities = true
    private var isLoadingMoreActivities = false
    
    // Activity Feed UI Elements
    private let activityFeedSection: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let activityHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "Recent Activity"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Segmented control for Activity/Moments tabs
    let contentSegmentedControl: UISegmentedControl = {
        let items = ["Activity", "Moments"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    // Camera button for Moments tab
    private let momentsCameraButton: UIButton = {
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
    
    private let activityTableView: UITableView = {
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
    
    // Reels collection view for vertical video feed
    private let reelsCollectionView: UICollectionView = {
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
    private var currentReelIndex = 0
    private var reelPlayers: [Int: AVPlayer] = [:]
    
    // Track video loading states to prevent index misalignment
    enum VideoLoadState {
        case notLoaded
        case loading
        case ready
        case failed
    }
    private var reelVideoStates: [Int: VideoLoadState] = [:]
    
    private let activityEmptyStateLabel: UILabel = {
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
    
    private let activityLoadingContainer: UIView = {
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
    
    private var activityLoadingIndicator: UIActivityIndicatorView {
        // Get the indicator from the container using the tag
        return activityLoadingContainer.subviews.first(where: { $0 is UIActivityIndicatorView }) as? UIActivityIndicatorView ?? UIActivityIndicatorView()
    }
    
    // Floating record button for Reels tab
    private let floatingRecordButton: UIButton = {
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
    
    private let loadMoreIndicatorView: UIView = {
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
        
        print("🟡 CirclesHomeViewController viewDidLoad called")
        print("🟡 Instance: \(ObjectIdentifier(self))")
        
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
            print("🟡 Found cached places: \(cachedPlaces.count) - storing for later display")
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
        print("⚡ [Enhanced] loadData called - attempting optimized loading")
        
        // Show progressive skeleton loading immediately
        showProgressiveSkeletonLoading()
        
        // Check cache first for ultra-fast loading
        if let cachedContent = optimizedCache.retrieve() {
            print("⚡ [Cache Hit] Using cached data for instant loading")
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
                print("⚡ [Fast API] Successfully loaded via homescreen endpoint")
                self.isUsingFastLoad = true
                self.hideProgressiveSkeletonLoading()
                
                // Background load full data for completeness
                DispatchQueue.global(qos: .background).async {
                    self.loadFullDashboardData()
                }
            } else {
                print("⚡ [Fallback] Fast API failed, using full dashboard")
                self.loadFullDashboardData()
            }
            
            completion?()
        }
    }
    */
    
    // MARK: - Safe Cache Optimization (Step 1)
    private func tryLoadFromCache() {
        // Only try cache if we haven't started loading yet
        guard !hasStartedLoading && circles.isEmpty else { 
            print("📦 [SafeCache] Skipping - already loading or have data")
            return 
        }
        
        // Check if we have cached data
        if let cachedContent = optimizedCache.retrieve() {
            print("📦 [SafeCache] Found cached data - applying as background enhancement")
            
            // Apply cached circles and places for immediate map population
            if !cachedContent.myCircles.isEmpty && circles.isEmpty {
                self.circles = cachedContent.myCircles
                self.networkCircles = cachedContent.networkCircles
                print("📦 [SafeCache] Applied \(cachedContent.myCircles.count) cached circles")
                
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
                print("📦 [SafeCache] Applied \(cachedContent.activities.count) cached activities")
            }
            
            // Start background image preloading
            DispatchQueue.global(qos: .background).async {
                self.preloadImagesFromCache(cachedContent)
            }
        }
    }
    
    private func preloadImagesFromCache(_ data: HomeScreenContent) {
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
        
        print("📦 [SafeCache] Preloading \(uniqueUrls.count) images in background")
        
        CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
            print("📦 [SafeCache] Preloaded \(loadedCount)/\(uniqueUrls.count) images")
        }
    }
    
    // MARK: - Background Image Preloading (Step 2)
    private func startBackgroundImagePreloading() {
        DispatchQueue.global(qos: .background).async {
            // Check if we have any data to preload from
            if !self.allPlaces.isEmpty {
                self.preloadPlaceImages()
            }
            
            // Clean up expired cache periodically
            CacheService.shared.cleanExpiredCache()
        }
    }
    
    private func preloadPlaceImages() {
        let imageUrls = allPlaces.compactMap { place in
            // Extract first photo URL from Place model
            return place.photos?.first
        }
        
        let uniqueUrls = Array(Set(imageUrls))
        
        guard !uniqueUrls.isEmpty else { return }
        
        print("🖼️ [BackgroundPreload] Starting preload of \(uniqueUrls.count) place images")
        
        CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
            print("🖼️ [BackgroundPreload] Completed: \(loadedCount)/\(uniqueUrls.count) place images cached")
        }
    }
    
    // MARK: - Optional Skeleton Loading (Step 3)
    private var skeletonTimer: Timer?
    
    private func scheduleOptionalSkeletonLoading() {
        // Only show skeleton if we have no data and loading takes longer than 1.5 seconds
        guard circles.isEmpty && activities.isEmpty else { return }
        
        skeletonTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Only show if we still have no data
            if self.circles.isEmpty && self.activities.isEmpty && !self.hasStartedLoading {
                print("💀 [OptionalSkeleton] Loading is slow - showing skeleton")
                self.showOptionalSkeletonLoading()
            }
        }
    }
    
    private func showOptionalSkeletonLoading() {
        guard skeletonLoadingView == nil else { return }
        
        print("💀 [OptionalSkeleton] Showing skeleton for slow connection")
        
        // Create and show skeleton view
        skeletonLoadingView = showSkeletonLoading(in: view)
        
        // Hide main content initially
        mapContainerView.alpha = 0.3 // Keep slightly visible
        activityTableView.alpha = 0.3
        userListView.alpha = 0.3
    }
    
    private func hideOptionalSkeletonLoading() {
        skeletonTimer?.invalidate()
        skeletonTimer = nil
        
        guard let skeleton = skeletonLoadingView else { return }
        
        print("💀 [OptionalSkeleton] Hiding skeleton - data loaded")
        
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
    private var hasTriedFastAPI = false
    
    private func tryFastAPIAsAlternative() {
        // Only try once per session and only if we don't have data yet
        guard !hasTriedFastAPI && circles.isEmpty && activities.isEmpty else { return }
        
        hasTriedFastAPI = true
        print("🚀 [Step4] Attempting fast API as alternative data source")
        
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
                    print("🚀 [Step4] Fast API succeeded - applying alternative data")
                    
                    // Apply the fast data as an alternative source
                    if let userList = response.data?.userList, !userList.isEmpty {
                        // Refresh user list view to show updated data
                        self.userListView.refresh()
                        print("🚀 [Step4] Applied \\(userList.count) users from fast API")
                    }
                    
                    if let activities = response.data?.recentActivities, !activities.isEmpty && self.activities.isEmpty {
                        self.activities = activities
                        self.activityTableView.reloadData()
                        self.activityLoadingContainer.isHidden = true
                        print("🚀 [Step4] Applied \\(activities.count) activities from fast API")
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
                    print("🚀 [Step4] Fast API failed, will continue with regular loading: \\(error)")
                    // Don't show error to user - this is just an optimization attempt
                    // Regular loading will continue normally
                }
            }
        }
    }
    
    // MARK: - Progressive Skeleton Loading
    private func showProgressiveSkeletonLoading() {
        guard skeletonLoadingView == nil else { return }
        
        print("💀 [Skeleton] Showing progressive loading skeleton")
        
        // Create and show skeleton view
        skeletonLoadingView = showSkeletonLoading(in: view)
        
        // Hide main content initially
        mapContainerView.alpha = 0
        activityTableView.alpha = 0
        userListView.alpha = 0
    }
    
    private func hideProgressiveSkeletonLoading() {
        guard let skeleton = skeletonLoadingView else { return }
        
        print("💀 [Skeleton] Hiding progressive loading skeleton")
        
        // Animate content in and skeleton out
        UIView.animate(withDuration: 0.3, animations: {
            self.mapContainerView.alpha = 1.0
            self.activityTableView.alpha = 1.0
            self.userListView.alpha = 1.0
        })
        
        hideSkeletonLoading(skeleton)
        skeletonLoadingView = nil
    }
    
    private func updateProgressiveLoading(stage: ProgressiveLoadingStage) {
        print("💀 [Progressive] Loading stage: \(stage)")
        
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
    private func loadHomeScreenDataFast(completion: @escaping (Bool) -> Void) {
        print("⚡ [FastLoad] Fetching ultra-fast home screen data...")
        
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
                    print("⚡ [FastLoad] Success in \(loadTime)ms - Users: \(response.data.userList.count), Activities: \(response.data.activities.count)")
                    
                    // Apply user list immediately for horizontal scroll
                    self.applyFastUserList(response.data.userList)
                    
                    // Apply recent activities immediately
                    self.applyFastActivities(response.data.activities)
                    
                    // Show UI immediately
                    self.showHomeScreenUI()
                    
                    completion(true)
                    
                case .failure(let error):
                    print("⚡ [FastLoad] Failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Full Dashboard Data Loading (Background)
    private func loadFullDashboardData() {
        print("📊 [FullLoad] Loading complete dashboard data...")
        
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
                    print("📊 [FullLoad] Success in \(loadTime)ms - Full data loaded")
                    
                    // Cache the full data for next time
                    self.optimizedCache.store(response.data)
                    
                    // Apply full data (this will enhance what's already displayed)
                    self.applyHomeScreenData(response.data)
                    
                    // Update map with places if available
                    if let mapData = response.data.mapData {
                        self.applyMapData(mapData)
                    }
                    
                case .failure(let error):
                    print("📊 [FullLoad] Failed: \(error.localizedDescription)")
                    // Fallback to legacy loading if needed
                    if !self.isUsingFastLoad {
                        self.fetchCircles()
                    }
                }
            }
        }
    }
    
    // MARK: - Fast Data Application Methods
    private func applyFastUserList(_ userList: [UserListItem]) {
        print("⚡ [FastApply] Applying user list with \(userList.count) users")
        
        // For now, trigger a refresh of the user list view to show the most recent data
        // The HorizontalUserListView will load its own connection data
        userListView.refresh()
        userListView.isHidden = userList.isEmpty
        
        // Trigger progressive loading update
        updateProgressiveLoading(stage: .userListLoaded)
        
        print("⚡ [FastApply] User list updated and visible")
    }
    
    private func applyFastActivities(_ activities: [Activity]) {
        print("⚡ [FastApply] Applying \(activities.count) activities")
        
        self.activities = activities
        
        // Update activity table immediately
        activityTableView.reloadData()
        activityLoadingContainer.isHidden = true
        
        // Show activity view
        activityTableView.isHidden = false
        
        // Trigger progressive loading update
        updateProgressiveLoading(stage: .activitiesLoaded)
        
        print("⚡ [FastApply] Activities updated and visible")
    }
    
    private func showHomeScreenUI() {
        print("⚡ [FastApply] Showing home screen UI")
        
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
        
        print("⚡ [FastApply] Home screen UI visible")
    }
    
    private func applyHomeScreenData(_ data: HomeScreenContent) {
        print("📊 [FullApply] Applying complete home screen data")
        
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
        
        print("📊 [FullApply] Complete data applied - Activities: \(data.activities.count)")
    }
    
    // MARK: - Image Preloading
    private func preloadImages(from data: HomeScreenContent) {
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
        
        print("📷 [Preload] Starting background preload of \(uniqueUrls.count) images")
        
        // Preload images in background
        DispatchQueue.global(qos: .background).async {
            CacheService.shared.preloadImages(from: uniqueUrls) { loadedCount in
                print("📷 [Preload] Completed: \(loadedCount)/\(uniqueUrls.count) images cached")
            }
        }
    }
    
    private func applyMapData(_ mapData: MapData) {
        print("🗺️ [MapApply] Applying map data with \(mapData.places.count) places")
        
        // Set map region immediately for better UX
        if let bounds = mapData.bounds {
            // TODO: Set map region once the correct map view property is identified
            print("🗺️ [MapApply] Map region update requested (deferred)")
        }
        
        // Start progressive place loading
        loadMapPlacesProgressively(mapData.places)
    }
    
    // MARK: - Progressive Map Loading
    private func loadMapPlacesProgressively(_ mapPlaces: [MapPlace]) {
        print("🗺️ [Progressive] Starting progressive map loading for \(mapPlaces.count) places")
        
        // Load places in batches for smooth performance
        let batchSize = 10
        let batches = mapPlaces.chunked(into: batchSize)
        
        var loadedPlaces: [Place] = []
        var batchIndex = 0
        
        func loadNextBatch() {
            guard batchIndex < batches.count else {
                print("🗺️ [Progressive] Completed loading all \(loadedPlaces.count) places")
                isMapDataReady = true
                return
            }
            
            let currentBatch = batches[batchIndex]
            print("🗺️ [Progressive] Loading batch \(batchIndex + 1)/\(batches.count) (\(currentBatch.count) places)")
            
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
    private func updateMapWithPlaces(_ places: [Place], animated: Bool = false) {
        print("🗺️ [UpdateMap] Map update requested for \(places.count) places")
        
        // Update the embedded map controller with smooth loading
        guard let mapVC = mapViewController else {
            print("🗺️ [UpdateMap] No map controller available, skipping update")
            return
        }
        
        // Use the embedded map controller's smooth update method
        mapVC.updatePlaces(places)
        
        print("🗺️ [UpdateMap] Map update delegated to embedded map controller")
    }
    
    private func updateUIAfterDataLoad() {
        // TODO: Re-enable these methods once they're identified in the existing codebase
        // For now, we'll skip these updates to get the basic functionality working
        
        // Update empty state
        updateEmptyState()
        
        // Update notification badge  
        updateNotificationBadge()
        
        print("📊 [UpdateUI] UI updates completed")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Invalidate reels collection view layout to ensure proper sizing
        if reelsCollectionView.bounds.width > 0 {
            reelsCollectionView.collectionViewLayout.invalidateLayout()
        }
        
        // Apply gradients to cards with Google Maps blue
        let googleMapsBlue = UIColor(red: 66/255.0, green: 133/255.0, blue: 244/255.0, alpha: 1.0)
        
        addGradientToCard(homeCard, colors: [
            googleMapsBlue,
            googleMapsBlue.withAlphaComponent(0.85)
        ])
        
        addGradientToCard(workCard, colors: [
            googleMapsBlue,
            googleMapsBlue.withAlphaComponent(0.85)
        ])
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
        
        print("🟢 CirclesHomeViewController viewWillAppear called")
        print("🟢 Instance: \(ObjectIdentifier(self))")
        print("   hasStartedLoading: \(hasStartedLoading)")
        print("   isReturningFromFullScreenMap: \(isReturningFromFullScreenMap)")
        print("   circles.count: \(circles.count)")
        print("   allPlaces.count: \(allPlaces.count)")
        print("   preloadedData: \(preloadedData != nil)")
        
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
        print("🔔 CirclesHomeViewController: Updating notification badge on viewWillAppear")
        updateNotificationBadge()
        startNotificationBadgeRefresh()
        
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
            print("🟢 Using preloaded data from splash screen")
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
            print("🟢 Skipping load - this instance has already started loading")
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
            print("🟢 Starting initial data load (after debounce)")
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
        
        // Listen for connections to be loaded before checking tutorial/overlay
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
    
    private func checkAndRetryOnboardingIfNeeded() {
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
    
    @objc private func connectionsLoadedHandler() {
        print("🔔 Connections loaded notification received")
        // Remove observer to prevent multiple calls
        NotificationCenter.default.removeObserver(self, name: .connectionsLoaded, object: nil)
        
        // Check tutorial and overlay now that connections are loaded
        checkTutorialAndOverlay()
    }
    
    private func checkTutorialAndOverlay() {
        // Only check once per session
        guard !hasCheckedTutorialAndOverlay else {
            print("⚠️ Already checked tutorial and overlay")
            return
        }
        hasCheckedTutorialAndOverlay = true
        
        // If no relationship data has loaded yet, wait a bit longer for async data
        let hasAnyLoadedData = NetworkManager.shared.connections.count > 0 || 
                              NetworkManager.shared.pendingConnections.count > 0 || 
                              userListView.connectionCount > 0
        
        if !hasAnyLoadedData && tutorialCheckRetryCount < maxTutorialCheckRetries {
            tutorialCheckRetryCount += 1
            print("🔍 No relationship data loaded yet, scheduling retry \(tutorialCheckRetryCount)/\(maxTutorialCheckRetries) in 2 seconds")
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
        
        print("🔍 checkTutorialAndOverlay - Accepted connections: \(acceptedConnectionCount), Following: \(horizontalViewCount), Pending: \(pendingConnectionCount), Total: \(totalRelationshipCount)")
        
        // Additional safety check: also check user profile counts as backup
        let currentUser = AuthService.shared.currentUser
        let profileFollowingCount = currentUser?.followingCount ?? 0
        let profileConnectionsCount = currentUser?.connectionsCount ?? 0
        let profileTotalRelationships = profileFollowingCount + profileConnectionsCount
        
        print("🔍 Profile backup check - Following: \(profileFollowingCount), Connections: \(profileConnectionsCount), Profile total: \(profileTotalRelationships)")
        
        // Only show overlay if BOTH the loaded data AND profile data indicate no relationships
        let shouldConsiderAsNewUser = totalRelationshipCount == 0 && profileTotalRelationships == 0
        
        if shouldConsiderAsNewUser {
            print("✅ User has 0 total relationships in both loaded data and profile - checking if should show overlay")
            // For users with 0 total relationships, always show the overlay unless they've explicitly dismissed it this session
            // Reset the flag for users with 0 relationships to ensure they see it
            if !hasCheckedForSuggestedUsers {
                hasCheckedForSuggestedUsers = true  // Set the flag to prevent repeated showing
                // Enable the overlay for users with 0 relationships
                OnboardingManager.shared.enableSuggestedUsersOverlay()
                print("✅ Enabled suggested users overlay for user with 0 relationships")
            }
            
            if OnboardingManager.shared.shouldShowSuggestedUsers {
                print("✅ Should show suggested users overlay - calling showSuggestedUsersOverlay()")
                showSuggestedUsersOverlay()
                return
            } else {
                print("❌ Suggested users overlay disabled in settings")
            }
        } else {
            print("✅ User has relationships (loaded: \(totalRelationshipCount), profile: \(profileTotalRelationships)) - skipping new user overlay")
        }
        
        // Check tutorial status from backend
        OnboardingManager.shared.checkIfUserNeedsTutorial { [weak self] needsTutorial in
            guard let self = self, needsTutorial else { 
                // If no tutorial needed and not already shown overlay, check for suggested users
                if NetworkManager.shared.connections.count > 0 {
                    self?.checkAndShowSuggestedUsers()
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
    
    private func checkAndShowSuggestedUsers() {
        // Only check once per session
        guard !hasCheckedForSuggestedUsers else { 
            print("⚠️ checkAndShowSuggestedUsers - Already checked this session")
            return 
        }
        hasCheckedForSuggestedUsers = true
        
        // Get connection count from NetworkManager
        let connectionCount = NetworkManager.shared.connections.count
        print("🔍 checkAndShowSuggestedUsers - Connection count: \(connectionCount)")
        
        // Check if should show suggested users
        if OnboardingManager.shared.shouldShowSuggestedUsersOverlay(connectionCount: connectionCount) {
            print("✅ Should show suggested users overlay - calling showSuggestedUsersOverlay()")
            showSuggestedUsersOverlay()
        } else {
            print("❌ Should NOT show suggested users overlay")
        }
    }
    
    private func showSuggestedUsersOverlay() {
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
    
    private func showAddPlaceTutorialIfNeeded() {
        // Check if should show add place tutorial
        guard OnboardingManager.shared.shouldShowAddPlaceTutorial() else {
            // Continue with visit tracking permission
            showVisitTrackingPermissionIfNeeded()
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
    
    private func forceShowSuggestedUsersOverlay() {
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
    
    private func forceShowAddPlaceTutorial() {
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
    
    private func showVisitTrackingPermissionIfNeeded() {
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
    
    private func updateAppearance() {
        // Update border colors that don't automatically adapt
        homeCard.layer.borderColor = Constants.Colors.separator.cgColor
        workCard.layer.borderColor = Constants.Colors.separator.cgColor
        quickAccessContainer.layer.shadowColor = Constants.Colors.label.cgColor
        categoryFilterButton.layer.borderColor = Constants.Colors.separator.cgColor
        connectionFilterButton.layer.borderColor = Constants.Colors.separator.cgColor
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        // Removed redundant title - tab bar already shows "My Circles"
        
        // Create custom view for notification button with badge
        setupNotificationBadge()
        
        // Setup empty state view
        emptyStateView.addSubview(emptyStateImageView)
        emptyStateView.addSubview(emptyStateLabel)
        
        // Setup quick access buttons
        setupQuickAccessButtons()
        
        // Add scroll view
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add search bar to main view (not scrolling)
        view.addSubview(searchBar)
        view.addSubview(searchScopeButton)
        view.addSubview(quickAddPlaceButton)
        
        // Add search scope dropdown
        view.addSubview(searchScopeDropdownView)
        searchScopeDropdownView.addSubview(searchScopeTableView)
        
        // Add content to scroll view
        contentView.addSubview(quickAccessContainer)
        quickAccessContainer.addSubview(homeCard)
        quickAccessContainer.addSubview(workCard)
        quickAccessContainer.addSubview(quickAccessCard)
        homeCard.addSubview(homeButton)
        homeCard.addSubview(homeNavigateButton)
        workCard.addSubview(workButton)
        workCard.addSubview(workNavigateButton)
        quickAccessCard.addSubview(quickAccessButton)
        quickAccessCard.addSubview(quickAccessNavigateButton)
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
        
        // Add small loading indicator directly to map container for better UX
        mapContainerView.addSubview(mapLoadingIndicator)
        contentView.addSubview(locationStatusLabel)
        filterStackView.addArrangedSubview(categoryFilterButton)
        filterStackView.addArrangedSubview(connectionFilterButton)
        contentView.addSubview(emptyStateView)
        
        // Add activity feed section
        contentView.addSubview(activityFeedSection)
        activityFeedSection.addSubview(activityHeaderLabel)
        activityFeedSection.addSubview(contentSegmentedControl)
        activityFeedSection.addSubview(momentsCameraButton)
        activityFeedSection.addSubview(activityTableView)
        activityFeedSection.addSubview(reelsCollectionView)
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
        
        // Add dropdown views
        view.addSubview(categoryDropdownView)
        view.addSubview(connectionDropdownView)
        categoryDropdownView.addSubview(categoryDropdownTableView)
        connectionDropdownView.addSubview(connectionDropdownTableView)
        
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
            // Search bar (fixed at top)
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            searchBar.trailingAnchor.constraint(equalTo: searchScopeButton.leadingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            // Search scope button
            searchScopeButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchScopeButton.trailingAnchor.constraint(equalTo: quickAddPlaceButton.leadingAnchor, constant: -Constants.Spacing.small),
            searchScopeButton.widthAnchor.constraint(equalToConstant: 32),
            searchScopeButton.heightAnchor.constraint(equalToConstant: 32),
            
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
            
            // Quick access container (now in content view)
            quickAccessContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            quickAccessContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            quickAccessContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            quickAccessContainer.heightAnchor.constraint(equalToConstant: 50),
            
            // Quick Add Place button
            quickAddPlaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            quickAddPlaceButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            quickAddPlaceButton.heightAnchor.constraint(equalToConstant: 40),
            quickAddPlaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            // Home card
            homeCard.leadingAnchor.constraint(equalTo: quickAccessContainer.leadingAnchor, constant: Constants.Spacing.large),
            homeCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            homeCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.28),
            homeCard.heightAnchor.constraint(equalToConstant: 40),
            
            // Quick Access card (with spacing from home card)
            quickAccessCard.leadingAnchor.constraint(equalTo: homeCard.trailingAnchor, constant: Constants.Spacing.small),
            quickAccessCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            quickAccessCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.28),
            quickAccessCard.heightAnchor.constraint(equalToConstant: 40),
            
            // Work card (with spacing from quick access card)
            workCard.leadingAnchor.constraint(equalTo: quickAccessCard.trailingAnchor, constant: Constants.Spacing.small),
            workCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            workCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.28),
            workCard.heightAnchor.constraint(equalToConstant: 40),
            
            // Home button (inside home card)
            homeButton.leadingAnchor.constraint(equalTo: homeCard.leadingAnchor),
            homeButton.topAnchor.constraint(equalTo: homeCard.topAnchor),
            homeButton.bottomAnchor.constraint(equalTo: homeCard.bottomAnchor),
            homeButton.trailingAnchor.constraint(equalTo: homeNavigateButton.leadingAnchor, constant: -8),
            
            // Home navigate button
            homeNavigateButton.centerYAnchor.constraint(equalTo: homeCard.centerYAnchor),
            homeNavigateButton.trailingAnchor.constraint(equalTo: homeCard.trailingAnchor, constant: -8),
            homeNavigateButton.widthAnchor.constraint(equalToConstant: 24),
            homeNavigateButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Work button (inside work card)
            workButton.leadingAnchor.constraint(equalTo: workCard.leadingAnchor),
            workButton.topAnchor.constraint(equalTo: workCard.topAnchor),
            workButton.bottomAnchor.constraint(equalTo: workCard.bottomAnchor),
            workButton.trailingAnchor.constraint(equalTo: workNavigateButton.leadingAnchor, constant: -8),
            
            // Work navigate button
            workNavigateButton.centerYAnchor.constraint(equalTo: workCard.centerYAnchor),
            workNavigateButton.trailingAnchor.constraint(equalTo: workCard.trailingAnchor, constant: -8),
            workNavigateButton.widthAnchor.constraint(equalToConstant: 24),
            workNavigateButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Quick Access button (inside quick access card)
            quickAccessButton.leadingAnchor.constraint(equalTo: quickAccessCard.leadingAnchor),
            quickAccessButton.topAnchor.constraint(equalTo: quickAccessCard.topAnchor),
            quickAccessButton.bottomAnchor.constraint(equalTo: quickAccessCard.bottomAnchor),
            quickAccessButton.trailingAnchor.constraint(equalTo: quickAccessNavigateButton.leadingAnchor, constant: -8),
            
            // Quick Access navigate button
            quickAccessNavigateButton.centerYAnchor.constraint(equalTo: quickAccessCard.centerYAnchor),
            quickAccessNavigateButton.trailingAnchor.constraint(equalTo: quickAccessCard.trailingAnchor, constant: -8),
            quickAccessNavigateButton.widthAnchor.constraint(equalToConstant: 24),
            quickAccessNavigateButton.heightAnchor.constraint(equalToConstant: 24),
            
            // User list view
            userListView.topAnchor.constraint(equalTo: quickAccessContainer.bottomAnchor, constant: Constants.Spacing.small),
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
            emptyStateLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
            
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
            categoryFilterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            connectionFilterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            
            // Category dropdown
            categoryDropdownView.topAnchor.constraint(equalTo: categoryFilterButton.bottomAnchor, constant: 4),
            categoryDropdownView.leadingAnchor.constraint(equalTo: categoryFilterButton.leadingAnchor),
            categoryDropdownView.widthAnchor.constraint(equalToConstant: 200),
            
            categoryDropdownTableView.topAnchor.constraint(equalTo: categoryDropdownView.topAnchor),
            categoryDropdownTableView.leadingAnchor.constraint(equalTo: categoryDropdownView.leadingAnchor),
            categoryDropdownTableView.trailingAnchor.constraint(equalTo: categoryDropdownView.trailingAnchor),
            categoryDropdownTableView.bottomAnchor.constraint(equalTo: categoryDropdownView.bottomAnchor),
            
            // Connection dropdown
            connectionDropdownView.topAnchor.constraint(equalTo: connectionFilterButton.bottomAnchor, constant: 4),
            connectionDropdownView.leadingAnchor.constraint(equalTo: connectionFilterButton.leadingAnchor),
            connectionDropdownView.widthAnchor.constraint(equalToConstant: 200),
            
            connectionDropdownTableView.topAnchor.constraint(equalTo: connectionDropdownView.topAnchor),
            connectionDropdownTableView.leadingAnchor.constraint(equalTo: connectionDropdownView.leadingAnchor),
            connectionDropdownTableView.trailingAnchor.constraint(equalTo: connectionDropdownView.trailingAnchor),
            connectionDropdownTableView.bottomAnchor.constraint(equalTo: connectionDropdownView.bottomAnchor),
            
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
        
        categoryDropdownHeightConstraint = categoryDropdownView.heightAnchor.constraint(equalToConstant: 0)
        categoryDropdownHeightConstraint?.isActive = true
        
        connectionDropdownHeightConstraint = connectionDropdownView.heightAnchor.constraint(equalToConstant: 0)
        connectionDropdownHeightConstraint?.isActive = true
        
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
        categoryFilterButton.addTarget(self, action: #selector(categoryFilterButtonTapped), for: .touchUpInside)
        connectionFilterButton.addTarget(self, action: #selector(connectionFilterButtonTapped), for: .touchUpInside)
        searchScopeButton.addTarget(self, action: #selector(searchScopeButtonTapped), for: .touchUpInside)
        
        setupMapView()
        setupActivityFeed()
    }
    
    private func setupMapView() {
        let mapVC = FullScreenMapViewController()
        mapVC.viewMode = .allPlaces
        mapVC.delegate = self
        
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
    
    private func setupDropdownViews() {
        // Setup dropdown table views
        categoryDropdownTableView.delegate = self
        categoryDropdownTableView.dataSource = self
        categoryDropdownTableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryDropdownCell")
        categoryDropdownTableView.delaysContentTouches = false
        categoryDropdownTableView.canCancelContentTouches = true
        
        connectionDropdownTableView.delegate = self
        connectionDropdownTableView.dataSource = self
        connectionDropdownTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ConnectionDropdownCell")
        connectionDropdownTableView.delaysContentTouches = false
        connectionDropdownTableView.canCancelContentTouches = true
        
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
    
    private func setupActivityFeed() {
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
        
        // Setup segmented control
        contentSegmentedControl.addTarget(self, action: #selector(contentSegmentChanged), for: .valueChanged)
        
        // Set scroll view delegate for pagination
        scrollView.delegate = self
        
        // Add refresh control to scroll view
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshActivityFeed), for: .valueChanged)
        scrollView.refreshControl = refreshControl
    }
    
    private func setupSearchBar() {
        searchBar.delegate = self
        
        // Add toolbar with Done button to search bar
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        
        toolbar.items = [flexSpace, doneButton]
        searchBar.inputAccessoryView = toolbar
    }
    
    @objc private func dismissKeyboard() {
        // Called from Done button, always dismiss
        searchBar.resignFirstResponder()
    }
    
    private func setupQuickAccessButtons() {
        // Configure Home button
        var homeConfig = UIButton.Configuration.filled()
        homeConfig.image = UIImage(systemName: "house.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        homeConfig.title = "Home"
        homeConfig.imagePlacement = .leading
        homeConfig.imagePadding = 4
        homeConfig.baseBackgroundColor = .clear
        homeConfig.baseForegroundColor = .white
        homeConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        homeConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        homeButton.configuration = homeConfig
        homeButton.addTarget(self, action: #selector(homeButtonTapped), for: .touchUpInside)
        
        // Configure Work button
        var workConfig = UIButton.Configuration.filled()
        workConfig.image = UIImage(systemName: "building.2.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        workConfig.title = "Work"
        workConfig.imagePlacement = .leading
        workConfig.imagePadding = 4
        workConfig.baseBackgroundColor = .clear
        workConfig.baseForegroundColor = .white
        workConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        workConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        workButton.configuration = workConfig
        workButton.addTarget(self, action: #selector(workButtonTapped), for: .touchUpInside)
        
        // Configure Quick Access button
        var quickAccessConfig = UIButton.Configuration.filled()
        quickAccessConfig.image = UIImage(systemName: "star.fill")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        quickAccessConfig.title = "Places"
        quickAccessConfig.imagePlacement = .leading
        quickAccessConfig.imagePadding = 4
        quickAccessConfig.baseBackgroundColor = .clear
        quickAccessConfig.baseForegroundColor = .white
        quickAccessConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        quickAccessConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        quickAccessButton.configuration = quickAccessConfig
        quickAccessButton.addTarget(self, action: #selector(quickAccessButtonTapped), for: .touchUpInside)
        
        // Update Quick Access button title based on saved places count
        updateQuickAccessButtonTitle()
        
        // Add targets for navigate buttons
        homeNavigateButton.addTarget(self, action: #selector(homeNavigateButtonTapped), for: .touchUpInside)
        workNavigateButton.addTarget(self, action: #selector(workNavigateButtonTapped), for: .touchUpInside)
        quickAccessNavigateButton.addTarget(self, action: #selector(quickAccessNavigateButtonTapped), for: .touchUpInside)
        
        // Remove shadow from container since cards have their own shadows
        quickAccessContainer.layer.shadowOpacity = 0
        
        // Apply appearance
        updateAppearance()
    }
    
    // Navigation title tap removed since we no longer show the title
    
    // MARK: - Cache Management
    
    private func isCacheValid() -> Bool {
        guard let expiry = placesCacheExpiry else { return false }
        return Date() < expiry && !cachedPlaces.isEmpty
    }
    
    private func invalidateCache() {
        cachedPlaces.removeAll()
        userOwnPlaces.removeAll()
        placesCacheExpiry = nil
        print("🗑️ Places cache invalidated")
    }
    
    private func shouldUseCachedData() -> Bool {
        return isCacheValid() && !isPerformingInitialLoad
    }
    
    private func addGradientToCard(_ card: UIView, colors: [UIColor]) {
        // Remove any existing gradient layers
        card.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = card.bounds
        gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = 8
        
        card.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    // MARK: - Preloaded Data
    func setPreloadedData(_ data: PreloadedData) {
        // Store connections separately so they're available when userListView is lazily created
        self.preloadedConnections = data.connections
        self.preloadedData = data
    }
    
    private func usePreloadedData(_ data: PreloadedData) {
        // Set circles and places
        self.circles = data.circles
        
        // Set activities and moments from preloaded data
        self.activities = data.activities
        self.reels = data.moments
        
        print("📍 usePreloadedData: Got \(data.circles.count) circles")
        print("📍 usePreloadedData: Got \(data.allPlaces.count) places (INCOMPLETE!)")
        print("📍 usePreloadedData: Got \(data.connections.count) connections")
        print("📍 usePreloadedData: Got \(data.activities.count) activities")
        print("📍 usePreloadedData: Got \(data.moments.count) moments")
        print("📍 usePreloadedData: Should have 124 places according to profile")
        
        // Don't set initial connections from preloaded data since they don't have message timestamps
        // The connections will be properly loaded with all data in viewWillAppear via refresh()
        print("✅ usePreloadedData: Skipping initial connections - will load with proper data via refresh()")
        
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
            self.connectionFilterButton.setTitle("All Connections", for: .normal)
            
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
            
            print("✅ Preloaded data applied successfully")
            print("   - Circles: \(self.circles.count)")
            print("   - Places: \(self.allPlaces.count) (INCOMPLETE - need to fetch all)")
            print("   - Filtered places: \(self.filteredPlaces.count)")
            print("   - Activities: \(self.activities.count)")
            print("   - Moments: \(self.reels.count)")
            
            // Now fetch ALL places from circles
            self.fetchAllPlacesFromCircles()
        }
    }
    
    // MARK: - Activity Feed Methods
    @objc private func refreshActivityFeed() {
        // Refresh the horizontal user list
        userListView.refresh()
        
        // Check for daily summary data
        checkForDailySummary()
        
        // Refresh content based on selected tab
        if contentSegmentedControl.selectedSegmentIndex == 0 {
            fetchActivities()
        } else {
            fetchReels()
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
        
        if selectedIndex == 0 {
            // Show Activity feed
            activityTableView.isHidden = false
            reelsCollectionView.isHidden = true
            momentsCameraButton.isHidden = true
            activityHeaderLabel.text = "Recent Activity"
            
            // Pause any playing videos
            pauseAllVideos()
            
            // Load activities if needed
            if activities.isEmpty {
                fetchActivities()
            }
        } else {
            // Show Reels feed
            activityTableView.isHidden = true
            reelsCollectionView.isHidden = false
            
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
        }
    }
    
    private func fetchActivities(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isLoadingActivities && !isLoadingMoreActivities else { 
            print("🔄 Already loading activities, skipping...")
            completion?(false)
            return 
        }
        
        // Don't load more if we've reached the end
        if loadMore && !hasMoreActivities {
            print("📊 No more activities to load")
            completion?(false)
            return
        }
        
        print("📊 Starting to fetch activities... (loadMore: \(loadMore))")
        print("📊 activityLoadingContainer.isHidden before: \(activityLoadingContainer.isHidden)")
        print("📊 activityLoadingIndicator.isAnimating before: \(activityLoadingIndicator.isAnimating)")
        
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
            
            print("📊 activityLoadingContainer.isHidden after: \(activityLoadingContainer.isHidden)")
            print("📊 activityLoadingIndicator.isAnimating after: \(activityLoadingIndicator.isAnimating)")
            print("📊 activityTableView.isHidden: \(activityTableView.isHidden)")
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
                    print("✅ Successfully fetched \(response.activities.count) activities")
                    
                    if loadMore {
                        // Append to existing activities
                        self.activities.append(contentsOf: response.activities)
                    } else {
                        // Replace activities
                        self.activities = response.activities
                    }
                    
                    // Update pagination state
                    self.currentOffset = self.activities.count ?? 0
                    self.hasMoreActivities = response.hasMore
                    
                    print("📊 Total activities: \(self.activities.count ?? 0), hasMore: \(response.hasMore)")
                    
                    self.updateActivityFeed()
                    
                case .failure(let error):
                    print("❌ Error fetching activities: \(error)")
                    print("🔍 Error details: \(error.localizedDescription)")
                    
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
    
    private func updateActivityFeed() {
        isLoadingActivities = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show table view if Activity tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 2 {
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
    private func fetchReels(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
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
                    print("❌ Error fetching reels: \(error)")
                    
                    // Handle specific error types gracefully
                    var isHandledError = false
                    
                    if case APIError.serverError = error {
                        // Check if this is the "too many disjunctions" error
                        let errorString = error.localizedDescription
                        if errorString.contains("Too many disjunctions") || errorString.contains("32 disjunctions") {
                            print("🔍 Detected Firestore disjunction limit error - showing user-friendly message")
                            
                            if !loadMore {
                                self.showFirestoreQueryLimitError()
                                isHandledError = true
                            }
                        }
                    } else if case APIError.rateLimited = error {
                        print("🔍 Rate limited loading Moments feed - showing fallback content")
                        
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
    
    private func updateReelsFeed() {
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
    
    private func showFirestoreQueryLimitError() {
        isLoadingReels = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show collection view if Moments tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 1 {
            reelsCollectionView.isHidden = false
        }
        activityEmptyStateLabel.text = "Too much content to load right now! Try refreshing in a few moments, or check back later for your Moments feed."
        activityEmptyStateLabel.isHidden = false
        
        print("🔍 Showing user-friendly message for Firestore query limit")
        
        // Clear reels array to show empty state
        reels = []
        reelsCollectionView.reloadData()
        
        // Auto-retry after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            print("🔍 Auto-retrying Moments feed after Firestore error")
            self?.fetchReels()
        }
    }
    
    private func showMomentsFeedFallback() {
        isLoadingReels = false
        activityLoadingIndicator.stopAnimating()
        activityLoadingContainer.isHidden = true
        
        // Only show collection view if Moments tab is selected
        if contentSegmentedControl.selectedSegmentIndex == 1 {
            reelsCollectionView.isHidden = false
        }
        activityEmptyStateLabel.text = "Feed temporarily unavailable due to high activity. Pull to refresh to try again!"
        activityEmptyStateLabel.isHidden = false
        
        print("🔍 Showing fallback message for rate limited Moments feed")
        
        // Clear reels array to show empty state
        reels = []
        reelsCollectionView.reloadData()
        
        // Enable pull-to-refresh for immediate retry
        scrollView.refreshControl?.isEnabled = true
    }
    
    // MARK: - Data Fetching
    private func performInitialDataLoad() {
        
        // Unified method to load both circles and places
        print("🚀 Starting OPTIMIZED initial data load")
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
                print("✅ Fetched \(circles.count) user circles")
            case .failure(let error):
                print("❌ Failed to fetch user circles: \(error)")
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
                print("✅ Fetched \(response.data.count) network circles")
            case .failure(let error):
                print("❌ Failed to fetch network circles: \(error)")
            }
            group.leave()
        }
        
        // 3. Load activities (parallel)
        group.enter()
        ActivityService.shared.getNetworkActivities(limit: 20, offset: 0) { result in
            switch result {
            case .success(let response):
                activitiesResult = response.activities
                print("✅ Fetched \(response.activities.count) activities")
            case .failure(let error):
                print("❌ Failed to fetch activities: \(error)")
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
                print("✅ Fetched \(reelsResult.count) moments")
            case .failure(let error):
                print("❌ Failed to fetch moments: \(error)")
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
            print("⏱️ Phase 1 completed in \(String(format: "%.2f", circleLoadTime)) seconds")
            
            // Update UI
            self.updateEmptyState()
            self.updateActivityFeed()
            
            // Now fetch places from all circles in parallel
            let allCircles = myCirclesResult + networkCirclesResult
            guard !allCircles.isEmpty else {
                self.isMapDataReady = true
                self.updateMapWhenReady()
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false
                self.hideLoadingState()
                self.userListView.refresh()
                
                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                print("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds (no circles)")
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
                                
                                print("🗺️ [Progressive] Updated map with \(uniquePlaces.count) places (\(loadedCircles)/\(totalCircles) circles loaded)")
                            }
                            
                        case .failure(let error):
                            print("❌ Failed to fetch places for circle '\(circle.name)': \(error)")
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
                print("✅ OPTIMIZED load completed in \(String(format: "%.2f", totalTime)) seconds")
                print("   - My circles: \(myCirclesResult.count)")
                print("   - Network circles: \(networkCirclesResult.count)")
                print("   - Total places: \(uniquePlaces.count)")
                print("   - Activities: \(activitiesResult.count)")
                print("   - Moments: \(reelsResult.count)")
            }
        }
    }
    
    private func showMapLoadingState() {
        // Prevent showing loading state multiple times
        guard !isShowingLoadingUI else { 
            print("🗺️ Map loading state already showing")
            return 
        }
        
        print("🗺️ Showing map with loading indicator")
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
    
    private func hideMapLoadingState() {
        print("🗺️ Hiding map loading state, showing populated map")
        print("🗺️ About to call fetchActivities from hideMapLoadingState")
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
        
        // Show place count now that loading is complete with animation
        mapViewController?.showPlaceCount()
        mapPlaceCountLabel.alpha = 0
        mapPlaceCountLabel.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.mapPlaceCountLabel.alpha = 1
        }
        
        // Activities and moments are already loaded in performInitialDataLoad
        // No need to fetch again here
    }
    
    // NEW: Immediate loading state to prevent empty map confusion
    private func showMapLoadingStateImmediate() {
        print("🗺️ [IMMEDIATE] Showing map loading state on viewWillAppear")
        
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
    private func extractAndShowCachedPlaces() {
        // For now, skip cached place extraction since creating dummy Place objects
        // requires complex initialization. The immediate loading indicator is more important
        // and provides the main UX benefit the user requested.
        
        // Update loading message to indicate we found cached circles
        DispatchQueue.main.async { [weak self] in
            self?.mapLoadingLabel.text = "Found \(self?.circles.count ?? 0) circles, loading places..."
            print("📦 [Cache→Map] Found cached circles, will load places next")
        }
    }
    
    // PROGRESSIVE MAP UPDATES: Update map with places as they become available
    private func updateMapProgressively(with places: [Place], isFromCache: Bool = false) {
        // Only update if we have places and the map is ready
        guard !places.isEmpty else { return }
        
        // Store places
        if isFromCache {
            // Cached places are temporary - will be replaced with full data
            print("🗺️ [Progressive] Showing \(places.count) cached places temporarily")
        } else {
            // Full place data
            self.allPlaces = places
            self.userOwnPlaces = places.filter { place in
                circles.contains { circle in
                    circle.places?.contains(place.id) == true
                }
            }
            print("🗺️ [Progressive] Populated map with \(places.count) full places")
            
            // Update available categories now that we have places
            self.updateAvailableCategories()
        }
        
        // Apply filters and update map
        let placesToDisplay = applyFiltersToPlaces(places)
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
    
    private func fetchCircles(completion: (() -> Void)? = nil) {
        // Only show loading state on the very first app launch
        isLoadingCircles = true
        
        print("🔍 DEBUG fetchCircles() called - About to call CircleService.fetchUserCircles")
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            print("🔍 DEBUG fetchCircles() completion called")
            DispatchQueue.main.async {
                self.isLoadingCircles = false
                
                switch result {
                case .success(let circles):
                    print("✅ Successfully fetched \(circles.count) user circles")
                    print("🔍 DEBUG - User Circle Details:")
                    for (index, circle) in circles.enumerated() {
                        print("   Circle \(index + 1): '\(circle.name)' (ID: \(circle.id), Places: \(circle.placesCount ?? 0))")
                    }
                    self.circles = circles
                    print("🔍 DEBUG - After assignment, self.circles.count: \(self.circles.count)")
                    self.fetchAllPlacesFromCircles()
                    completion?()
                    // Don't mark as loaded here - wait until places are fetched
                case .failure(let error):
                    print("❌ Error fetching circles: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                    completion?()
                    
                    // If it's a duplicate request error, still need to clean up state
                    if case .duplicateRequest = error as? APIError {
                        print("❌ Duplicate request detected - cleaning up state")
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
    
    private func fetchNetworkCircles(completion: (() -> Void)? = nil) {
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
                    print("✅ Successfully fetched \(response.data.count) network circles")
                    let currentUserId = AuthService.shared.getUserId() ?? ""
                    let normalizedUserId = IDNormalizer.normalize(currentUserId) ?? currentUserId
                    for circle in response.data {
                        let normalizedOwner = IDNormalizer.normalize(circle.owner) ?? circle.owner
                        print("📍 Network circle received: \(circle.name) by \(circle.owner) (normalized: \(normalizedOwner)), privacy: \(circle.privacy.rawValue)")
                        if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                            print("⚠️ WARNING: Network circles contains user's own circle: \(circle.name)")
                            print("   Circle owner: \(circle.owner)")
                            print("   Current user: \(currentUserId)")
                            print("   Normalized owner: \(normalizedOwner)")
                            print("   Normalized user: \(normalizedUserId)")
                        }
                    }
                    self.networkCircles = response.data
                    self.updateEmptyState()
                    completion?()
                case .failure(let error):
                    print("❌ Error fetching network circles: \(error.localizedDescription)")
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
    
    private func createSampleCircles() -> [Circle] {
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
    
    private func updateEmptyState() {
        // Hide empty state if loading
        if isLoadingCircles || isLoadingPlaces {
            emptyStateView.isHidden = true
            return
        }
        
        if isSearching {
            emptyStateView.isHidden = !filteredPlaces.isEmpty
            emptyStateLabel.text = "No places found"
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
    
    private func fetchAllPlacesFromCircles() {
        // Reset map data ready flag at the start of any fetch
        isMapDataReady = false
        
        print("📍 fetchAllPlacesFromCircles() - Starting fetch process")
        print("📍 User circles count: \(circles.count)")
        print("📍 Network circles count: \(networkCircles.count)")
        
        // ALWAYS fetch all user places to ensure we have the complete 124 places
        // Don't use cached data for user places as it may be incomplete
        print("📍 Fetching all places (cache disabled to ensure complete data)")
        
        // Note: We're commenting out the cache check to ensure we get all 124 user places
        // if shouldUseCachedData() {
        //     print("📍 Using cached places data (\(cachedPlaces.count) places)")
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
        
        print("📍 fetchAllPlacesFromCircles called (cache invalid or expired)")
        print("📍 User circles count: \(circles.count)")
        print("📍 Network circles count: \(networkCircles.count)")
        
        // If no circles at all, just update UI and return
        if circles.isEmpty && networkCircles.isEmpty {
            print("📍 No circles to fetch places from")
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
            print("📍 Network circle: \(circle.name) by \(circle.owner), privacy: \(circle.privacy)")
        }
        
        // Fetch user's own places
        var userPlacesCount = 0
        print("📍 Starting to fetch places from \(circles.count) user circles:")
        for (index, circle) in circles.enumerated() {
            print("   Circle \(index + 1)/\(circles.count): '\(circle.name)' (ID: \(circle.id), Expected places: \(circle.placesCount ?? 0))")
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                switch result {
                case .success(let places):
                    print("✅ Fetched \(places.count) places from USER circle '\(circle.name)' (expected: \(circle.placesCount ?? 0))")
                    userPlacesCount += places.count
                    allFetchedPlaces.append(contentsOf: places)
                case .failure(let error):
                    print("❌ Failed to fetch places for USER circle '\(circle.name)' (id: \(circle.id)): \(error)")
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
                    for circle in response.data {
                        group.enter()
                        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                            switch result {
                            case .success(let places):
                                print("✅ Found \(places.count) places in network circle: \(circle.name)")
                                print("   Circle owner ID: \(circle.owner)")
                                allFetchedPlaces.append(contentsOf: places)
                            case .failure(let error):
                                print("Failed to fetch places for network circle \(circle.id): \(error)")
                            }
                            group.leave()
                        }
                    }
                case .failure(let error):
                    print("Failed to fetch network circles: \(error)")
                    // If it's a duplicate request error, retry
                    if case .duplicateRequest = error {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.fetchNetworkCircles()
                        }
                    }
                }
                group.leave()
            }
        } else {
            // Use existing network circles
            for circle in networkCircles {
                print("📍 Fetching places for network circle: \(circle.name) (\(circle.id))")
                group.enter()
                PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                    switch result {
                    case .success(let places):
                        print("✅ Found \(places.count) places in network circle: \(circle.name)")
                        print("   Circle owner ID: \(circle.owner)")
                        allFetchedPlaces.append(contentsOf: places)
                    case .failure(let error):
                        print("❌ Failed to fetch places for network circle \(circle.name) (\(circle.id)): \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main, execute: { [weak self] in
            guard let self = self else { return }
            
            print("📍 PLACE FETCH COMPLETE - DETAILED SUMMARY:")
            print("   Total raw places fetched: \(allFetchedPlaces.count)")
            print("   User places fetched: \(userPlacesCount)")
            print("   User circles count: \(self.circles.count)")
            print("   Network circles count: \(self.networkCircles.count)")
            
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
            
            print("📍 BEFORE DEDUPLICATION:")
            print("   User places: \(userPlacesBeforeDedup.count)")
            print("   Network places: \(networkPlacesBeforeDedup.count)")
            
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
            
            print("📍 AFTER DEDUPLICATION:")
            print("   User places: \(userPlacesAfterDedup.count) (should be 124 according to user)")
            print("   Network places: \(networkPlacesAfterDedup.count)")
            print("   Total unique places: \(deduplicatedPlaces.count)")
            
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
            
            print("📍 Map Update Summary:")
            print("   Total filtered places: \(mapFilteredPlaces.count)")
            print("   Places with location: \(placesWithLocation)")
            print("   Places without location: \(placesWithoutLocation)")
            
            // Update filteredPlaces for UI consistency (search, empty states, etc.)
            self.filteredPlaces = mapFilteredPlaces
            
            // Use progressive loading instead of waiting for everything
            self.updateMapProgressively(with: deduplicatedPlaces, isFromCache: false)
                
            // Hide loading state
            self.isLoadingPlaces = false
            self.isPerformingInitialLoad = false // Reset initial load flag
            self.hideLoadingState()
            
            // Mark that we've loaded data only if we actually have data
            if !self.circles.isEmpty || !allFetchedPlaces.isEmpty {
                CirclesHomeViewController.hasLoadedInitialData = true
            }
        })
    }
    
    // MARK: - Map Update Coordination
    
    private func updateMapWhenReady() {
        // Only update map if data is ready and we have places to display
        guard isMapDataReady else {
            print("🗺️ Map data not ready yet, deferring update")
            return
        }
        
        // Apply current filters to get the places to display
        let placesToDisplay = applyFiltersToPlaces(allPlaces)
        
        print("🗺️ Updating map with \(placesToDisplay.count) places (data ready)")
        
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
    
    private func updatePlaceCountLabel(count: Int) {
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
    
    private func setupNavigationBar() {
        // Create help button for left side
        let helpButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(helpButtonTapped)
        )
        navigationItem.leftBarButtonItem = helpButton
        
        // Create check-in button
        let checkInButton = UIBarButtonItem(
            image: UIImage(systemName: "checkmark.circle"),
            style: .plain,
            target: self,
            action: #selector(checkInButtonTapped)
        )
        
        // Create notification button with bell icon
        let notificationButton = UIBarButtonItem(
            image: UIImage(systemName: "bell"),
            style: .plain,
            target: self,
            action: #selector(notificationButtonTapped)
        )
        self.notificationBarButton = notificationButton
        
        // Create upgrade button for free users
        var rightBarButtons = [checkInButton, notificationButton]
        
        // Check if user is not subscribed
        Task { @MainActor in
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
            
            navigationItem.rightBarButtonItems = rightBarButtons
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
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
    
    @objc private func handleCircleDeleted(_ notification: Notification) {
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
    
    @objc private func handleRefreshCircles() {
        // Invalidate cache when circles/places are modified
        invalidateCache()
        // Refresh circles to get updated place counts
        refreshData()
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Check if cache is expired when app comes to foreground
        if !isCacheValid() {
            print("📱 App entering foreground - cache expired, will refresh on next load")
            // Don't refresh automatically, just invalidate cache
            // Data will be refreshed when view appears
        }
    }
    
    @objc private func handleMomentDeleted(_ notification: Notification) {
        guard let videoId = notification.userInfo?["videoId"] as? String else { return }
        
        print("📢 Received MomentDeleted notification for video: \(videoId)")
        
        // Find the indices of activities to remove
        var indexPathsToRemove: [IndexPath] = []
        var indicesToRemove: [Int] = []
        
        for (index, activity) in activities.enumerated() {
            if activity.targetType == "place_video" && activity.targetId == videoId {
                print("🗑️ Found activity to remove at index \(index) for video: \(videoId)")
                indexPathsToRemove.append(IndexPath(row: index, section: 0))
                indicesToRemove.append(index)
            }
        }
        
        // Remove from data source (in reverse order to maintain indices)
        for index in indicesToRemove.reversed() {
            activities.remove(at: index)
        }
        
        if !indexPathsToRemove.isEmpty {
            print("✅ Removing \(indexPathsToRemove.count) activity(ies) from feed")
            
            // Update UI if activity feed is visible
            if contentSegmentedControl.selectedSegmentIndex == 2 { // Activity tab
                // Use performBatchUpdates for proper animation and consistency
                activityTableView.performBatchUpdates({
                    activityTableView.deleteRows(at: indexPathsToRemove, with: .fade)
                }) { [weak self] _ in
                    // Update empty state after animation completes
                    self?.activityEmptyStateLabel.isHidden = !(self?.activities.isEmpty ?? true)
                }
            } else {
                // If not visible, just update the empty state
                activityEmptyStateLabel.isHidden = activities.isEmpty
            }
        }
    }
    
    @objc private func handleShowOnboardingTour(_ notification: Notification) {
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
    @objc private func addButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        // Present modally wrapped in navigation controller for cancel button
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }
    
    @objc private func upgradeButtonTapped() {
        SubscriptionManager.shared.showPaywall(from: self, reason: .generalUpgrade)
    }
    
    private func updateNavigationBarForSubscription() {
        Task { @MainActor in
            let checkInButton = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"), style: .plain, target: self, action: #selector(checkInButtonTapped))
            let notificationButton = self.notificationBarButton ?? UIBarButtonItem(image: UIImage(systemName: "bell"), style: .plain, target: self, action: #selector(notificationButtonTapped))
            
            var rightBarButtons = [checkInButton, notificationButton]
            
            // Check if user is not subscribed
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
            
            navigationItem.rightBarButtonItems = rightBarButtons
        }
    }
    
    
    
    @objc private func expandMapButtonTapped() {
        // Set flag to prevent map updates when returning
        isReturningFromFullScreenMap = true
        
        // If we have a connection filter but no network circles, fetch them first
        if let connectionId = selectedConnectionId, 
           connectionId != "my_places_only",
           networkCircles.isEmpty {
            print("📍 Fetching network circles before expanding map...")
            fetchNetworkCircles { [weak self] in
                guard let self = self else { return }
                self.presentFullScreenMapWithCurrentState()
            }
        } else {
            presentFullScreenMapWithCurrentState()
        }
    }
    
    private func presentFullScreenMapWithCurrentState() {
        // Present full screen map with current filter states
        let fullScreenMap = FullScreenMapViewController(
            places: allPlaces,
            initialRegion: nil,
            selectedCategory: selectedCategory,  // Pass current category filter
            selectedConnectionId: selectedConnectionId  // Pass current connection filter
        )
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.delegate = self  // Set delegate to handle place selection
        
        // Separate user places from connection places
        var userPlaces: [Place] = []
        var connectionPlacesMap: [String: [Place]] = [:]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let userCircleIds = Set(circles.map { $0.id })
        
        // Get connections from NetworkManager
        let connections = NetworkManager.shared.connections
        
        // Build a map of circle owner IDs to connection otherUserIds
        // This handles the ID normalization and connection data issues
        var ownerToConnectionId: [String: String] = [:]
        for connection in connections {
            let otherUserId = connection.otherUserId(currentUserId: currentUserId)
            // Try to find this connection's circles in networkCircles
            for circle in networkCircles {
                if IDNormalizer.isSameUser(circle.owner, otherUserId) {
                    ownerToConnectionId[circle.owner] = otherUserId
                }
            }
        }
        
        for place in allPlaces {
            // Check if this is a user's place
            if let circleId = place.circleId, userCircleIds.contains(circleId) {
                userPlaces.append(place)
            } else if let circleId = place.circleId, let circle = networkCircles.first(where: { $0.id == circleId }) {
                // Check if the circle owner is the current user (handles user circles in networkCircles)
                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                    userPlaces.append(place)
                } else {
                    // This is a connection's place
                    // Use the normalized connection ID as the key
                    let mapKey = ownerToConnectionId[circle.owner] ?? circle.owner
                    if connectionPlacesMap[mapKey] == nil {
                        connectionPlacesMap[mapKey] = []
                    }
                    connectionPlacesMap[mapKey]?.append(place)
                }
            }
        }
        
        // Debug connection data
        print("🔍 DEBUG: Checking connections before passing to full screen map")
        print("🔍 Connection places map keys: \(connectionPlacesMap.keys.sorted())")
        for (index, connection) in connections.enumerated() {
            let otherUserId = connection.otherUserId(currentUserId: currentUserId)
            let placeCount = connectionPlacesMap[otherUserId]?.count ?? 0
            print("  \(index): \(connection.connectedUser?.displayName ?? "Unknown") - \(placeCount) places")
            print("     - otherUserId: \(otherUserId)")
        }
        
        // Update the full screen map with connections data
        fullScreenMap.updatePlacesWithConnections(
            userPlaces,
            connections: connections,
            connectionPlaces: connectionPlacesMap
        )
        fullScreenMap.modalPresentationStyle = .fullScreen
        present(fullScreenMap, animated: true)
    }
    
    @objc private func quickAddPlaceButtonTapped() {
        // Debug: Log current circle state
        print("🔍 DEBUG quickAddPlaceButtonTapped - circles.count: \(circles.count)")
        print("🔍 DEBUG quickAddPlaceButtonTapped - circles.isEmpty: \(circles.isEmpty)")
        print("🔍 DEBUG quickAddPlaceButtonTapped - isLoadingCircles: \(isLoadingCircles)")
        print("🔍 DEBUG quickAddPlaceButtonTapped - hasLoadedInitialData: \(CirclesHomeViewController.hasLoadedInitialData)")
        if !circles.isEmpty {
            print("🔍 DEBUG quickAddPlaceButtonTapped - circles: \(circles.map { $0.name })")
        } else {
            print("🔍 DEBUG quickAddPlaceButtonTapped - No circles found! This is why picker isn't showing")
        }
        
        // If user has circles, show circle picker. Otherwise, prompt to create a circle
        if circles.isEmpty {
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
        } else if circles.count == 1 {
            // If only one circle, go directly to add place
            let addPlaceVC = AddPlaceViewController(circleId: circles[0].id)
            navigationController?.pushViewController(addPlaceVC, animated: true)
        } else {
            // Show circle picker
            showCirclePicker()
        }
    }
    
    private func showCirclePicker() {
        // Sort circles alphabetically for easy finding
        let sortedCircles = circles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        let circlePickerVC = CirclePickerViewController(circles: sortedCircles)
        circlePickerVC.onCircleSelected = { [weak self] circle in
            let addPlaceVC = AddPlaceViewController(circleId: circle.id)
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
    
    
    
    private func updateMapVisibility() {
        // Map is always visible, just ensure it's shown
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        updateMapPlaces()
    }
    
    private func deduplicatePlaces(userPlaces: [Place], networkPlaces: [Place]) -> [Place] {
        var seenPlaceIds = Set<String>()
        var deduplicatedPlaces: [Place] = []
        
        // First, add all user places (these take priority)
        for place in userPlaces {
            if !seenPlaceIds.contains(place.id) {
                seenPlaceIds.insert(place.id)
                deduplicatedPlaces.append(place)
            } else {
                print("🔍 Skipping duplicate user place: '\(place.name)' (ID: \(place.id))")
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
                print("🔍 Skipping duplicate network place: '\(place.name)' (ID: \(place.id)) - already exists in user places")
            }
        }
        
        if duplicatesFound > 0 {
            print("⚠️ Found and removed \(duplicatesFound) duplicate places from network data")
        }
        
        print("📍 Deduplication summary: \(userPlaces.count) user + \(networkPlaces.count) network = \(deduplicatedPlaces.count) unique places")
        return deduplicatedPlaces
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
                print("🔍 Skipping duplicate place: '\(place.name)' (ID: \(place.id)) - already exists")
            }
        }
        
        if duplicatesFound > 0 {
            print("⚠️ Found and removed \(duplicatesFound) duplicate places from fetched data")
        }
        
        print("📍 Deduplication summary: \(places.count) fetched places = \(deduplicatedPlaces.count) unique places")
        return deduplicatedPlaces
    }
    
    private func fetchNetworkPlacesAndCombineWithCached() {
        var networkPlaces: [Place] = []
        let group = DispatchGroup()
        
        // Fetch places from network circles
        for circle in networkCircles {
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                switch result {
                case .success(let places):
                    print("✅ Fetched \(places.count) network places from circle '\(circle.name)'")
                    networkPlaces.append(contentsOf: places)
                case .failure(let error):
                    print("❌ Error fetching network places from circle '\(circle.name)': \(error.localizedDescription)")
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
            print("📍 Combined places: \(self.cachedPlaces.count) cached user + \(networkPlaces.count) network = \(allPlaces.count) total (after deduplication)")
            print("📍 User's own places: \(self.userOwnPlaces.count)")
            
            self.allPlaces = allPlaces
            self.applyFiltersAndUpdateMap()
        }
    }
    
    private func applyFiltersAndUpdateMap() {
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
    
    private func applyFiltersToPlaces(_ places: [Place]) -> [Place] {
        print("📍 Connection filter - selectedConnectionId: \(self.selectedConnectionId ?? "nil")")
        
        // Apply connection filter if selected
        var mapFilteredPlaces = places
        
        if let connectionId = self.selectedConnectionId {
            if connectionId == "my_places_only" {
                // Show only places from user's own circles
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let userCircleIds = self.circles.map { $0.id }
                print("📍 FILTER: my_places_only selected")
                print("📍 Total places to filter: \(places.count)")
                print("📍 User has \(self.circles.count) circles")
                print("📍 Current user ID: \(currentUserId)")
                
                if userCircleIds.isEmpty && networkCircles.isEmpty {
                    print("⚠️ Warning: No circles loaded, showing empty results")
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
                                    print("📍 Found user place in network circle: '\(place.name)' from circle '\(circle.name)'")
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
                    print("📍 FILTER RESULT: Kept \(mapFilteredPlaces.count) places, excluded \(excludedCount) places")
                    print("📍 Found \(networkCircleUserPlaces) user places that were in network circles")
                    print("📍 User should have 124 places total according to user")
                }
            } else {
                // Show only places from the selected connection
                // Get all places from circles owned by this connection
                print("📍 FILTER: Specific connection selected: \(connectionId)")
                var connectionFilteredPlaces: [Place] = []
                var debugCircleOwners = Set<String>()
                
                for place in places {
                    // Find the circle this place belongs to
                    if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                        debugCircleOwners.insert(circle.owner)
                        // Use IDNormalizer to compare IDs properly
                        if IDNormalizer.isSameUser(circle.owner, connectionId) {
                            connectionFilteredPlaces.append(place)
                            print("   ✅ Found place '\(place.name)' from circle '\(circle.name)' owned by connection")
                        }
                    }
                }
                
                mapFilteredPlaces = connectionFilteredPlaces
                print("   Available circle owners: \(debugCircleOwners)")
                print("   Looking for connectionId: \(connectionId)")
                print("   Filtered to connection '\(connectionId)': \(mapFilteredPlaces.count) places")
            }
        } else {
            // "All Connections" selected - show all places (user's + connections')
            mapFilteredPlaces = places
            print("   Showing all connections' places: \(mapFilteredPlaces.count) places")
        }
        
        // Apply category filter
        if let category = self.selectedCategory {
            let beforeCategoryFilter = mapFilteredPlaces.count
            mapFilteredPlaces = mapFilteredPlaces.filter { place in
                let matches = category.matches(place: place)
                
                // Debug logging for filter matching
                if !matches {
                    print("   🚫 Place '\(place.name)' does not match filter '\(category.displayName)' - place category: \(place.category), customCategoryId: \(place.customCategoryId ?? "none")")
                }
                
                return matches
            }
            print("   Category filter '\(category.displayName)' applied: \(beforeCategoryFilter) → \(mapFilteredPlaces.count) places")
        }
        
        print("   Final places after filtering: \(mapFilteredPlaces.count)")
        return mapFilteredPlaces
    }
    
    
    private func updateMapPlaces() {
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
    private func refreshMapDisplay() {
        print("🗺️ [RefreshMapDisplay] Refreshing map with current filters")
        
        // Skip if we don't have data yet
        if allPlaces.isEmpty {
            print("🗺️ [RefreshMapDisplay] No places data available, skipping refresh")
            return
        }
        
        // Apply current filters to existing data
        let placesToDisplay = applyFiltersToPlaces(allPlaces)
        
        print("🗺️ [RefreshMapDisplay] Displaying \(placesToDisplay.count) filtered places (from \(allPlaces.count) total)")
        
        // Update the map immediately (no debouncing needed for filters)
        mapViewController?.updatePlaces(placesToDisplay)
        
        // Trigger map region adjustment to fit all filtered results (like full-screen map)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.mapViewController?.adjustMapRegion()
        }
        
        // Update place count label
        updatePlaceCountLabel(count: placesToDisplay.count)
    }
    
    
    @objc private func categoryFilterButtonTapped() {
        // Don't allow opening dropdown if no categories are available
        if availableCategories.isEmpty {
            print("🏷️ [Categories] No categories available, dropdown disabled")
            return
        }
        
        isCategoryDropdownOpen.toggle()
        
        if isCategoryDropdownOpen {
            // Close other dropdowns if open
            if isConnectionDropdownOpen {
                isConnectionDropdownOpen = false
                hideConnectionDropdown()
            }
            showCategoryDropdown()
        } else {
            hideCategoryDropdown()
        }
    }
    
    private func showCategoryDropdown() {
        // Calculate available categories from all places
        updateAvailableCategories()
        
        // Calculate dropdown height
        let numberOfRows = availableCategories.count + 1 // +1 for "All Categories"
        let maxHeight: CGFloat = 300
        let calculatedHeight = CGFloat(numberOfRows) * 44
        let dropdownHeight = min(calculatedHeight, maxHeight)
        
        categoryDropdownView.isHidden = false
        categoryDropdownHeightConstraint?.constant = dropdownHeight
        
        // Enable scrolling if content exceeds max height
        categoryDropdownTableView.isScrollEnabled = calculatedHeight > maxHeight
        
        // Reload table data
        categoryDropdownTableView.reloadData()
        
        // Animate dropdown appearance
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.categoryDropdownView.alpha = 1
            self.view.layoutIfNeeded()
            
            // Rotate arrow
            self.categoryFilterButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        // Bring dropdown to front
        view.bringSubviewToFront(categoryDropdownView)
    }
    
    private func hideCategoryDropdown() {
        UIView.animate(withDuration: 0.2, animations: {
            self.categoryDropdownView.alpha = 0
            self.categoryDropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
            
            // Rotate arrow back
            self.categoryFilterButton.imageView?.transform = .identity
        }) { _ in
            self.categoryDropdownView.isHidden = true
        }
    }
    
    private func updateAvailableCategories() {
        print("🏷️ [Categories] Updating available categories with connection filter: \(selectedConnectionId ?? "none")")
        print("🏷️ [Categories] Total allPlaces count: \(allPlaces.count)")
        
        // Apply connection filter first to get only visible places
        let visiblePlaces = applyConnectionFilterToPlaces(allPlaces)
        print("🏷️ [Categories] Visible places after connection filter: \(visiblePlaces.count)")
        
        // Get unique categories from visible places only
        var categoriesSet = Set<UnifiedCategory>()
        for place in visiblePlaces {
            let category = UnifiedCategory.from(place: place)
            categoriesSet.insert(category)
            
            // Debug logging for custom categories
            if case .custom(let customName) = category {
                print("🏷️ [Categories] Found custom category: '\(customName)' for place: \(place.name)")
            }
        }
        availableCategories = Array(categoriesSet).sorted { $0.displayName < $1.displayName }
        
        print("🏷️ [Categories] Available categories after connection filter (\(visiblePlaces.count) places): \(availableCategories.map { $0.displayName })")
        
        // Check if the currently selected category is still available
        if let selectedCategory = self.selectedCategory,
           !availableCategories.contains(selectedCategory) {
            print("🏷️ [Categories] Previously selected category '\(selectedCategory.displayName)' no longer available, clearing selection")
            self.selectedCategory = nil
        }
        
        // Update the category filter button title based on available categories
        updateCategoryFilterButtonTitle()
    }
    
    // Helper method to apply only connection filtering (without category filter)
    private func applyConnectionFilterToPlaces(_ places: [Place]) -> [Place] {
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
    
    private func updateCategoryFilterButtonTitle() {
        if availableCategories.isEmpty {
            categoryFilterButton.setTitle("No Categories", for: .normal)
            categoryFilterButton.isEnabled = false
            categoryFilterButton.alpha = 0.6
        } else {
            categoryFilterButton.setTitle(selectedCategory?.displayName ?? "All Categories", for: .normal)
            categoryFilterButton.isEnabled = true
            categoryFilterButton.alpha = 1.0
        }
    }
    
    private func updateCategoryDropdownHeight() {
        // Calculate dropdown height based on available categories
        let numberOfRows = availableCategories.count + 1 // +1 for "All Categories"
        let maxHeight: CGFloat = 300
        let calculatedHeight = CGFloat(numberOfRows) * 44
        let dropdownHeight = min(calculatedHeight, maxHeight)
        
        // Update height constraint if dropdown is visible
        if !categoryDropdownView.isHidden {
            categoryDropdownHeightConstraint?.constant = dropdownHeight
            categoryDropdownTableView.isScrollEnabled = calculatedHeight > maxHeight
            categoryDropdownTableView.reloadData()
            
            // Animate the height change
            UIView.animate(withDuration: 0.2) {
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc private func connectionFilterButtonTapped() {
        isConnectionDropdownOpen.toggle()
        
        if isConnectionDropdownOpen {
            // Close other dropdowns if open
            if isCategoryDropdownOpen {
                isCategoryDropdownOpen = false
                hideCategoryDropdown()
            }
            showConnectionDropdown()
        } else {
            hideConnectionDropdown()
        }
    }
    
    private func showConnectionDropdown() {
        // Get connections
        let connections = NetworkManager.shared.connections
        
        // Calculate dropdown height
        let numberOfRows = connections.count + 2 // +2 for "All Connections" and "My Places Only"
        let maxHeight: CGFloat = 300
        let calculatedHeight = CGFloat(numberOfRows) * 44
        let dropdownHeight = min(calculatedHeight, maxHeight)
        
        connectionDropdownView.isHidden = false
        connectionDropdownHeightConstraint?.constant = dropdownHeight
        
        // Enable scrolling if content exceeds max height
        connectionDropdownTableView.isScrollEnabled = calculatedHeight > maxHeight
        
        // Reload table data
        connectionDropdownTableView.reloadData()
        
        // Animate dropdown appearance
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.connectionDropdownView.alpha = 1
            self.view.layoutIfNeeded()
            
            // Rotate arrow
            self.connectionFilterButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        // Bring dropdown to front
        view.bringSubviewToFront(connectionDropdownView)
    }
    
    private func hideConnectionDropdown() {
        UIView.animate(withDuration: 0.2, animations: {
            self.connectionDropdownView.alpha = 0
            self.connectionDropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
            
            // Rotate arrow back
            self.connectionFilterButton.imageView?.transform = .identity
        }) { _ in
            self.connectionDropdownView.isHidden = true
        }
    }
    
    private func showSearchScopeDropdown() {
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
    
    private func hideSearchScopeDropdown() {
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
    
    @objc private func dismissDropdowns(_ gesture: UITapGestureRecognizer? = nil) {
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
        if isCategoryDropdownOpen {
            isCategoryDropdownOpen = false
            hideCategoryDropdown()
        }
        if isConnectionDropdownOpen {
            isConnectionDropdownOpen = false
            hideConnectionDropdown()
        }
        if isSearchScopeDropdownOpen {
            isSearchScopeDropdownOpen = false
            hideSearchScopeDropdown()
        }
    }
    
    @objc private func searchScopeButtonTapped() {
        isSearchScopeDropdownOpen.toggle()
        
        if isSearchScopeDropdownOpen {
            // Close other dropdowns if open
            if isCategoryDropdownOpen {
                isCategoryDropdownOpen = false
                hideCategoryDropdown()
            }
            if isConnectionDropdownOpen {
                isConnectionDropdownOpen = false
                hideConnectionDropdown()
            }
            showSearchScopeDropdown()
        } else {
            hideSearchScopeDropdown()
        }
    }
    
    @objc private func recordReelTapped() {
        let contentUploadVC = ContentUploadViewController()
        contentUploadVC.delegate = self
        let navController = UINavigationController(rootViewController: contentUploadVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc override func refreshData() {
        // Invalidate cache when user manually refreshes
        invalidateCache()
        
        print("🚀 Starting OPTIMIZED refresh")
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
                    print("❌ Failed to refresh network circles: \(error)")
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
                    print("❌ Failed to refresh user circles: \(error)")
                }
                refreshGroup.leave()
            }
        }
        
        refreshGroup.notify(queue: .main) { [weak self] in
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ OPTIMIZED refresh completed in \(String(format: "%.2f", totalTime)) seconds")
        }
    }
    
    @objc private func homeButtonTapped() {
        handleQuickAccessTapped(type: .home)
    }
    
    @objc private func workButtonTapped() {
        handleQuickAccessTapped(type: .work)
    }
    
    @objc private func homeNavigateButtonTapped() {
        navigateToQuickAccess(type: .home)
    }
    
    @objc private func workNavigateButtonTapped() {
        navigateToQuickAccess(type: .work)
    }
    
    @objc private func quickAccessButtonTapped() {
        handleQuickAccessPlacesTapped()
    }
    
    @objc private func quickAccessNavigateButtonTapped() {
        navigateToQuickAccessPlaces()
    }
    
    @objc private func checkInButtonTapped() {
        let checkInVC = CheckInViewController()
        let navController = UINavigationController(rootViewController: checkInVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func helpButtonTapped() {
        let helpVC = HelpViewController()
        let navController = UINavigationController(rootViewController: helpVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func notificationButtonTapped() {
        let notificationsVC = NotificationsViewController()
        navigationController?.pushViewController(notificationsVC, animated: true)
    }
    
    private func setupNotificationBadge() {
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
    
    private func updateNotificationBadge() {
        print("🔔 [updateNotificationBadge] Starting badge update...")
        print("🔔 [updateNotificationBadge] Badge label exists: \(notificationBadgeLabel != nil)")
        print("🔔 [updateNotificationBadge] Notification button exists: \(notificationBarButton != nil)")
        
        // Always ensure badge is set up first
        if notificationBadgeLabel == nil {
            print("🔔 [updateNotificationBadge] Badge label is nil, setting up badge")
            setupNotificationBadge()
        }
        
        NotificationService.shared.getUnreadNotificationCount { [weak self] result in
            guard let self = self else { 
                print("🔔 [updateNotificationBadge] Self is nil, aborting")
                return 
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let count):
                    print("🔔 [updateNotificationBadge] Got unread count: \(count)")
                    if count > 0 {
                        self.notificationBadgeLabel?.text = count > 99 ? "99+" : "\(count)"
                        self.notificationBadgeLabel?.isHidden = false
                        print("🔔 [updateNotificationBadge] Badge shown with count: \(count)")
                        
                        // Adjust width constraint if needed
                        if count > 9 {
                            self.notificationBadgeLabel?.constraints.forEach { constraint in
                                if constraint.firstAttribute == .width {
                                    constraint.constant = 20
                                }
                            }
                        }
                    } else {
                        print("🔔 [updateNotificationBadge] No unread notifications, hiding badge")
                        self.notificationBadgeLabel?.isHidden = true
                    }
                case .failure(let error):
                    print("❌ [updateNotificationBadge] Failed to get unread count: \(error)")
                    self.notificationBadgeLabel?.isHidden = true
                }
            }
        }
    }
    
    private func navigateToQuickAccess(type: QuickAccessType) {
        let key = type == .home ? "userHomeAddress" : "userWorkAddress"
        let savedAddress = UserDefaults.standard.string(forKey: key)
        
        if let address = savedAddress, !address.isEmpty {
            // Create the same place object that would be created for viewing
            // This ensures we use the same geocoded location
            navigateToQuickAccessPlace(type: type, address: address, directNavigation: true)
        } else {
            // Show setup prompt
            let alert = UIAlertController(
                title: "Set \(type.rawValue) Address",
                message: "You need to set your \(type.rawValue.lowercased()) address first.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Set Address", style: .default) { [weak self] _ in
                self?.showAddressEntry(for: type)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }
    
    private func handleQuickAccessTapped(type: QuickAccessType) {
        // Check if address is already saved
        let key = type == .home ? "userHomeAddress" : "userWorkAddress"
        let savedAddress = UserDefaults.standard.string(forKey: key)
        
        if let address = savedAddress, !address.isEmpty {
            // Create a place from saved address and navigate to detail view
            navigateToQuickAccessPlace(type: type, address: address)
        } else {
            // Show address entry
            showAddressEntry(for: type)
        }
    }
    
    private func showAddressEntry(for type: QuickAccessType) {
        let alert = UIAlertController(
            title: "Set \(type.rawValue) Address",
            message: "Enter your \(type.rawValue.lowercased()) address",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "123 Main St, City, State"
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let address = alert.textFields?.first?.text, !address.isEmpty {
                // Save address
                let key = type == .home ? "userHomeAddress" : "userWorkAddress"
                UserDefaults.standard.set(address, forKey: key)
                
                // Navigate to place detail
                self?.navigateToQuickAccessPlace(type: type, address: address)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func navigateToQuickAccessPlace(type: QuickAccessType, address: String, directNavigation: Bool = false) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading", message: "Finding location...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Geocode the address to get coordinates
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            guard let self = self else { return }
            loadingAlert.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                
                var location: GeoLocation? = nil
                if let placemark = placemarks?.first,
                   let clLocation = placemark.location {
                    // Convert to GeoLocation format (MongoDB uses [longitude, latitude])
                    location = GeoLocation(type: "Point", coordinates: [clLocation.coordinate.longitude, clLocation.coordinate.latitude])
                }
                
                if directNavigation {
                    // Navigate directly using the geocoded location
                    if let location = location?.clLocation {
                        // Try Google Maps first
                        let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
                        
                        if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else {
                            // Fallback to Apple Maps
                            let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                            if let url = appleMapsURL {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        let alert = UIAlertController(title: "Navigation Error", message: "Could not find location for this address.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                } else {
                    // Show home/work address details
                    self.showAddressDetails(type: type, address: address, location: location)
                }
            }
        }
    }
    
    private func showAddressDetails(type: QuickAccessType, address: String, location: GeoLocation?) {
        let detailVC = UIViewController()
        detailVC.view.backgroundColor = .systemBackground
        detailVC.title = type.rawValue
        
        // Create content stack view
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Address section
        let addressContainer = UIView()
        addressContainer.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        addressContainer.layer.cornerRadius = 12
        
        let addressLabel = UILabel()
        addressLabel.text = "Address"
        addressLabel.font = .systemFont(ofSize: 14, weight: .medium)
        addressLabel.textColor = .secondaryLabel
        
        let addressValueLabel = UILabel()
        addressValueLabel.text = address
        addressValueLabel.font = .systemFont(ofSize: 16)
        addressValueLabel.numberOfLines = 0
        
        let addressStack = UIStackView(arrangedSubviews: [addressLabel, addressValueLabel])
        addressStack.axis = .vertical
        addressStack.spacing = 4
        addressStack.translatesAutoresizingMaskIntoConstraints = false
        
        addressContainer.addSubview(addressStack)
        NSLayoutConstraint.activate([
            addressStack.topAnchor.constraint(equalTo: addressContainer.topAnchor, constant: 16),
            addressStack.leadingAnchor.constraint(equalTo: addressContainer.leadingAnchor, constant: 16),
            addressStack.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -16),
            addressStack.bottomAnchor.constraint(equalTo: addressContainer.bottomAnchor, constant: -16)
        ])
        
        stackView.addArrangedSubview(addressContainer)
        
        // Navigate button
        let navigateButton = UIButton(type: .system)
        navigateButton.setTitle("Navigate", for: .normal)
        navigateButton.setImage(UIImage(systemName: "location.arrow"), for: .normal)
        navigateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        navigateButton.backgroundColor = Constants.Colors.primary
        navigateButton.setTitleColor(.white, for: .normal)
        navigateButton.tintColor = .white
        navigateButton.layer.cornerRadius = 12
        navigateButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        navigateButton.addAction(UIAction { [weak self] _ in
            if let location = location?.clLocation {
                // Try Google Maps first
                let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
                
                if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                } else {
                    // Fallback to Apple Maps
                    let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                    if let url = appleMapsURL {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }, for: .touchUpInside)
        
        stackView.addArrangedSubview(navigateButton)
        
        // Edit button
        let editButton = UIButton(type: .system)
        editButton.setTitle("Edit Address", for: .normal)
        editButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        editButton.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.2)
        editButton.layer.cornerRadius = 12
        editButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        editButton.addAction(UIAction { [weak self] _ in
            self?.setupQuickAccess(forType: type)
        }, for: .touchUpInside)
        
        stackView.addArrangedSubview(editButton)
        
        detailVC.view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: detailVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: detailVC.view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: detailVC.view.trailingAnchor, constant: -20)
        ])
        
        self.navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private enum QuickAccessType: String {
        case home = "Home"
        case work = "Work"
    }
    
    private func setupQuickAccess(forType type: QuickAccessType) {
        let alert = UIAlertController(title: "Set \(type.rawValue) Address", message: "Enter your \(type.rawValue.lowercased()) address", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter address"
            textField.autocapitalizationType = .words
            textField.returnKeyType = .done
            
            // Load existing address if available
            let key = type == .home ? "userHomeAddress" : "userWorkAddress"
            if let existingAddress = UserDefaults.standard.string(forKey: key) {
                textField.text = existingAddress
            }
        }
        
        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let address = alert.textFields?.first?.text, !address.isEmpty else { return }
            
            // Save to UserDefaults
            let key = type == .home ? "userHomeAddress" : "userWorkAddress"
            UserDefaults.standard.set(address, forKey: key)
            
            // Geocode the address
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(address) { placemarks, error in
                if let placemark = placemarks?.first, let location = placemark.location {
                    // Save location
                    let locationKey = type == .home ? "userHomeLocation" : "userWorkLocation"
                    let locationData = [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude
                    ]
                    UserDefaults.standard.set(locationData, forKey: locationKey)
                    
                    // Update UI
                    DispatchQueue.main.async { [weak self] in
                        self?.setupQuickAccessButtons()
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(saveAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    // MARK: - Quick Access Places
    
    private func handleQuickAccessPlacesTapped() {
        let savedPlaces = getQuickAccessPlaces()
        
        if savedPlaces.isEmpty {
            // Show place selection if no places saved
            showQuickAccessPlaceSelection()
        } else {
            // Show menu with saved places
            showQuickAccessMenu()
        }
    }
    
    private func navigateToQuickAccessPlaces() {
        let savedPlaces = getQuickAccessPlaces()
        
        if savedPlaces.isEmpty {
            showError("No quick access places saved. Tap the button to add places.")
            return
        }
        
        if savedPlaces.count == 1 {
            // Navigate directly to the single place
            navigateToQuickAccessPlace(savedPlaces[0])
        } else {
            // Show action sheet to select which place
            let actionSheet = UIAlertController(title: "Navigate to", message: nil, preferredStyle: .actionSheet)
            
            for place in savedPlaces {
                actionSheet.addAction(UIAlertAction(title: place["name"] as? String ?? "Unknown", style: .default) { [weak self] _ in
                    self?.navigateToQuickAccessPlace(place)
                })
            }
            
            actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            // iPad support
            if let popover = actionSheet.popoverPresentationController {
                popover.sourceView = quickAccessNavigateButton
                popover.sourceRect = quickAccessNavigateButton.bounds
            }
            
            present(actionSheet, animated: true)
        }
    }
    
    private func navigateToQuickAccessPlace(_ placeData: [String: Any]) {
        guard let latitude = placeData["latitude"] as? Double,
              let longitude = placeData["longitude"] as? Double,
              let name = placeData["name"] as? String else {
            showError("Invalid place data")
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        
        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving as NSString
        ]
        
        mapItem.openInMaps(launchOptions: launchOptions)
    }
    
    private func showQuickAccessMenu() {
        let savedPlaces = getQuickAccessPlaces()
        let actionSheet = UIAlertController(title: "Quick Access Places", message: nil, preferredStyle: .actionSheet)
        
        // Show saved places
        for place in savedPlaces {
            if let name = place["name"] as? String {
                actionSheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                    self?.navigateToQuickAccessPlace(place)
                })
            }
        }
        
        // Add manage option
        actionSheet.addAction(UIAlertAction(title: "Manage Places", style: .default) { [weak self] _ in
            self?.showQuickAccessPlaceSelection()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad support
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = quickAccessButton
            popover.sourceRect = quickAccessButton.bounds
        }
        
        present(actionSheet, animated: true)
    }
    
    private func showQuickAccessPlaceSelection() {
        // Get current user ID
        guard let currentUserId = AuthService.shared.getUserId() else {
            showError("Unable to determine current user")
            return
        }
        
        // Filter to only show the current user's places (not network places)
        let userPlaces = self.allPlaces.filter { place in
            place.addedBy == currentUserId
        }
        
        // Ensure we have user places before showing the selection
        guard !userPlaces.isEmpty else {
            showError("No places found. Add some places to your circles first.")
            return
        }
        
        // Log for debugging
        print("📍 QuickAccessPlaces: Passing \(userPlaces.count) user places (out of \(self.allPlaces.count) total)")
        
        let quickAccessVC = QuickAccessPlacesViewController()
        quickAccessVC.allPlaces = userPlaces
        quickAccessVC.delegate = self
        let navController = UINavigationController(rootViewController: quickAccessVC)
        present(navController, animated: true)
    }
    
    private func getQuickAccessPlaces() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: "userQuickAccessPlaces") as? [[String: Any]] ?? []
    }
    
    private func saveQuickAccessPlaces(_ places: [[String: Any]]) {
        UserDefaults.standard.set(places, forKey: "userQuickAccessPlaces")
        updateQuickAccessButtonTitle()
    }
    
    private func updateQuickAccessButtonTitle() {
        var config = quickAccessButton.configuration ?? UIButton.Configuration.filled()
        config.title = "Quick"
        quickAccessButton.configuration = config
    }
    
    
    // MARK: - Circle Management
    private func editCircle(at indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    private func deleteCircle(at indexPath: IndexPath) {
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
    
    private func performDelete(circle: Circle, at indexPath: IndexPath) {
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
    
    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Dropdown TableView Delegate & DataSource
extension CirclesHomeViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == categoryDropdownTableView {
            // Always show at least "All Categories", even if no specific categories available
            return max(1, availableCategories.count + 1) // +1 for "All Categories"
        } else if tableView == connectionDropdownTableView {
            return NetworkManager.shared.connections.count + 2 // +2 for "All Connections" and "My Places Only"
        } else if tableView == searchScopeTableView {
            return SearchScope.allCases.count
        } else if tableView == searchResultsTableView {
            return numberOfRowsInSearchResults()
        } else if tableView == activityTableView {
            return activities.count
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == categoryDropdownTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryDropdownCell") ?? UITableViewCell(style: .default, reuseIdentifier: "CategoryDropdownCell")
            
            cell.backgroundColor = .clear
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            cell.selectionStyle = .default
            
            // Set selection background color
            let selectedView = UIView()
            selectedView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            cell.selectedBackgroundView = selectedView
            
            if indexPath.row == 0 {
                if availableCategories.isEmpty {
                    // No categories available, only show "All Categories"
                    cell.textLabel?.text = "All Categories (No filtered categories available)"
                    cell.textLabel?.textColor = Constants.Colors.label
                    cell.accessoryType = .checkmark
                    cell.selectionStyle = .none // Disable selection since it's the only option
                } else {
                    // Normal "All Categories" option
                    cell.textLabel?.text = "All Categories"
                    cell.textLabel?.textColor = selectedCategory == nil ? Constants.Colors.primary : Constants.Colors.label
                    cell.accessoryType = selectedCategory == nil ? .checkmark : .none
                }
            } else {
                // Add bounds check
                let categoryIndex = indexPath.row - 1
                guard categoryIndex < availableCategories.count else {
                    return cell
                }
                let category = availableCategories[categoryIndex]
                cell.textLabel?.text = category.displayName
                cell.textLabel?.textColor = selectedCategory == category ? Constants.Colors.primary : Constants.Colors.label
                cell.accessoryType = selectedCategory == category ? .checkmark : .none
            }
            
            return cell
        } else if tableView == connectionDropdownTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ConnectionDropdownCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ConnectionDropdownCell")
            
            cell.backgroundColor = .clear
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            cell.selectionStyle = .default
            
            // Set selection background color
            let selectedView = UIView()
            selectedView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            cell.selectedBackgroundView = selectedView
            
            if indexPath.row == 0 {
                cell.textLabel?.text = "All Connections"
                cell.textLabel?.textColor = selectedConnectionId == nil ? Constants.Colors.primary : Constants.Colors.label
                cell.accessoryType = selectedConnectionId == nil ? .checkmark : .none
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "My Places Only"
                cell.textLabel?.textColor = selectedConnectionId == "my_places_only" ? Constants.Colors.primary : Constants.Colors.label
                cell.accessoryType = selectedConnectionId == "my_places_only" ? .checkmark : .none
            } else {
                // Add bounds check
                let connectionIndex = indexPath.row - 2
                guard connectionIndex < NetworkManager.shared.connections.count else {
                    return cell
                }
                let connection = NetworkManager.shared.connections[connectionIndex]
                let userName = connection.connectedUser?.displayName ?? "Unknown"
                cell.textLabel?.text = userName
                // Compare with the other user's ID
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let otherUserId = connection.otherUserId(currentUserId: currentUserId)
                cell.textLabel?.textColor = selectedConnectionId == otherUserId ? Constants.Colors.primary : Constants.Colors.label
                cell.accessoryType = selectedConnectionId == otherUserId ? .checkmark : .none
            }
            
            return cell
        } else if tableView == searchScopeTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchScopeCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SearchScopeCell")
            
            cell.backgroundColor = .clear
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            cell.selectionStyle = .default
            
            // Set selection background color
            let selectedView = UIView()
            selectedView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            cell.selectedBackgroundView = selectedView
            
            // Add bounds check
            guard indexPath.row < SearchScope.allCases.count else {
                return cell
            }
            
            let scope = SearchScope.allCases[indexPath.row]
            cell.textLabel?.text = scope.title
            cell.textLabel?.textColor = currentSearchScope == scope ? Constants.Colors.primary : Constants.Colors.label
            cell.accessoryType = currentSearchScope == scope ? .checkmark : .none
            
            return cell
        } else if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            
            // Add bounds check
            guard indexPath.row < filteredPlaces.count else {
                return cell
            }
            
            let place = filteredPlaces[indexPath.row]
            
            var content = cell.defaultContentConfiguration()
            content.text = place.name
            
            // Show creator name and circle info
            var subtitle = ""
            
            // Check if it's the current user first
            let currentUserId = AuthService.shared.getUserId() ?? ""
            if place.addedBy == currentUserId {
                subtitle = "Added by you"
            } else {
                // Try to find the connection name from network circles
                var connectionName: String? = nil
                
                // Look through network circles to find the owner
                for networkCircle in networkCircles {
                    if let circleId = place.circleId, networkCircle.id == circleId {
                        // Found the circle, get the owner's name
                        if let ownerDetails = networkCircle.ownerDetails {
                            connectionName = ownerDetails.displayName
                        } else {
                            // Try to find from connections list
                            if let connection = NetworkManager.shared.connections.first(where: { $0.connectedUserId == networkCircle.owner }) {
                                connectionName = connection.connectedUser?.displayName
                            }
                        }
                        break
                    }
                }
                
                if let name = connectionName {
                    subtitle = "Added by \(name)"
                } else {
                    subtitle = "Added by a connection"
                }
            }
            
            // Add circle name
            if let circle = circles.first(where: { $0.id == place.circleId }) {
                subtitle += " • \(circle.name)"
            } else if let networkCircle = networkCircles.first(where: { $0.id == place.circleId }) {
                subtitle += " • \(networkCircle.name)"
            }
            
            content.secondaryText = subtitle
            content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
            
            // Add category icon
            let iconName: String
            switch place.category {
            case .restaurant, .cafe, .bar: iconName = "fork.knife"
            case .hotel: iconName = "bed.double"
            case .retail: iconName = "bag"
            case .service: iconName = "wrench.and.screwdriver"
            case .attraction: iconName = "star"
            case .entertainment: iconName = "tv"
            case .healthcare: iconName = "heart"
            case .fitness: iconName = "figure.walk"
            case .education: iconName = "graduationcap"
            case .outdoor: iconName = "tree"
            case .transport: iconName = "car"
            case .finance: iconName = "dollarsign.circle"
            case .home: iconName = "house"
            case .work: iconName = "building.2"
            case .other: iconName = "circle.grid.3x3"
            }
            content.image = UIImage(systemName: iconName)
            content.imageProperties.tintColor = Constants.Colors.primary
            
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            
            return cell
        } else if tableView == activityTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: ActivityFeedCell.identifier, for: indexPath) as! ActivityFeedCell
            
            // Add bounds check
            guard indexPath.row < activities.count else {
                return cell
            }
            
            let activity = activities[indexPath.row]
            cell.delegate = self
            cell.configure(with: activity)
            return cell
        }
        
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Use automatic dimensions for all table views to avoid constraint conflicts
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == categoryDropdownTableView {
            // Don't allow selection if no categories are available
            if availableCategories.isEmpty && indexPath.row == 0 {
                // Only "All Categories" is available and it's already selected, do nothing
                hideCategoryDropdown()
                isCategoryDropdownOpen = false
                return
            }
            
            if indexPath.row == 0 {
                // All Categories selected
                selectedCategory = nil
                categoryFilterButton.setTitle("All Categories", for: .normal)
            } else {
                // Specific category selected
                let categoryIndex = indexPath.row - 1
                guard categoryIndex < availableCategories.count else { return }
                selectedCategory = availableCategories[categoryIndex]
                categoryFilterButton.setTitle(selectedCategory?.displayName ?? "All Categories", for: .normal)
            }
            
            // Update UI and hide dropdown
            print("📍 Category filter changed to: \(selectedCategory?.displayName ?? "All Categories")")
            refreshMapDisplay()
            hideCategoryDropdown()
            isCategoryDropdownOpen = false
            
        } else if tableView == connectionDropdownTableView {
            if indexPath.row == 0 {
                // All Connections selected
                selectedConnectionId = nil
                connectionFilterButton.setTitle("All Connections", for: .normal)
            } else if indexPath.row == 1 {
                // My Places Only selected
                selectedConnectionId = "my_places_only"
                connectionFilterButton.setTitle("My Places Only", for: .normal)
            } else {
                // Specific connection selected
                let connectionIndex = indexPath.row - 2
                guard connectionIndex < NetworkManager.shared.connections.count else { return }
                let connection = NetworkManager.shared.connections[connectionIndex]
                // Use the other user's ID (not the current user's ID)
                let currentUserId = AuthService.shared.getUserId() ?? ""
                selectedConnectionId = connection.otherUserId(currentUserId: currentUserId)
                let userName = connection.connectedUser?.displayName ?? "Unknown"
                connectionFilterButton.setTitle(userName, for: .normal)
                
                // Debug logging
                print("📍 CONNECTION SELECTED:")
                print("   Connection ID: \(connection.id)")
                print("   Connection userId: \(connection.userId)")
                print("   Connection connectedUserId: \(connection.connectedUserId)")
                print("   Current user ID: \(currentUserId)")
                print("   Selected connection ID (otherUserId): \(selectedConnectionId ?? "nil")")
                print("   Connected user name: \(userName)")
                print("   Connected user ID from object: \(connection.connectedUser?.id ?? "nil")")
            }
            
            // Update UI and hide dropdown
            print("📍 Connection filter changed to: \(selectedConnectionId ?? "All Connections")")
            
            // Update available categories based on new connection filter
            updateAvailableCategories()
            
            // Refresh category dropdown height in case number of categories changed
            updateCategoryDropdownHeight()
            
            // If a specific connection is selected and we don't have network circles, fetch them
            if selectedConnectionId != nil && selectedConnectionId != "my_places_only" && networkCircles.isEmpty {
                print("📍 Need to fetch network circles for connection filtering")
                fetchNetworkCircles { [weak self] in
                    // After fetching new network data, update categories again and refresh map
                    self?.updateAvailableCategories()
                    self?.updateMapPlaces()
                }
            } else {
                // We have all the data needed, just refresh the display with current filters
                refreshMapDisplay()
            }
            hideConnectionDropdown()
            isConnectionDropdownOpen = false
        } else if tableView == searchScopeTableView {
            // Add bounds check
            guard indexPath.row < SearchScope.allCases.count else { return }
            
            let selectedScope = SearchScope.allCases[indexPath.row]
            currentSearchScope = selectedScope
            
            // Update search bar placeholder
            searchBar.placeholder = selectedScope.placeholder
            
            // If currently searching, refresh the search results with new scope
            if isSearching {
                filterPlaces(searchText: searchBar.text ?? "")
            }
            
            // Load network places if switching to network search and not already loaded
            if selectedScope == .networkPlaces && networkPlaces.isEmpty && !isLoadingNetworkPlaces {
                loadNetworkPlaces()
            }
            
            // Update UI and hide dropdown
            hideSearchScopeDropdown()
            isSearchScopeDropdownOpen = false
        } else if tableView == searchResultsTableView {
            // Add bounds check
            guard indexPath.row < filteredPlaces.count else { return }
            handleSearchResultSelection(at: indexPath)
        } else if tableView == activityTableView {
            // Add bounds check
            guard indexPath.row < activities.count else { return }
            let activity = activities[indexPath.row]
            
            // Navigate based on activity type
            switch activity.type {
            case .placeAdded, .placeLiked, .placeCommented, .commentLiked, .photoUploaded:
                // Navigate to the place
                navigateToPlace(withId: activity.targetId)
            case .circleCreated:
                // Navigate to the circle
                navigateToCircle(withId: activity.targetId)
            case .checkIn:
                // Navigate to the check-in place
                navigateToCheckInPlace(activity: activity)
            case .videoUploaded:
                // Navigate to the video (targetId is the video ID for video activities)
                navigateToVideo(withId: activity.targetId)
            }
        }
    }
}

// MARK: - CreateCircleDelegate
extension CirclesHomeViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        print("✅ Circle created successfully: \(circle.name)")
        
        // Add the new circle to our local array at the beginning
        circles.insert(circle, at: 0)
        updateEmptyState()
        updateMapPlaces()
        
        // Dismiss the modal CreateCircleViewController first
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            // After dismissal, navigate to AddPlaceViewController with the new circle
            let addPlaceVC = AddPlaceViewController(circleId: circle.id)
            self.navigationController?.pushViewController(addPlaceVC, animated: true)
        }
    }
}

// MARK: - EditCircleDelegate
extension CirclesHomeViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        // Find and update the circle in the array
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            updateMapPlaces()
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        // Find and remove the circle from the array
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            updateEmptyState()
            updateMapPlaces()
        }
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension CirclesHomeViewController: FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        let timestamp = Date().timeIntervalSince1970
        print("🎯 [DEBUG-\(timestamp)] CirclesHomeViewController.mapViewController called for place: \(place.name)")
        print("🗺️ [DEBUG-\(timestamp)] Controller isPresentedModally: \(controller.isPresentedModally)")
        
        // Deduplication check to prevent double presentation
        let timeSinceLastPresentation = timestamp - lastPresentationTime
        if lastPresentedPlaceId == place.id && timeSinceLastPresentation < presentationDebounceInterval {
            print("🚫 [DEBUG-\(timestamp)] Duplicate presentation blocked - same place (\(place.name)) presented \(timeSinceLastPresentation) seconds ago")
            return
        }
        
        // Update deduplication tracking
        lastPresentedPlaceId = place.id
        lastPresentationTime = timestamp
        
        // First check user's own circles
        if let circle = circles.first(where: { $0.places?.contains(place.id) == true }) {
            print("✅ [DEBUG-\(timestamp)] Found place in user circle: \(circle.name)")
            let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
            print("📱 [DEBUG-\(timestamp)] Created PlaceDetailViewController - presenting...")
            presentPlaceDetail(placeDetailVC, from: controller)
        } 
        // Then check network circles
        else if let networkCircle = networkCircles.first(where: { $0.places?.contains(place.id) == true }) {
            print("✅ [DEBUG-\(timestamp)] Found place in network circle: \(networkCircle.name)")
            let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
            print("📱 [DEBUG-\(timestamp)] Created PlaceDetailViewController - presenting...")
            presentPlaceDetail(placeDetailVC, from: controller)
        } else {
            print("⚠️ [DEBUG-\(timestamp)] Place not found in any circle")
        }
    }
    
    private func presentPlaceDetail(_ placeDetailVC: PlaceDetailViewController, from controller: FullScreenMapViewController) {
        let timestamp = Date().timeIntervalSince1970
        print("🎭 [DEBUG-\(timestamp)] presentPlaceDetail called")
        print("🗺️ [DEBUG-\(timestamp)] Controller isPresentedModally: \(controller.isPresentedModally)")
        
        // Check if the map controller is presented modally
        if controller.isPresentedModally {
            print("📄 [DEBUG-\(timestamp)] Presenting PlaceDetail modally on full-screen map")
            // Present place detail modally on top of the full screen map
            let navController = UINavigationController(rootViewController: placeDetailVC)
            navController.modalPresentationStyle = .pageSheet
            controller.present(navController, animated: true)
        } else {
            print("📱 [DEBUG-\(timestamp)] Pushing PlaceDetail via navigation for embedded map")
            // For embedded map, use regular navigation push
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
        print("🎭 [DEBUG-\(timestamp)] presentPlaceDetail completed")
    }
}


// MARK: - UISearchBarDelegate
extension CirclesHomeViewController: UISearchBarDelegate {
    // Override to add updateEmptyState call
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBar(searchBar, textDidChange: searchText)
        // Update empty state after search
        updateEmptyState()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Dismiss the keyboard when "Done" is tapped
        searchBar.resignFirstResponder()
        // Update empty state if needed
        updateEmptyState()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarCancelButtonClicked(searchBar)
        // Update empty state after clearing search
        updateEmptyState()
    }
}

// MARK: - Custom Search Implementation
extension CirclesHomeViewController {
    // Override the default filterPlaces to support search scope
    func filterPlaces(searchText: String) {
        let searchSource: [Place]
        
        switch currentSearchScope {
        case .myPlaces:
            searchSource = userOwnPlaces // Use only user's own places
        case .networkPlaces:
            // Combine user's places with network places, removing duplicates
            searchSource = deduplicatePlaces(userPlaces: userOwnPlaces, networkPlaces: networkPlaces)
        }
        
        filteredPlaces = searchSource.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.address.localizedCaseInsensitiveContains(searchText) ||
            (place.description ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.notes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.publicNotes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.privateNotes ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Load network places for search
    func loadNetworkPlaces() {
        guard !isLoadingNetworkPlaces else { return }
        
        isLoadingNetworkPlaces = true
        print("🔍 Loading network places for search...")
        
        let group = DispatchGroup()
        var allNetworkPlaces: [Place] = []
        
        // If we don't have network circles, fetch them first
        if networkCircles.isEmpty {
            group.enter()
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.networkCircles = response.data
                    // Now fetch places from network circles
                    for circle in response.data {
                        group.enter()
                        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                            switch result {
                            case .success(let places):
                                allNetworkPlaces.append(contentsOf: places)
                            case .failure(let error):
                                print("Failed to fetch places for network circle \(circle.id): \(error)")
                            }
                            group.leave()
                        }
                    }
                case .failure(let error):
                    print("Failed to fetch network circles: \(error)")
                }
                group.leave()
            }
        } else {
            // Use existing network circles
            for circle in networkCircles {
                group.enter()
                PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                    switch result {
                    case .success(let places):
                        allNetworkPlaces.append(contentsOf: places)
                    case .failure(let error):
                        print("Failed to fetch places for network circle \(circle.id): \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoadingNetworkPlaces = false
            
            // Deduplicate network places before storing
            let deduplicatedNetworkPlaces = self.removeDuplicatePlaces(allNetworkPlaces)
            self.networkPlaces = deduplicatedNetworkPlaces
            print("🔍 Loaded \(allNetworkPlaces.count) raw network places, deduplicated to \(deduplicatedNetworkPlaces.count) unique places for search")
            
            // If currently searching in network scope, refresh results
            if self.currentSearchScope == .networkPlaces && self.isSearching == true {
                self.filterPlaces(searchText: self.searchBar.text ?? "")
                if !self.filteredPlaces.isEmpty {
                    self.showSearchResults()
                } else {
                    self.hideSearchResults()
                }
                self.updateEmptyState()
            }
        }
    }
}

// MARK: - PlaceSearchable Navigation
extension CirclesHomeViewController {
    func navigateToPlace(_ place: Place) {
        // Find the circle this place belongs to
        var targetCircle: Circle?
        
        // Check user's circles first
        if let circleId = place.circleId, let circle = circles.first(where: { $0.id == circleId }) {
            targetCircle = circle
        }
        
        // Check network circles if not found
        if targetCircle == nil {
            if let circleId = place.circleId {
                targetCircle = networkCircles.first(where: { $0.id == circleId })
            }
        }
        
        guard let circle = targetCircle else {
            print("⚠️ Could not find circle for place: \(place.name)")
            return
        }
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}

// MARK: - HorizontalUserListViewDelegate
extension CirclesHomeViewController: HorizontalUserListViewDelegate {
    func didSelectUser(_ user: User, connectionId: String) {
        // Navigate to user's profile
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - Daily Summary Methods
extension CirclesHomeViewController {
    func showDailySummaryIfAvailable() {
        // This is for showing stored summaries (if any) in the card view
        // Only used for persistent display, not for notification taps
        checkForDailySummary()
    }
    
    // Called when notification is tapped - fetch fresh data and show modal
    func fetchAndShowDailySummary() {
        // Always present the modal DailySummaryViewController
        // It will fetch its own data from the API
        let summaryVC = DailySummaryViewController()
        present(summaryVC, animated: true, completion: nil)
    }
    
    private func checkForDailySummary() {
        // Remove any existing card since we're not using this feature anymore
        // Daily summaries should be shown as modals when notification is tapped
        removeDailySummaryCard()
        
        // Clear any old stored data
        if let latestKey = UserDefaults.standard.string(forKey: "latestDailySummaryKey") {
            UserDefaults.standard.removeObject(forKey: latestKey)
            UserDefaults.standard.removeObject(forKey: "latestDailySummaryKey")
        }
    }
    
    private func showDailySummaryCard(with data: [String: Any]) {
        // Don't show if already showing
        if dailySummaryCard != nil { return }
        
        // Create the card
        let card = DailySummaryCardView()
        card.delegate = self
        card.configure(with: data)
        card.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to the activity feed section at the top
        activityFeedSection.addSubview(card)
        
        // Position between header and segmented control
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.small),
            card.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.medium),
            card.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        // Adjust segmented control position
        contentSegmentedControl.constraints.forEach { constraint in
            if constraint.firstItem === contentSegmentedControl && 
               constraint.firstAttribute == .top &&
               constraint.secondItem === activityHeaderLabel {
                constraint.isActive = false
            }
        }
        
        contentSegmentedControl.topAnchor.constraint(equalTo: card.bottomAnchor, constant: Constants.Spacing.small).isActive = true
        
        // Animate in
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -20)
        
        UIView.animate(withDuration: 0.3) {
            card.alpha = 1
            card.transform = .identity
        }
        
        dailySummaryCard = card
        hasDailySummaryData = true
    }
    
    private func removeDailySummaryCard() {
        guard let card = dailySummaryCard else { return }
        
        // Restore segmented control constraint
        contentSegmentedControl.constraints.forEach { constraint in
            if constraint.firstItem === contentSegmentedControl && 
               constraint.firstAttribute == .top &&
               constraint.secondItem === card {
                constraint.isActive = false
            }
        }
        
        contentSegmentedControl.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.small).isActive = true
        
        // Animate out
        UIView.animate(withDuration: 0.3, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: -20)
        }) { _ in
            card.removeFromSuperview()
        }
        
        dailySummaryCard = nil
        hasDailySummaryData = false
    }
}

// MARK: - DailySummaryCardViewDelegate
extension CirclesHomeViewController: DailySummaryCardViewDelegate {
    func dailySummaryCardDidTapNewPlaces() {
        // Already on home tab, just scroll to map
        scrollView.setContentOffset(.zero, animated: true)
    }
    
    func dailySummaryCardDidTapNewConnections() {
        // Navigate to network tab
        if let tabBarController = tabBarController {
            tabBarController.selectedIndex = 1
        }
    }
    
    func dailySummaryCardDidTapUnreadMessages() {
        // Navigate to messages tab
        if let tabBarController = tabBarController {
            tabBarController.selectedIndex = 2
        }
    }
    
    func dailySummaryCardDidTapClose() {
        removeDailySummaryCard()
        
        // Clear the stored data for today
        if let latestKey = UserDefaults.standard.string(forKey: "latestDailySummaryKey") {
            UserDefaults.standard.removeObject(forKey: latestKey)
            UserDefaults.standard.removeObject(forKey: "latestDailySummaryKey")
        }
    }
    
    func dailySummaryCardDidExpand() {
        // Track analytics if needed
        print("📊 Daily summary expanded")
    }
    
    func dailySummaryCardDidCollapse() {
        // Track analytics if needed
        print("📊 Daily summary collapsed")
    }
}

// MARK: - ActivityFeedCellDelegate
extension CirclesHomeViewController: ActivityFeedCellDelegate {
    func didTapUserProfile(user: User) {
        // Navigate to user's profile
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func didTapActivityContent(activity: Activity) {
        // Navigate based on activity type
        switch activity.type {
        case .videoUploaded:
            // For video uploads, navigate to the video player
            navigateToVideoFromActivity(activity)
        case .placeAdded, .placeLiked, .placeCommented, .checkIn:
            // For place-related activities, navigate to place detail
            navigateToPlaceFromActivity(activity)
        default:
            break
        }
    }
    
    func didTapPlaceImage(activity: Activity) {
        navigateToPlaceFromActivity(activity)
    }
    
    private func navigateToVideoFromActivity(_ activity: Activity) {
        // The targetId contains the video ID for video upload activities
        let videoId = activity.targetId
        guard !videoId.isEmpty else { return }
        
        // Fetch the video details
        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { [weak self] (result: Result<PlaceVideoResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let video = response.data
                    // Create and present the video player with just this video
                    let videoReelsVC = VideoReelsViewController(reels: [video], startIndex: 0)
                        videoReelsVC.modalPresentationStyle = .fullScreen
                        
                        // Set up navigation handler for when user taps on place in video
                        videoReelsVC.placeNavigationHandler = { [weak self] placeId in
                            // Dismiss the video player first
                            self?.dismiss(animated: true) {
                                // Then navigate to place
                                let tempActivity = Activity(
                                    id: activity.id,
                                    type: .placeAdded,
                                    actorId: activity.actorId,
                                    actor: activity.actor,
                                    targetType: "place",
                                    targetId: placeId,
                                    targetName: activity.targetName,
                                    circleId: activity.circleId,
                                    circleName: activity.circleName,
                                    metadata: activity.metadata,
                                    timestamp: activity.timestamp,
                                    isRead: activity.isRead,
                                    reactionCount: activity.reactionCount,
                                    commentCount: activity.commentCount,
                                    userReaction: activity.userReaction,
                                    reactionSummary: activity.reactionSummary
                                )
                                self?.navigateToPlaceFromActivity(tempActivity)
                            }
                        }
                        
                        self?.present(videoReelsVC, animated: true)
                case .failure(let error):
                    self?.showError("Failed to load video: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func navigateToPlaceFromActivity(_ activity: Activity) {
        // For video uploads, use placeId from metadata; for check-ins use metadata placeId; otherwise use targetId
        let placeId: String
        if activity.type == .videoUploaded || activity.type == .checkIn {
            placeId = activity.metadata?.placeId ?? ""
        } else {
            placeId = activity.targetId
        }
        guard !placeId.isEmpty else { return }
        
        Logger.info("🔍 navigateToPlaceFromActivity: Attempting to navigate to place")
        Logger.info("🔍 Activity type: \(activity.type)")
        Logger.info("🔍 Activity target: \(activity.targetName)")
        Logger.info("🔍 PlaceId: \(placeId)")
        Logger.info("🔍 CircleId: \(activity.circleId ?? "none")")
        Logger.info("🔍 Actor: \(activity.actor?.displayName ?? "unknown")")
        
        // Try to find the place in an existing circle
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] (result: Result<Place, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let place):
                    Logger.info("✅ Successfully fetched place: \(place.name)")
                    let detailVC = PlaceDetailViewController(place: place)
                    self?.navigationController?.pushViewController(detailVC, animated: true)
                case .failure(let error):
                    Logger.error("❌ Failed to fetch place \(placeId): \(error.localizedDescription)")
                    // If we can't fetch the place (likely because it's not in a user's circle),
                    // create a temporary place object from the activity metadata for check-ins and video uploads
                    if activity.type == .checkIn || activity.type == .videoUploaded {
                        let placeName = activity.targetName
                        
                        // Show a simple place view with limited functionality
                        let tempPlaceVC = TempPlaceDetailViewController()
                        tempPlaceVC.configure(
                            placeId: placeId,
                            name: placeName,
                            address: activity.metadata?.placeAddress ?? "",
                            latitude: activity.metadata?.latitude,
                            longitude: activity.metadata?.longitude,
                            photo: activity.metadata?.placePhoto
                        )
                        self?.navigationController?.pushViewController(tempPlaceVC, animated: true)
                    } else {
                        self?.showError("Unable to load place details")
                    }
                }
            }
        }
    }
    
    func didTapReactions(activity: Activity) {
        // Show unified engagement view (LinkedIn-style)
        let engagementVC = ActivityEngagementViewController(activity: activity)
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func didTapComments(activity: Activity) {
        // Show comments view
        let commentsVC = ActivityCommentsViewController(activity: activity)
        commentsVC.onCommentsUpdated = { [weak self] commentCount in
            // Since Activity is a struct with let properties, we need to refresh the data
            // to get the updated comment count from the server
            self?.refreshActivityFeed()
        }
        let navController = UINavigationController(rootViewController: commentsVC)
        present(navController, animated: true)
    }
    
    func didTapReactionButton(activity: Activity, emoji: String) {
        // Toggle reaction - if user already has this reaction, remove it, otherwise add it
        let endpoint = activity.userReaction == emoji ? 
            "activities/\(activity.id)/reactions/remove" : 
            "activities/\(activity.id)/reactions"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: ["emoji": emoji]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Reload activity feed to show updated reaction count
                    self?.fetchActivities()
                case .failure(let error):
                    self?.showError("Failed to update reaction: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func didLongPressReactionButton(activity: Activity, sourceView: UIView) {
        // Create and show reaction picker
        let reactionPicker = ReactionPickerView()
        reactionPicker.delegate = self
        reactionPicker.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view hierarchy
        view.addSubview(reactionPicker)
        
        // Constrain to fill the view
        NSLayoutConstraint.activate([
            reactionPicker.topAnchor.constraint(equalTo: view.topAnchor),
            reactionPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reactionPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reactionPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store activity for later use
        currentReactionActivity = activity
        
        // Show picker near the source view
        reactionPicker.show(from: sourceView)
    }
}

// MARK: - ReactionPickerDelegate
extension CirclesHomeViewController: ReactionPickerDelegate {
    func reactionPicker(_ picker: ReactionPickerView, didSelectReaction reaction: ReactionStyle) {
        guard let activity = currentReactionActivity else { return }
        
        // Send reaction to server
        didTapReactionButton(activity: activity, emoji: reaction.rawValue)
        
        // Clear stored activity
        currentReactionActivity = nil
    }
    
    func reactionPickerDidDismiss(_ picker: ReactionPickerView) {
        // Clear stored activity
        currentReactionActivity = nil
    }
}

// MARK: - Navigation from Notifications
extension CirclesHomeViewController {
    func scrollToTop() {
        DispatchQueue.main.async {
            self.scrollView.setContentOffset(.zero, animated: true)
        }
    }
    
    func navigateToCircle(withId circleId: String) {
        // Find the circle in our data
        guard let circle = circles.first(where: { $0.id == circleId }) else {
            // If circle not found, try to load it
            loadCircleAndNavigate(circleId: circleId)
            return
        }
        
        // Navigate to circle detail
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func loadCircleAndNavigate(circleId: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading circle...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circle):
                        let detailVC = CircleDetailViewController(circle: circle)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load circle: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    func navigateToPlace(withId placeId: String) {
        // Try to find the place in our loaded data first
        if let place = allPlaces.first(where: { $0.id == placeId }) {
            // Find the circle for this place
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else {
            // If not found, load the place
            loadPlaceAndNavigate(placeId: placeId)
        }
    }
    
    private func navigateToVideo(withId videoId: String) {
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Loading video...", from: self)
        
        // Fetch video details
        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { [weak self] (result: Result<VideoResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let response):
                        // Create array with just this video
                        let reels = [response.data]
                        
                        // Open VideoReelsViewController
                        let reelsVC = VideoReelsViewController(reels: reels, startIndex: 0)
                        
                        // Set the place navigation handler
                        reelsVC.placeNavigationHandler = { [weak self] placeId in
                            // Navigate to place after video is dismissed
                            self?.navigateToPlace(withId: placeId)
                        }
                        
                        reelsVC.modalPresentationStyle = .fullScreen
                        self.present(reelsVC, animated: true)
                        
                    case .failure(let error):
                        self.showError("Unable to load video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func navigateToCheckInPlace(activity: Activity) {
        // First check if we have the place ID and can find it in our loaded data
        if let placeId = activity.metadata?.placeId,
           let place = allPlaces.first(where: { $0.id == placeId }) {
            // Found the place in our data, navigate normally
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else {
                // Place exists but not in a circle (floating place), still show it
                let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else if let placeId = activity.metadata?.placeId {
            // Have a place ID but not in our data, try to load it
            // But if it fails, fall back to creating from metadata
            PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let place):
                        // Successfully loaded the place
                        let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    case .failure:
                        // Failed to load, create from metadata
                        self?.navigateToCheckInPlaceFromMetadata(activity: activity)
                    }
                }
            }
        } else {
            // No place ID, create from metadata
            navigateToCheckInPlaceFromMetadata(activity: activity)
        }
    }
    
    private func navigateToCheckInPlaceFromMetadata(activity: Activity) {
        // Create a temporary place from check-in metadata
        guard let metadata = activity.metadata else {
            showError("Unable to load place details for this check-in")
            return
        }
        
        // Determine place category
        let categoryString = metadata.placeCategory ?? "other"
        let category = PlaceCategory(rawValue: categoryString) ?? .other
        
        // Create coordinate if we have location data
        var coordinate: CLLocationCoordinate2D?
        if let lat = metadata.latitude, let lng = metadata.longitude {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        // Create GeoLocation from coordinate
        var geoLocation: GeoLocation? = nil
        if let coord = coordinate {
            geoLocation = GeoLocation(
                type: "Point",
                coordinates: [coord.longitude, coord.latitude]
            )
        }
        
        // Create a temporary place object
        let tempPlace = Place(
            id: activity.metadata?.placeId ?? UUID().uuidString,
            name: activity.targetName,
            description: nil,
            address: metadata.placeAddress ?? "",
            location: geoLocation,
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: metadata.placePhoto != nil ? [metadata.placePhoto!] : nil,
            videos: nil,
            category: category,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: metadata.message,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: 0,
            circleId: metadata.circleId ?? "",
            addedBy: activity.actorId,
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date(),
            isNew: true
        )
        
        // Navigate to place detail with the temporary place
        let placeDetailVC = PlaceDetailViewController(place: tempPlace, circle: nil)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    private func loadPlaceAndNavigate(placeId: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading place...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        // We need to find the circle
                        guard let circleId = place.circleId else {
                            let alert = UIAlertController(
                                title: "Error",
                                message: "Place has no associated circle",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(alert, animated: true)
                            return
                        }
                        CircleService.shared.fetchCircleById(id: circleId) { circleResult in
                            DispatchQueue.main.async {
                                switch circleResult {
                                case .success(let circle):
                                    let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                                    self.navigationController?.pushViewController(placeDetailVC, animated: true)
                                case .failure:
                                    // Show error
                                    let alert = UIAlertController(
                                        title: "Error",
                                        message: "Failed to load place details",
                                        preferredStyle: .alert
                                    )
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(alert, animated: true)
                                }
                            }
                        }
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Swipe Actions for Activity Table
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only handle swipe actions for activity table
        guard tableView == activityTableView else { return nil }
        
        // Add bounds check
        guard indexPath.row < activities.count else { return nil }
        
        let activity = activities[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only allow deletion of user's own activities
        guard activity.actorId == currentUserId else { return nil }
        
        // Create delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeleteActivity(at: indexPath, completion: completion)
        }
        
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false // Require confirmation
        
        return configuration
    }
    
    // Helper method to confirm and delete activity
    private func confirmDeleteActivity(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        guard indexPath.row < activities.count else {
            completion(false)
            return
        }
        
        let activity = activities[indexPath.row]
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Delete Activity",
            message: "Are you sure you want to delete this activity? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteActivity(activity, at: indexPath, completion: completion)
        })
        
        present(alert, animated: true)
    }
    
    // Method to delete activity from backend and update UI
    private func deleteActivity(_ activity: Activity, at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        // Call API to delete activity
        let endpoint = "activities/\(activity.id)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .delete
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(false)
                    return
                }
                
                switch result {
                case .success:
                    // Remove activity from array
                    self.activities.remove(at: indexPath.row)
                    
                    // Update table view
                    self.activityTableView.deleteRows(at: [indexPath], with: .automatic)
                    
                    // Update empty state if needed
                    self.activityEmptyStateLabel.isHidden = !self.activities.isEmpty
                    
                    // Show success feedback
                    let successAlert = UIAlertController(
                        title: nil,
                        message: "Activity deleted successfully",
                        preferredStyle: .alert
                    )
                    self.present(successAlert, animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        successAlert.dismiss(animated: true)
                    }
                    
                    completion(true)
                    
                case .failure(let error):
                    print("Failed to delete activity: \(error)")
                    
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to delete activity. Please try again.",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    
                    completion(false)
                }
            }
        }
    }
}

// MARK: - UIScrollViewDelegate
extension CirclesHomeViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Handle activity table view scrolling for pagination
        if scrollView == activityTableView {
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.frame.height
            
            // Check if we're near the bottom (within 100 points)
            if offsetY > contentHeight - scrollViewHeight - 100 {
                if !activities.isEmpty && hasMoreActivities && !isLoadingMoreActivities {
                    print("📊 Reached bottom of activity table, loading more...")
                    fetchActivities(loadMore: true)
                }
            }
        }
        // Handle pagination for reels collection view
        else if scrollView == reelsCollectionView {
            let contentHeight = scrollView.contentSize.height
            let scrollOffset = scrollView.contentOffset.y
            let frameHeight = scrollView.frame.size.height
            
            if scrollOffset > contentHeight - frameHeight * 1.5 {
                if !isLoadingMoreReels && hasMoreReels {
                    fetchReels(loadMore: true)
                }
            }
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate && scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CirclesHomeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ensure touch.view is valid and is a UIView
        guard let touchView = touch.view as? UIView else {
            return false
        }
        
        // Don't intercept touches on the search bar or keyboard
        if touchView.isDescendant(of: searchBar) {
            return false
        }
        
        // Don't intercept touches if keyboard is showing (this prevents issues with keyboard buttons)
        if searchBar.isFirstResponder {
            return false
        }
        
        // Don't intercept touches on the dropdown table views
        if touchView.isDescendant(of: categoryDropdownTableView) ||
           touchView.isDescendant(of: connectionDropdownTableView) ||
           touchView.isDescendant(of: searchScopeTableView) ||
           touchView.isDescendant(of: searchResultsTableView) {
            return false
        }
        
        // Don't intercept touches on the dropdown containers themselves
        let location = touch.location(in: view)
        if !categoryDropdownView.isHidden && categoryDropdownView.frame.contains(location) {
            return false
        }
        if !connectionDropdownView.isHidden && connectionDropdownView.frame.contains(location) {
            return false
        }
        if !searchScopeDropdownView.isHidden && searchScopeDropdownView.frame.contains(location) {
            return false
        }
        if !searchResultsTableView.isHidden && searchResultsTableView.frame.contains(location) {
            return false
        }
        
        return true
    }
}

// MARK: - SSEServiceDelegate
extension CirclesHomeViewController {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        switch event.type {
        case .onboardingCompleted:
            // Onboarding completed - reload circles to show the new ones
            Logger.info("Received onboarding completed event, reloading circles")
            DispatchQueue.main.async { [weak self] in
                self?.loadData()
            }
            
        case .placeAdded, .circleCreated, .connectionActivity:
            // Connection activity events - refresh user list to show updated activity
            Logger.info("Received connection activity event, refreshing user list")
            DispatchQueue.main.async { [weak self] in
                self?.userListView.refresh()
                // Update notification badge for new activity
                print("🔔 CirclesHomeViewController: Updating badge for connection activity SSE event")
                self?.updateNotificationBadge()
                
                // Also refresh activity feed if on Activity tab
                if self?.contentSegmentedControl.selectedSegmentIndex == 0 {
                    self?.refreshActivityFeedWithNewItem()
                }
            }
            
        case .newActivity:
            // New activity in network - refresh activity feed
            Logger.info("Received new activity event for activity feed")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Update notification badge when new activity arrives
                print("🔔 CirclesHomeViewController: Updating badge for new activity SSE event")
                self.updateNotificationBadge()
                
                // Only refresh if Activity tab is selected
                if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                    self.refreshActivityFeedWithNewItem()
                }
            }
            
        default:
            // Handle other specific event types
            if let eventTypeString = event.data["type"] as? String {
                switch eventTypeString {
                case "moment_uploaded":
                    Logger.info("Received moment uploaded event")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // Refresh activity feed if on Activity tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                            self.refreshActivityFeedWithNewItem()
                        }
                        // Refresh moments feed if on Moments tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 1 {
                            self.fetchReels()
                        }
                    }
                    
                case "comment_added", "reaction_added", "check_in":
                    Logger.info("Received \(eventTypeString) event")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // Refresh activity feed if on Activity tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                            self.refreshActivityFeedWithNewItem()
                        }
                    }
                    
                default:
                    break
                }
            }
        }
    }
    
    private func refreshActivityFeedWithNewItem() {
        // Smart refresh - only load new items without full reload
        // This prevents scroll position loss and provides better UX
        
        // If we don't have any activities yet, do a full load
        if activities.isEmpty {
            fetchActivities()
            return
        }
        
        // Otherwise, fetch just the newest activities
        ActivityService.shared.getNetworkActivities(limit: 5, offset: 0) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let newActivities = response.activities
                    
                    // Find activities that aren't already in our list
                    var addedActivities: [Activity] = []
                    for activity in newActivities {
                        if !self.activities.contains(where: { $0.id == activity.id }) {
                            addedActivities.append(activity)
                        }
                    }
                    
                    if !addedActivities.isEmpty {
                        // Insert new activities at the beginning
                        self.activities.insert(contentsOf: addedActivities, at: 0)
                        
                        // Update table view with animation
                        let indexPaths = (0..<addedActivities.count).map { IndexPath(row: $0, section: 0) }
                        self.activityTableView.insertRows(at: indexPaths, with: .automatic)
                        
                        // Update empty state
                        self.activityEmptyStateLabel.isHidden = !self.activities.isEmpty
                        
                        Logger.info("Added \(addedActivities.count) new activities to feed via SSE")
                    }
                    
                case .failure(let error):
                    Logger.error("Failed to fetch new activities via SSE: \(error)")
                }
            }
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
        Logger.info("SSE connection established")
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
        if let error = error {
            Logger.error("SSE connection lost: \(error)")
        } else {
            Logger.info("SSE connection closed")
        }
    }
}

// MARK: - SuggestedUsersOverlayViewDelegate
extension CirclesHomeViewController: SuggestedUsersOverlayViewDelegate {
    func didSelectUser(_ user: User) {
        // User selected a suggested user - refresh connections
        userListView.refresh()
    }
    
    func didTapExploreNetwork() {
        // Navigate directly to DiscoverUsersViewController for new users
        let discoverVC = DiscoverUsersViewController()
        let navController = UINavigationController(rootViewController: discoverVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    func didTapImportContacts() {
        // Navigate to My Network tab with contacts import
        if let tabBarController = self.tabBarController as? CirclesTabBarController {
            tabBarController.selectedIndex = 1 // My Network tab
            
            // Trigger contacts import in the My Network tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: NSNotification.Name("ShowContactsImport"), object: nil)
            }
        }
    }
    
    func didDismissOverlay() {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        
        if isShowingWelcomeTour {
            // If in tour mode, reset the flag
            isShowingWelcomeTour = false
        } else {
            // Mark that user has dismissed the overlay in normal flow
            OnboardingManager.shared.disableSuggestedUsersOverlay()
            
            // Now check and show tutorial
            checkTutorialAndOverlay()
        }
    }
    
    func didTapNext(selectedUsers: [User]) {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, force show the add place tutorial
            forceShowAddPlaceTutorial()
        } else {
            // Normal flow - check if should show add place tutorial
            showAddPlaceTutorialIfNeeded()
        }
    }
    
    func didTapSkip() {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        hasCheckedForSuggestedUsers = true  // Set the flag to prevent showing again
        
        if isShowingWelcomeTour {
            // In tour mode, force show the add place tutorial
            forceShowAddPlaceTutorial()
        } else {
            // Normal flow - check if should show add place tutorial
            showAddPlaceTutorialIfNeeded()
        }
    }
}

// MARK: - ContentUploadDelegate
extension CirclesHomeViewController: ContentUploadDelegate {
    func contentUploadDidFinish(with moment: PlaceMoment) {
        // Refresh reels to show the newly uploaded video
        fetchReels()
        
        // Also refresh activities to show the upload activity
        fetchActivities()
        
        // Ensure the correct tab content is displayed based on selected tab
        // This prevents Moments content from showing when Activity tab is selected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.contentSegmentChanged()
        }
    }
    
    func contentUploadDidCancel() {
        // Nothing to do on cancel
    }
}

// MARK: - AddFirstPlaceTutorialViewDelegate
extension CirclesHomeViewController: AddFirstPlaceTutorialViewDelegate {
    func didTapGotIt() {
        // Clean up overlay reference
        addPlaceTutorialOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, just reset the flag
            isShowingWelcomeTour = false
            // Don't mark as shown so it can be shown again
        } else {
            // Normal flow - mark tutorial as shown
            OnboardingManager.shared.markAddPlaceTutorialShown()
            
            // Continue with visit tracking permission
            showVisitTrackingPermissionIfNeeded()
        }
    }
    
    func didTapSkipTutorial() {
        // Clean up overlay reference
        addPlaceTutorialOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, just reset the flag
            isShowingWelcomeTour = false
            // Don't mark as shown so it can be shown again
        } else {
            // Normal flow - mark tutorial as shown
            OnboardingManager.shared.markAddPlaceTutorialShown()
            
            // Continue with visit tracking permission
            showVisitTrackingPermissionIfNeeded()
        }
    }
}

// MARK: - VisitTrackingPermissionViewDelegate

extension CirclesHomeViewController: VisitTrackingPermissionViewDelegate {
    func didEnableVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark permission response
        OnboardingManager.shared.setVisitTrackingPermissionResponse(enabled: true)
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
    
    func didDisableVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark permission response
        OnboardingManager.shared.setVisitTrackingPermissionResponse(enabled: false)
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
    
    func didSkipVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark as shown but no response
        OnboardingManager.shared.markVisitTrackingPermissionShown()
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
}

// MARK: - QuickAccessPlacesDelegate

extension CirclesHomeViewController: QuickAccessPlacesDelegate {
    func didUpdateQuickAccessPlaces(_ places: [Place]) {
        // Convert places to dictionary format for storage
        let placesData = places.map { place -> [String: Any] in
            return [
                "id": place.id,
                "name": place.name,
                "address": place.address,
                "latitude": place.location?.coordinates[1] ?? 0,
                "longitude": place.location?.coordinates[0] ?? 0
            ]
        }
        
        saveQuickAccessPlaces(placesData)
    }
}

// MARK: - UICollectionViewDataSource

extension CirclesHomeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == reelsCollectionView {
            return reels.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == reelsCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoReelCell", for: indexPath) as! VideoReelCell
            let reel = reels[indexPath.item]
            
            // Check video state for this index
            let videoState = reelVideoStates[indexPath.item] ?? .notLoaded
            
            // Load video if needed and not already loading
            if reel.contentType != "photo" && !reel.isEmbedded && videoState == .notLoaded {
                reelVideoStates[indexPath.item] = .loading
                loadReelVideo(at: indexPath.item)
            } else if reel.isEmbedded && videoState == .notLoaded {
                // Mark embedded videos as ready immediately
                reelVideoStates[indexPath.item] = .ready
            }
            
            // Only pass player for non-embedded videos
            let player: AVPlayer? = {
                if reel.contentType == "photo" || reel.isEmbedded {
                    return nil // Photos and embedded videos don't use AVPlayer
                }
                return videoState == .ready ? reelPlayers[indexPath.item] : nil
            }()
            
            // Configure cell - it will handle embedded videos internally
            cell.configure(with: reel, player: player)
            cell.delegate = self
            
            return cell
        }
        return UICollectionViewCell()
    }
}

// MARK: - UICollectionViewDelegate

extension CirclesHomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == reelsCollectionView {
            // Videos are played inline, no need to open full screen
            // Just ensure the video at this index is playing
            if indexPath.item != currentReelIndex {
                let offsetY = CGFloat(indexPath.item) * collectionView.frame.size.height
                collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
            }
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension CirclesHomeViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == reelsCollectionView {
            // Simply return the collection view's size - no need for complex calculations
            return collectionView.frame.size
        }
        return CGSize.zero
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == reelsCollectionView {
            return 0
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == reelsCollectionView {
            return 0
        }
        return 0
    }
}

// MARK: - VideoLinkInputDelegate

// Keep the old delegate for backward compatibility if needed
extension CirclesHomeViewController: VideoLinkInputDelegate {
    func videoLinkInputDidFinish(with video: PlaceVideo) {
        // Convert to moment and handle
        let moment = PlaceMoment(from: video)
        contentUploadDidFinish(with: moment)
    }
    
    func videoLinkInputDidCancel() {
        // User cancelled - nothing to do
    }
}

// MARK: - Video Management

extension CirclesHomeViewController {
    private func loadReelVideo(at index: Int) {
        guard index >= 0 && index < reels.count else { 
            reelVideoStates[index] = .failed
            return 
        }
        
        let reel = reels[index]
        
        // Skip loading video player for photos
        if reel.contentType == "photo" {
            reelVideoStates[index] = .ready // Photos don't need video loading
            return
        }
        
        // Skip loading AVPlayer for embedded videos - they use EmbeddedVideoPlayerView
        if reel.isEmbedded {
            print("✅ CirclesHome: Skipping AVPlayer for embedded video \(reel.id)")
            print("   - videoType: \(reel.videoType ?? "nil")")
            print("   - embedPlatform: \(reel.embedPlatform ?? "nil")")
            print("   - embedUrl: \(reel.embedUrl ?? "nil")")
            reelVideoStates[index] = .ready // Mark as ready so cell will be configured
            return
        }
        
        // For regular and direct videos, load AVPlayer
        guard let urlString = reel.videoUrl ?? reel.previewUrl,
              let url = URL(string: urlString) else { 
            print("❌ CirclesHome: Invalid video URL for reel \(reel.id)")
            print("   - videoUrl: \(reel.videoUrl ?? "nil")")
            print("   - previewUrl: \(reel.previewUrl ?? "nil")")
            print("   - title: \(reel.title)")
            print("   - uploadStatus: \(reel.uploadStatus.rawValue)")
            reelVideoStates[index] = .failed
            return 
        }
        
        // Create player
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none // Loop video
        
        // Enable audio playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ CirclesHome: Failed to setup audio session: \(error)")
        }
        
        reelPlayers[index] = player
        reelVideoStates[index] = .ready
        print("✅ CirclesHome: Loaded video for index \(index), URL: \(url)")
        
        // Force collection view to reload this cell to update with the player
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let indexPath = IndexPath(item: index, section: 0)
            
            // Only update if the cell is still showing the same reel
            if index < self.reels.count,
               let cell = self.reelsCollectionView.cellForItem(at: indexPath) as? VideoReelCell {
                cell.configure(with: reel, player: player)
                print("📹 CirclesHome: Reconfigured cell with player for index \(index)")
            }
        }
    }
    
    private func updateCurrentReelIndex() {
        let center = CGPoint(x: reelsCollectionView.frame.size.width / 2 + reelsCollectionView.contentOffset.x,
                            y: reelsCollectionView.frame.size.height / 2 + reelsCollectionView.contentOffset.y)
        
        if let indexPath = reelsCollectionView.indexPathForItem(at: center), indexPath.item != currentReelIndex {
            // Pause previous video
            pauseVideo(at: currentReelIndex)
            
            // Update current index
            currentReelIndex = indexPath.item
            
            // Play new video
            playVideo(at: currentReelIndex)
            
            // Preload adjacent videos
            preloadAdjacentVideos()
        }
    }
    
    private func playVideo(at index: Int) {
        guard index >= 0 && index < reels.count else { return }
        
        // Track view for both photos and videos
        trackReelView(at: index)
        
        // Check if it's a photo
        if reels[index].contentType == "photo" {
            return
        }
        
        // Play video if available
        if let player = reelPlayers[index] {
            // Restart from beginning when returning to video
            player.seek(to: .zero) { _ in
                player.play()
                print("▶️ CirclesHome: Playing video at index \(index) from beginning")
            }
        } else {
            // Load and play
            loadReelVideo(at: index)
            // Player will auto-play when ready if we add KVO like in VideoReelsViewController
        }
    }
    
    private func pauseVideo(at index: Int) {
        if let player = reelPlayers[index] {
            player.pause()
            print("⏸ CirclesHome: Paused video at index \(index)")
        }
    }
    
    private func pauseAllVideos() {
        for player in reelPlayers.values {
            player.pause()
        }
    }
    
    private func trackReelView(at index: Int) {
        guard index >= 0 && index < reels.count else { return }
        
        let reel = reels[index]
        let endpoint = "videos/reels/\(reel.id)/view"
        
        // Send view tracking request
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            // Silent tracking, no need to handle response
            if case .failure(let error) = result {
                print("❌ CirclesHome: Failed to track view for reel \(reel.id): \(error)")
            } else {
                print("✅ CirclesHome: Successfully tracked view for reel \(reel.id)")
            }
        }
    }
    
    private func preloadAdjacentVideos() {
        // Preload videos around current index
        let preloadRange = max(0, currentReelIndex - 1)...min(reels.count - 1, currentReelIndex + 1)
        
        for index in preloadRange {
            let videoState = reelVideoStates[index] ?? .notLoaded
            if videoState == .notLoaded && reels[index].contentType != "photo" {
                reelVideoStates[index] = .loading
                loadReelVideo(at: index)
            }
        }
        
        // Clean up distant videos to save memory
        releaseDistantVideos()
    }
    
    private func releaseDistantVideos() {
        // Release videos that are more than 2 positions away
        for (index, player) in reelPlayers {
            if abs(index - currentReelIndex) > 2 {
                player.pause()
                reelPlayers.removeValue(forKey: index)
                reelVideoStates[index] = .notLoaded // Reset state for released videos
                print("🗑 CirclesHome: Released video at index \(index)")
            }
        }
    }
}

// MARK: - VideoReelCellDelegate

extension CirclesHomeViewController: VideoReelCellDelegate {
    func videoReelCellDidTapLike(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        var reel = reels[indexPath.item]
        
        // Toggle like state optimistically
        let wasLiked = reel.likedByCurrentUser ?? false
        reel.likedByCurrentUser = !wasLiked
        reel.likeCount = wasLiked ? max(0, reel.likeCount - 1) : reel.likeCount + 1
        reels[indexPath.item] = reel
        
        // Update cell
        cell.configure(with: reel, player: reelPlayers[indexPath.item])
        
        // Call API
        let endpoint = wasLiked 
            ? "videos/reels/\(reel.id)/like"
            : "videos/reels/\(reel.id)/like"
        let method: RequestMethod = wasLiked ? .delete : .post
        
        APIService.shared.request(
            endpoint: endpoint,
            method: method,
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                // Revert on failure
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    reel.likedByCurrentUser = wasLiked
                    reel.likeCount = wasLiked ? reel.likeCount + 1 : max(0, reel.likeCount - 1)
                    self.reels[indexPath.item] = reel
                    
                    if let cell = self.reelsCollectionView.cellForItem(at: indexPath) as? VideoReelCell {
                        cell.configure(with: reel, player: self.reelPlayers[indexPath.item])
                    }
                    
                    print("Failed to update like: \(error)")
                }
            }
        }
    }
    
    func videoReelCellDidTapComment(_ cell: VideoReelCell) {
        // Not opening full screen - just show comments in a sheet
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        let commentsVC = VideoCommentsViewController(video: reel)
        let nav = UINavigationController(rootViewController: commentsVC)
        nav.modalPresentationStyle = .pageSheet
        
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        
        present(nav, animated: true)
    }
    
    func videoReelCellDidTapShare(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Generating share link...", from: self)
        
        // Call API to generate share link
        APIService.shared.request(
            endpoint: "videos/\(reel.id)/share",
            method: .post
        ) { [weak self] (result: Result<VideoShareLinkResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: false) {
                    switch result {
                    case .success(let response):
                        // Create share items with the generated URL
                        var shareItems: [Any] = []
                        
                        // Add share text
                        shareItems.append(response.data.shareText)
                        
                        // Add share URL
                        if let url = URL(string: response.data.shareUrl) {
                            shareItems.append(url)
                        }
                        
                        // Add thumbnail image if available
                        if let thumbnailUrl = response.data.thumbnailUrl,
                           let cachedImage = ImageService.shared.getCachedImage(for: thumbnailUrl) {
                            shareItems.append(cachedImage)
                        }
                        
                        let activityVC = UIActivityViewController(
                            activityItems: shareItems,
                            applicationActivities: nil
                        )
                        
                        // Customize the share sheet
                        activityVC.setValue(response.data.videoTitle ?? "Check out this moment", forKey: "subject")
                        
                        // For iPad
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        }
                        
                        self?.present(activityVC, animated: true)
                        
                    case .failure(let error):
                        // Fallback to basic sharing if API fails
                        let shareText = "Check out this moment at \(reel.placeName) on Circles!"
                        let shareItems: [Any] = [shareText]
                        
                        let activityVC = UIActivityViewController(
                            activityItems: shareItems,
                            applicationActivities: nil
                        )
                        
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = cell
                            popover.sourceRect = cell.bounds
                        }
                        
                        self?.present(activityVC, animated: true)
                        
                        print("Failed to generate share link: \(error)")
                    }
                }
            }
        }
    }
    
    func videoReelCellDidTapProfile(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell),
              let user = reels[indexPath.item].user else { return }
        
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func videoReelCellDidTapPlace(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before navigating away
        pauseAllVideos()
        
        // Navigate to place detail
        showLoadingState()
        
        APIService.shared.request(
            endpoint: "places/\(reel.placeId)",
            method: .get
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success(let response):
                    if response.success {
                        let placeDetailVC = PlaceDetailViewController(place: response.place, circle: nil)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    }
                case .failure(let error):
                    self?.showError("Unable to load place details")
                    print("❌ CirclesHome: Failed to fetch place details: \(error)")
                }
            }
        }
    }
    
    func videoReelCellDidTapReaction(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before presenting engagement view
        pauseAllVideos()
        
        // Present the engagement view controller
        let engagementVC = VideoEngagementViewController(video: reel)
        engagementVC.setSelectedSegment(0) // Show likes tab
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func videoReelCellDidTapActivityEngagement(_ cell: VideoReelCell) {
        guard let indexPath = reelsCollectionView.indexPath(for: cell) else { return }
        let reel = reels[indexPath.item]
        
        // Pause all playing videos before presenting engagement view
        pauseAllVideos()
        
        // Present the engagement view controller
        let engagementVC = VideoEngagementViewController(video: reel)
        engagementVC.setSelectedSegment(1) // Show comments tab
        let navController = UINavigationController(rootViewController: engagementVC)
        present(navController, animated: true)
    }
    
    func videoReelCellDidTapLikeCount(_ cell: VideoReelCell) {
        // Not implementing like count view in the home feed
        // In a full implementation, we could show a modal with users who liked
    }
    
    // MARK: - Notification Badge Timer Management
    
    private func startNotificationBadgeRefresh() {
        // Invalidate existing timer
        notificationBadgeTimer?.invalidate()
        
        // Start a timer that refreshes notification badge every 30 seconds
        // This ensures the badge stays current even if SSE events are missed
        notificationBadgeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            print("🔔 [Timer] Periodic notification badge refresh")
            self?.updateNotificationBadge()
        }
        
        print("🔔 [Timer] Started periodic notification badge refresh (30s interval)")
    }
    
    private func stopNotificationBadgeRefresh() {
        notificationBadgeTimer?.invalidate()
        notificationBadgeTimer = nil
        print("🔔 [Timer] Stopped periodic notification badge refresh")
    }
}

