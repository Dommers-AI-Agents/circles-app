import UIKit
import CoreLocation
import UniformTypeIdentifiers
import MapKit

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
    private var isReturningFromFullScreenMap = false // Prevent map updates when returning from full screen
    private var isLoadingCircles = false // Track when circles are being loaded
    private var isLoadingPlaces = false // Track when places are being loaded
    private var isPerformingInitialLoad = false // Track if we're in the middle of initial loading
    private var isShowingLoadingUI = false // Track if loading UI is currently shown
    private static var hasLoadedInitialData = false // Track if we've loaded data at least once this session
    private var hasStartedLoading = false // Instance flag to prevent multiple loads in the same instance
    private var isMapDataReady = false // Track if map data is ready to be displayed
    
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
    
    private let createCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create a Circle", for: .normal)
        button.setTitleColor(Constants.Colors.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
        button.setTitle("My Places Only", for: .normal)
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
    private var selectedConnectionId: String? = "my_places_only" // Default to My Places Only
    
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
    
    // Suggested Users Overlay
    private var hasCheckedForSuggestedUsers = false
    private var hasCheckedTutorialAndOverlay = false
    
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
        setupNotifications()
        setupSearchBar()
        setupDropdownViews()
        
        // Setup user list delegate
        userListView.delegate = self
        
        // Setup SSE delegate
        SSEService.shared.addDelegate(self)
        
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
    }
    
    deinit {
        // Clean up timers
        mapUpdateTimer?.invalidate()
        loadDebounceTimer?.invalidate()
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        // Remove SSE delegate
        SSEService.shared.removeDelegate(self)
        // Reset loading flag if this instance was loading
        if isPerformingInitialLoad {
            isPerformingInitialLoad = false
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        print("🟢 CirclesHomeViewController viewWillAppear called")
        print("🟢 Instance: \(ObjectIdentifier(self))")
        print("   hasStartedLoading: \(hasStartedLoading)")
        print("   isReturningFromFullScreenMap: \(isReturningFromFullScreenMap)")
        print("   circles.count: \(circles.count)")
        print("   allPlaces.count: \(allPlaces.count)")
        print("   preloadedData: \(preloadedData != nil)")
        
        // Update notification badge
        updateNotificationBadge()
        
        // If returning from full screen map, skip updates
        if isReturningFromFullScreenMap {
            isReturningFromFullScreenMap = false
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
            
            // Still need to refresh connections to get properly sorted data with message timestamps
            userListView.refresh()
            
            return  // Exit early, no timer needed
        }
        
        // Simple check: if this instance has already started loading, don't load again
        if hasStartedLoading {
            print("🟢 Skipping load - this instance has already started loading")
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
        
        // First check if user has 0 connections - show suggested users overlay if so
        let connectionCount = NetworkManager.shared.connections.count
        print("🔍 checkTutorialAndOverlay - Connection count: \(connectionCount)")
        
        if connectionCount == 0 {
            print("✅ User has 0 connections - checking if should show overlay")
            // For users with 0 connections, always show the overlay unless they've explicitly dismissed it this session
            // Reset the flag for users with 0 connections to ensure they see it
            if !hasCheckedForSuggestedUsers {
                // Enable the overlay for users with 0 connections
                OnboardingManager.shared.enableSuggestedUsersOverlay()
                print("✅ Enabled suggested users overlay for user with 0 connections")
            }
            
            if OnboardingManager.shared.shouldShowSuggestedUsers {
                print("✅ Should show suggested users overlay - calling showSuggestedUsersOverlay()")
                showSuggestedUsersOverlay()
                return
            } else {
                print("❌ Suggested users overlay disabled in settings")
            }
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
                            targetView: self.createCircleButton,
                            in: self,
                            arrowDirection: .top
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
        
        // Setup navigation bar
        let addButton = UIBarButtonItem(image: UIImage(systemName: "plus.circle"), style: .plain, target: self, action: #selector(addButtonTapped))
        
        // Create notification button with bell icon
        let notificationButton = UIBarButtonItem(image: UIImage(systemName: "bell"), style: .plain, target: self, action: #selector(notificationButtonTapped))
        self.notificationBarButton = notificationButton
        
        // Create custom view for notification button with badge
        setupNotificationBadge()
        
        // Set both buttons as right bar button items
        navigationItem.rightBarButtonItems = [addButton, notificationButton]
        
        // Setup empty state view
        emptyStateView.addSubview(emptyStateImageView)
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateView.addSubview(createCircleButton)
        
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
        activityFeedSection.addSubview(activityTableView)
        activityFeedSection.addSubview(activityEmptyStateLabel)
        activityFeedSection.addSubview(activityLoadingContainer)
        
        // Ensure loading container is on top
        activityFeedSection.bringSubviewToFront(activityLoadingContainer)
        
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
        
        // Bring elements to proper z-order - filters and expand button above map
        contentView.bringSubviewToFront(filterContainer)
        contentView.bringSubviewToFront(mapExpandButton)
        
        // Ensure loading view is on top
        view.bringSubviewToFront(loadingContainerView)
        
        // Add tap gesture to dismiss dropdowns when clicking outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissDropdowns))
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
            
            createCircleButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: Constants.Spacing.large),
            createCircleButton.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            createCircleButton.widthAnchor.constraint(equalTo: emptyStateView.widthAnchor, multiplier: 0.8),
            createCircleButton.heightAnchor.constraint(equalToConstant: 44),
            createCircleButton.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
            
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
            
            // Activity table view
            activityTableView.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            activityTableView.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor),
            activityTableView.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor),
            activityTableView.bottomAnchor.constraint(equalTo: activityFeedSection.bottomAnchor),
            
            // Activity empty state
            activityEmptyStateLabel.centerXAnchor.constraint(equalTo: activityFeedSection.centerXAnchor),
            activityEmptyStateLabel.centerYAnchor.constraint(equalTo: activityTableView.centerYAnchor),
            activityEmptyStateLabel.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.large),
            activityEmptyStateLabel.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Activity loading container
            activityLoadingContainer.centerXAnchor.constraint(equalTo: activityFeedSection.centerXAnchor),
            activityLoadingContainer.centerYAnchor.constraint(equalTo: activityTableView.centerYAnchor),
            activityLoadingContainer.widthAnchor.constraint(equalToConstant: 80),
            activityLoadingContainer.heightAnchor.constraint(equalToConstant: 80)
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
        
        createCircleButton.addTarget(self, action: #selector(createCircleButtonTapped), for: .touchUpInside)
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
        
        // Set scroll view delegate for pagination
        scrollView.delegate = self
        
        // Add refresh control to scroll view
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshActivityFeed), for: .valueChanged)
        scrollView.refreshControl = refreshControl
    }
    
    private func setupSearchBar() {
        searchBar.delegate = self
        
        // Add tap gesture to dismiss keyboard when tapping outside search bar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        // Add toolbar with Done button to search bar
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        
        toolbar.items = [flexSpace, doneButton]
        searchBar.inputAccessoryView = toolbar
    }
    
    @objc private func dismissKeyboard(_ gesture: UITapGestureRecognizer? = nil) {
        // If called from tap gesture, check if tap is outside search bar
        if let gesture = gesture {
            let location = gesture.location(in: view)
            let searchBarFrame = searchBar.convert(searchBar.bounds, to: view)
            
            // Only dismiss if tap is outside search bar
            if !searchBarFrame.contains(location) {
                searchBar.resignFirstResponder()
            }
        } else {
            // Called from Done button, always dismiss
            searchBar.resignFirstResponder()
        }
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
        
        print("📍 usePreloadedData: Got \(data.circles.count) circles")
        print("📍 usePreloadedData: Got \(data.allPlaces.count) places (INCOMPLETE!)")
        print("📍 usePreloadedData: Got \(data.connections.count) connections")
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
            
            // Set default filter (My Places Only)
            self.selectedConnectionId = "my_places_only"
            self.connectionFilterButton.setTitle("My Places Only", for: .normal)
            
            // Don't mark as ready - we need to fetch places
            self.isMapDataReady = false
            
            // Apply filters and update map
            // Don't update map yet - we need to fetch all places first
            
            // Update empty state visibility
            self.updateEmptyState()
            
            print("✅ Preloaded data applied successfully")
            print("   - Circles: \(self.circles.count)")
            print("   - Places: \(self.allPlaces.count) (INCOMPLETE - need to fetch all)")
            print("   - Filtered places: \(self.filteredPlaces.count)")
            
            // Now fetch ALL places from circles
            self.fetchAllPlacesFromCircles()
        }
    }
    
    // MARK: - Activity Feed Methods
    @objc private func refreshActivityFeed() {
        // Refresh the horizontal user list
        userListView.refresh()
        
        // Refresh activity feed
        fetchActivities()
        
        // Also refresh circles data for consistency
        if isShowingNetworkCircles {
            fetchNetworkCircles()
        } else {
            fetchCircles()
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
        
        // Show table view
        activityTableView.isHidden = false
        
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
    
    // MARK: - Data Fetching
    private func performInitialDataLoad() {
        
        // Unified method to load both circles and places
        print("🔄 Starting initial data load")
        
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
        
        // Load circles
        group.enter()
        fetchCircles {
            group.leave()
        }
        
        // Load activities in parallel
        group.enter()
        fetchActivities { _ in
            group.leave()
        }
        
        // Handle completion
        group.notify(queue: .main) { [weak self] in
            print("🔄 Initial data load completed")
            self?.hideLoadingState()
            
            // Refresh user list after all data is loaded to ensure correct order
            self?.userListView.refresh()
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
        print("🗺️ Hiding map loading state, showing map")
        print("🗺️ About to call fetchActivities from hideMapLoadingState")
        isShowingLoadingUI = false
        mapLoadingView.isHidden = true
        mapLoadingIndicator.stopAnimating()
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
        
        // Show place count now that loading is complete
        mapViewController?.showPlaceCount()
        
        // Fetch activities when map data is loaded
        fetchActivities()
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
    
    private func fetchNetworkCircles() {
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
                    // Don't call updateMapPlaces here - fetchAllPlacesFromCircles handles everything
                case .failure(let error):
                    print("❌ Error fetching network circles: \(error.localizedDescription)")
                    
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
                if userCircleIds.contains(place.circleId) {
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
                !userCircleIds.contains(place.circleId) && 
                !self.networkCircles.contains(where: { $0.id == place.circleId && IDNormalizer.isSameUser($0.owner, currentUserId) })
            }
            
            print("📍 BEFORE DEDUPLICATION:")
            print("   User places: \(userPlacesBeforeDedup.count)")
            print("   Network places: \(networkPlacesBeforeDedup.count)")
            
            // Deduplicate places that might exist in multiple circles
            let deduplicatedPlaces = self.removeDuplicatePlaces(allFetchedPlaces)
            self.allPlaces = deduplicatedPlaces
            
            // Count after deduplication using same logic as filter
            let userPlacesAfterDedup = deduplicatedPlaces.filter { place in
                if userCircleIds.contains(place.circleId) {
                    return true
                }
                if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                    return IDNormalizer.isSameUser(circle.owner, currentUserId)
                }
                return false
            }
            let networkPlacesAfterDedup = deduplicatedPlaces.filter { place in
                !userCircleIds.contains(place.circleId) && 
                !self.networkCircles.contains(where: { $0.id == place.circleId && IDNormalizer.isSameUser($0.owner, currentUserId) })
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
            
            // Mark that places data is ready
            self.isMapDataReady = true
            
            // Now update map with places since data is ready
            self.updateMapWhenReady()
                
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
    
    // MARK: - Actions
    @objc private func addButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        // Present modally wrapped in navigation controller for cancel button
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }
    
    
    @objc private func createCircleButtonTapped() {
        Task { @MainActor in
            // Check subscription limit
            let currentCircleCount = isShowingNetworkCircles ? networkCircles.count : circles.count
            
            if !SubscriptionManager.shared.checkCircleLimit(currentCount: currentCircleCount, from: self) {
                return
            }
            
            let createCircleVC = CreateCircleViewController()
            createCircleVC.delegate = self
            
            // Present modally wrapped in navigation controller for cancel button
            let navController = UINavigationController(rootViewController: createCircleVC)
            navController.modalPresentationStyle = .pageSheet
            present(navController, animated: true)
        }
    }
    
    // MARK: - Tutorial Support
    func highlightCreateCircleButton() {
        // Ensure empty state is visible
        showEmptyState()
        
        // Scroll to make sure the button is visible
        scrollView.scrollRectToVisible(createCircleButton.frame, animated: true)
        
        // Add a pulse animation to draw attention
        UIView.animate(withDuration: 0.6, delay: 0.2, options: [.repeat, .autoreverse, .allowUserInteraction], animations: {
            self.createCircleButton.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }) { _ in
            self.createCircleButton.transform = .identity
        }
        
        // Add a glow effect
        createCircleButton.layer.shadowColor = Constants.Colors.primary.cgColor
        createCircleButton.layer.shadowRadius = 20
        createCircleButton.layer.shadowOpacity = 0.8
        createCircleButton.layer.shadowOffset = .zero
        
        // Remove the effect after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 0.3) {
                self.createCircleButton.layer.shadowOpacity = 0
                self.createCircleButton.layer.removeAllAnimations()
            }
        }
    }
    
    @objc private func expandMapButtonTapped() {
        // Set flag to prevent map updates when returning
        isReturningFromFullScreenMap = true
        
        // Present full screen map with all places but no filters
        // Let the full screen map have its own independent filters
        let fullScreenMap = FullScreenMapViewController(
            places: allPlaces,
            initialRegion: nil,
            selectedCategory: nil,  // Don't pass embedded filter
            selectedConnectionId: nil  // Don't pass connection filter
        )
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.delegate = self  // Set delegate to handle place selection
        
        // Separate user places from connection places
        var userPlaces: [Place] = []
        var connectionPlacesMap: [String: [Place]] = [:]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let userCircleIds = Set(circles.map { $0.id })
        
        for place in allPlaces {
            // Check if this is a user's place
            if userCircleIds.contains(place.circleId) {
                userPlaces.append(place)
            } else if let circle = networkCircles.first(where: { $0.id == place.circleId }) {
                // Check if the circle owner is the current user (handles user circles in networkCircles)
                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                    userPlaces.append(place)
                } else {
                    // This is a connection's place
                    if connectionPlacesMap[circle.owner] == nil {
                        connectionPlacesMap[circle.owner] = []
                    }
                    connectionPlacesMap[circle.owner]?.append(place)
                }
            }
        }
        
        // Get connections from NetworkManager
        let connections = NetworkManager.shared.connections
        
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
                self?.createCircleButtonTapped()
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
            self?.createCircleButtonTapped()
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
                if userCircleIds.contains(place.circleId) {
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
                        if userCircleIds.contains(place.circleId) {
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
                var connectionFilteredPlaces: [Place] = []
                for place in places {
                    // Find the circle this place belongs to
                    if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                        if circle.owner == connectionId {
                            connectionFilteredPlaces.append(place)
                        }
                    }
                }
                mapFilteredPlaces = connectionFilteredPlaces
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
                category.matches(place: place)
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
    
    
    @objc private func categoryFilterButtonTapped() {
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
        // Get unique categories from all places, including custom categories
        var categoriesSet = Set<UnifiedCategory>()
        for place in allPlaces {
            categoriesSet.insert(UnifiedCategory.from(place: place))
        }
        availableCategories = Array(categoriesSet).sorted { $0.displayName < $1.displayName }
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
    
    @objc private func dismissDropdowns() {
        // Check if tapped outside of dropdowns
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
    
    @objc override func refreshData() {
        // Invalidate cache when user manually refreshes
        invalidateCache()
        
        // Refresh the horizontal user list
        userListView.refresh()
        
        // Refresh the activity feed
        fetchActivities()
        
        if isShowingNetworkCircles {
            fetchNetworkCircles()
        } else {
            fetchCircles()
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
        NotificationService.shared.getUnreadNotificationCount { [weak self] result in
            guard let self = self else { return }
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
                case .failure:
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
            return availableCategories.count + 1 // +1 for "All Categories"
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
                cell.textLabel?.text = "All Categories"
                cell.textLabel?.textColor = selectedCategory == nil ? Constants.Colors.primary : Constants.Colors.label
                cell.accessoryType = selectedCategory == nil ? .checkmark : .none
            } else {
                let category = availableCategories[indexPath.row - 1]
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
                let connection = NetworkManager.shared.connections[indexPath.row - 2]
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
            
            let scope = SearchScope.allCases[indexPath.row]
            cell.textLabel?.text = scope.title
            cell.textLabel?.textColor = currentSearchScope == scope ? Constants.Colors.primary : Constants.Colors.label
            cell.accessoryType = currentSearchScope == scope ? .checkmark : .none
            
            return cell
        } else if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
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
                    if networkCircle.id == place.circleId {
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
            if indexPath.row == 0 {
                // All Categories selected
                selectedCategory = nil
                categoryFilterButton.setTitle("All Categories", for: .normal)
            } else {
                // Specific category selected
                selectedCategory = availableCategories[indexPath.row - 1]
                categoryFilterButton.setTitle(selectedCategory?.displayName ?? "All Categories", for: .normal)
            }
            
            // Update UI and hide dropdown
            print("📍 Category filter changed to: \(selectedCategory?.displayName ?? "All Categories")")
            updateMapPlaces()
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
                let connection = NetworkManager.shared.connections[indexPath.row - 2]
                // Use the other user's ID (not the current user's ID)
                let currentUserId = AuthService.shared.getUserId() ?? ""
                selectedConnectionId = connection.otherUserId(currentUserId: currentUserId)
                let userName = connection.connectedUser?.displayName ?? "Unknown"
                connectionFilterButton.setTitle(userName, for: .normal)
            }
            
            // Update UI and hide dropdown
            print("📍 Connection filter changed to: \(selectedConnectionId ?? "All Connections")")
            updateMapPlaces()
            hideConnectionDropdown()
            isConnectionDropdownOpen = false
        } else if tableView == searchScopeTableView {
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
            handleSearchResultSelection(at: indexPath)
        } else if tableView == activityTableView {
            let activity = activities[indexPath.row]
            
            // Navigate based on activity type
            switch activity.type {
            case .placeAdded, .placeLiked, .placeCommented, .commentLiked:
                // Navigate to the place
                navigateToPlace(withId: activity.targetId)
            case .circleCreated:
                // Navigate to the circle
                navigateToCircle(withId: activity.targetId)
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
        // First check user's own circles
        if let circle = circles.first(where: { $0.places?.contains(place.id) == true }) {
            let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
            presentPlaceDetail(placeDetailVC, from: controller)
        } 
        // Then check network circles
        else if let networkCircle = networkCircles.first(where: { $0.places?.contains(place.id) == true }) {
            let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
            presentPlaceDetail(placeDetailVC, from: controller)
        }
    }
    
    private func presentPlaceDetail(_ placeDetailVC: PlaceDetailViewController, from controller: FullScreenMapViewController) {
        // Check if the map controller is presented modally
        if controller.isPresentedModally {
            // Present place detail modally on top of the full screen map
            let navController = UINavigationController(rootViewController: placeDetailVC)
            navController.modalPresentationStyle = .pageSheet
            controller.present(navController, animated: true)
        } else {
            // For embedded map, use regular navigation push
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
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
        if let circle = circles.first(where: { $0.id == place.circleId }) {
            targetCircle = circle
        }
        
        // Check network circles if not found
        if targetCircle == nil {
            targetCircle = networkCircles.first(where: { $0.id == place.circleId })
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

// MARK: - ActivityFeedCellDelegate
extension CirclesHomeViewController: ActivityFeedCellDelegate {
    func didTapUserProfile(user: User) {
        // Navigate to user's profile
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
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
                        CircleService.shared.fetchCircleById(id: place.circleId) { circleResult in
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
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CirclesHomeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't intercept touches on the dropdown table views
        if let touchView = touch.view {
            if touchView.isDescendant(of: categoryDropdownTableView) ||
               touchView.isDescendant(of: connectionDropdownTableView) ||
               touchView.isDescendant(of: searchScopeTableView) ||
               touchView.isDescendant(of: searchResultsTableView) {
                return false
            }
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
            }
        default:
            // Handle other events if needed
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
    }
}

// MARK: - SuggestedUsersOverlayViewDelegate
extension CirclesHomeViewController: SuggestedUsersOverlayViewDelegate {
    func didSelectUser(_ user: User) {
        // User selected a suggested user - refresh connections
        userListView.refresh()
    }
    
    func didTapExploreNetwork() {
        // Navigate to My Network tab
        if let tabBarController = self.tabBarController as? CirclesTabBarController {
            tabBarController.selectedIndex = 1 // My Network tab
        }
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
        
        // Mark that user has dismissed the overlay
        OnboardingManager.shared.disableSuggestedUsersOverlay()
        
        // Now check and show tutorial
        checkTutorialAndOverlay()
    }
    
    func didTapNext(selectedUsers: [User]) {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        
        // Show visit tracking permission if needed
        showVisitTrackingPermissionIfNeeded()
    }
    
    func didTapSkip() {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        
        // Show visit tracking permission if needed
        showVisitTrackingPermissionIfNeeded()
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

