import UIKit
import CoreLocation
import UniformTypeIdentifiers
import MapKit
import AVFoundation
import SafariServices

class CirclesHomeViewController: BaseViewController, PlaceSearchable, SSEServiceDelegate {
    
    // MARK: - State
    /// Loaded circles/places, the people/category selection and the search
    /// overlay's working set live in `HomeState` (pure, unit tested). The
    /// properties below forward to it so call sites read unchanged; the
    /// data loader (Phase 4 step 3) will write into the same instance.
    lazy var state: HomeState = {
        let state = HomeState()
        state.onUserOwnPlacesChanged = { [weak self] places in
            // Keep the embedded map informed so it can center on the user's favorites
            self?.mapViewController?.ownPlaceIds = Set(places.map { $0.id })
        }
        return state
    }()

    var circles: [Circle] { get { state.circles } set { state.circles = newValue } }
    var networkCircles: [Circle] { get { state.networkCircles } set { state.networkCircles = newValue } }
    var isShowingNetworkCircles: Bool { get { state.isShowingNetworkCircles } set { state.isShowingNetworkCircles = newValue } }
    var allPlaces: [Place] { get { state.allPlaces } set { state.allPlaces = newValue } }
    /// While isSearching, this is the SEARCH-RESULTS array the overlay table
    /// renders and indexes into. Map-refresh paths must never write it during
    /// a search (see mapRefreshDidFilter) — a background load swapping it
    /// under the visible rows made taps open the wrong place.
    var filteredPlaces: [Place] { get { state.filteredPlaces } set { state.filteredPlaces = newValue } }
    var isSearching: Bool { get { state.isSearching } set { state.isSearching = newValue } }
    /// User tapped Done/the map to drop the people/suggested dropdown — it
    /// stays down until they edit the query or refocus the bar.
    var isSearchOverlayDismissed: Bool { get { state.isSearchOverlayDismissed } set { state.isSearchOverlayDismissed = newValue } }
    var selectedCategory: UnifiedCategory? { get { state.selectedCategory } set { state.selectedCategory = newValue } }
    var mapUpdateTimer: Timer? // Debounce timer for map updates
    var notificationBadgeTimer: Timer? // Periodic refresh timer for notification badge
    var isReturningFromFullScreenMap = false // Prevent map updates when returning from full screen
    var isShowingLoadingUI = false // Track if loading UI is currently shown

    /// Fetch sequencing and the in-flight flags live in `HomeDataLoader`,
    /// which writes into `state` and calls back for presentation. The flags
    /// and `fetch*` methods below forward to it.
    lazy var loader: HomeDataLoader = {
        let loader = HomeDataLoader(state: state)
        loader.delegate = self
        return loader
    }()
    var isLoadingCircles: Bool { get { loader.isLoadingCircles } set { loader.isLoadingCircles = newValue } }
    var isLoadingPlaces: Bool { get { loader.isLoadingPlaces } set { loader.isLoadingPlaces = newValue } }
    var isPerformingInitialLoad: Bool { get { loader.isPerformingInitialLoad } set { loader.isPerformingInitialLoad = newValue } }
    /// Cross-instance: has ANY home instance loaded data this app session.
    static var hasLoadedInitialData: Bool { get { HomeDataLoader.hasLoadedInitialData } set { HomeDataLoader.hasLoadedInitialData = newValue } }
    var hasStartedLoading: Bool { get { loader.hasStartedLoading } set { loader.hasStartedLoading = newValue } }
    var isMapDataReady: Bool { get { loader.isMapDataReady } set { loader.isMapDataReady = newValue } }
    
    // MARK: - Place Detail Deduplication Properties
    var lastPresentedPlaceId: String?
    var lastPresentationTime: TimeInterval = 0
    let presentationDebounceInterval: TimeInterval = 1.0 // 1 second to prevent double-taps
    
    // MARK: - Enhanced Performance Properties
    var skeletonLoadingView: HomeScreenSkeletonView? // Progressive loading skeleton
    
    // Instance-based cache with expiry (rules in HomeState)
    var placesCacheExpiry: Date? { get { state.placesCacheExpiry } set { state.placesCacheExpiry = newValue } }
    var cachedPlaces: [Place] { get { state.cachedPlaces } set { state.cachedPlaces = newValue } }
    /// The user's own places only. Writes notify the embedded map (see `state`).
    var userOwnPlaces: [Place] { get { state.userOwnPlaces } set { state.userOwnPlaces = newValue } }
    
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
    var cacheExpiryMinutes: TimeInterval { state.cacheExpiryMinutes }
    var loadDebounceTimer: Timer? // Debounce timer to prevent rapid successive loads
    var preloadedData: PreloadedData? // Store preloaded data from splash screen
    var preloadedConnections: [Connection]? // Store preloaded connections for userListView
    var notificationBadgeLabel: UIView? // Unseen-notifications red dot on the bell
    var notificationBarButton: UIBarButtonItem? // Store reference to notification button
    var rewardsBadgeLabel: UILabel? // Badge label showing reward points balance
    var rewardsBarButton: UIBarButtonItem? // Store reference to rewards ($) button
    
    // Search scope properties
    var currentSearchScope: SearchScope { get { state.currentSearchScope } set { state.currentSearchScope = newValue } }
    var networkPlaces: [Place] { get { state.networkPlaces } set { state.networkPlaces = newValue } } // Cache for network places
    var isLoadingNetworkPlaces = false

    // Unified search: places (local, instant) + people (server, debounced).
    // People results are the PEOPLE section of the search overlay; tapping one
    // filters the map to a connection/followee, or opens a stranger's profile.
    var searchedUsers: [User] { get { state.searchedUsers } set { state.searchedUsers = newValue } }
    var userSearchWorkItem: DispatchWorkItem?
    // Search overlay distance/suggested state: distances (meters) keyed by
    // place id for the PLACES rows, plus the SUGGESTED fallback — global
    // venues fetched when the query matches nothing you or your network saved
    var searchDistances: [String: CLLocationDistance] { get { state.searchDistances } set { state.searchDistances = newValue } }
    var suggestedPlaces: [GlobalPlace] { get { state.suggestedPlaces } set { state.suggestedPlaces = newValue } }
    var suggestedDistances: [String: CLLocationDistance] { get { state.suggestedDistances } set { state.suggestedDistances = newValue } }
    var suggestedSearchWorkItem: DispatchWorkItem?

    // MARK: - Viewport-Based Network Place Loading
    // Guards the disk-cache paint so it happens at most once per instance
    var hasPaintedPlacesFromDiskCache: Bool { get { state.hasPaintedPlacesFromDiskCache } set { state.hasPaintedPlacesFromDiskCache = newValue } }
    var fetchedViewportCircles: [(center: CLLocationCoordinate2D, radiusM: Double)] { get { state.fetchedViewportCircles } set { state.fetchedViewportCircles = newValue } }
    var isFetchingViewport: Bool { get { loader.isFetchingViewport } set { loader.isFetchingViewport = newValue } }
    // Connections whose FULL place set has been loaded (not viewport-bounded),
    // so the All Connections prefetch doesn't refetch on every selection
    var prefetchedConnectionIds: Set<String> { get { state.prefetchedConnectionIds } set { state.prefetchedConnectionIds = newValue } }
    
    // Suggested users overlay
    var suggestedUsersOverlay: SuggestedUsersOverlayView?
    var visitTrackingPermissionOverlay: VisitTrackingPermissionView?
    var addPlaceTutorialOverlay: AddFirstPlaceTutorialView?
    
    // Welcome tour tracking
    var isShowingWelcomeTour = false
    
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
        // Home row tops itself up with suggested people + a "Find People +"
        // cell when sparse (the modal map's copy of this row stays filter-only)
        view.showsDiscoverySuffix = true
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
        // Half-sheet look: rounded top corners where it meets the map above it
        tableView.layer.cornerRadius = 16
        tableView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tableView.clipsToBounds = true
        // The sheet now sits BELOW the floating filter chips (they stay over the
        // map's top half), so the list only needs a little breathing room on top.
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        tableView.register(QuickAccessPlaceCell.self, forCellReuseIdentifier: "HomePlaceListCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    var isShowingPlacesList = false
    // One entry per real-world venue (deduped across savers). `savedBy` holds
    // the saver display names ("You" first) for the "Saved by …" subtitle.
    var distanceSortedPlaces: [(place: Place, distance: CLLocationDistance?, savedBy: [String])] = []
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

    // Default "Everyone" (nil): the map opens scoped to your network —
    // yourself, your accepted connections, and everyone you follow — so a brand
    // new user still lands on a map with pins (they auto-follow from day one).
    // "My Places" / "My Connections" / a specific person are all one tap away in
    // the Connection dropdown.
    var selectedConnectionId: String? { get { state.selectedConnectionId } set { state.selectedConnectionId = newValue } }
    var selectedConnectionUser: User? { get { state.selectedConnectionUser } set { state.selectedConnectionUser = newValue } } // Set only when a specific connection is filtered

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
        // "My Places" is a filter like any other person, so it wears YOUR face
        // in the same chip — the map always names whose places are on it.
        let user: User?
        if selectedConnectionId == "my_places_only" {
            user = AuthService.shared.currentUser
        } else if selectedConnectionId != nil {
            user = selectedConnectionUser
        } else {
            user = nil // All Connections: nobody in particular to show
        }

        guard let user = user else {
            selectedConnectionAvatarButton.isHidden = true
            return
        }
        selectedConnectionAvatarButton.isHidden = false
        selectedConnectionAvatarButton.setImage(UIImage(systemName: "person.crop.circle.fill"), for: .normal)
        selectedConnectionAvatarButton.accessibilityLabel =
            selectedConnectionId == "my_places_only" ? "Your places" : "Selected connection"
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            let expectedUserId = user.id
            ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: "profile_\(user.id)_\(profilePicture)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, let image = image,
                          self.avatarChipUser?.id == expectedUserId else { return }
                    self.selectedConnectionAvatarButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                }
            }
        }
    }

    /// Whoever the avatar chip currently represents — the selected connection,
    /// or you when the map is scoped to your own places.
    private var avatarChipUser: User? {
        selectedConnectionId == "my_places_only" ? AuthService.shared.currentUser : selectedConnectionUser
    }

    @objc func selectedConnectionAvatarTapped() {
        guard let user = avatarChipUser else { return }
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
    
    var availableCategories: [UnifiedCategory] { get { state.availableCategories } set { state.availableCategories = newValue } }
    var mapHeightConstraint: NSLayoutConstraint?
    
    // Search scope dropdown properties
    var isSearchScopeDropdownOpen = false
    var searchScopeDropdownHeightConstraint: NSLayoutConstraint?
    
    // Activity tab (child); `activities` forwards for the loader/preload/blocked-user paths
    lazy var activityTab: HomeActivityFeedViewController = {
        let tab = HomeActivityFeedViewController()
        tab.host = self
        return tab
    }()
    var activities: [Activity] { get { activityTab.activities } set { activityTab.activities = newValue } }
    var contentTabHeightConstraint: NSLayoutConstraint?
    
    // Daily Summary Properties
    var dailySummaryCard: DailySummaryCardView?
    var hasDailySummaryData = false
    
    // Moments tab (child); `reels` forwards for the loader/preload/blocked-user paths
    lazy var momentsTab: HomeMomentsViewController = {
        let tab = HomeMomentsViewController()
        tab.host = self
        return tab
    }()
    var reels: [PlaceVideo] { get { momentsTab.reels } set { momentsTab.reels = newValue } }
    
    // Suggested Users Overlay
    var hasCheckedForSuggestedUsers = false
    var hasCheckedTutorialAndOverlay = false
    var tutorialCheckRetryCount = 0
    let maxTutorialCheckRetries = 3
    
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
    
    // MARK: - Content tabs
    // The segment bar switches between child view controllers whose views
    // fill `tabContentContainer` (see HomeContentTab). Activity and Moments
    // are still inline below; Specials is the first extracted tab.
    let tabContentContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var specialsTab: HomeSpecialsViewController = {
        let tab = HomeSpecialsViewController()
        tab.host = self
        return tab
    }()

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
        
        // Store cached places but don't display them yet
        // Wait for circles to load before displaying any places to ensure consistency
        if !cachedPlaces.isEmpty {
            Logger.debug("🟡 Found cached places: \(cachedPlaces.count) - storing for later display")
            self.allPlaces = cachedPlaces
            // Note: userOwnPlaces will be populated later when circles are loaded
        }
        // Don't show loading state here - performInitialDataLoad will handle it
        
        // Don't fetch circles here - it will be called in viewWillAppear
        
        // Start background image preloading for better performance
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
    
    // MARK: - Background Image Preloading
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
        
        ImageService.shared.preloadImages(from: uniqueUrls) { loadedCount in
            Logger.debug("🖼️ [BackgroundPreload] Completed: \(loadedCount)/\(uniqueUrls.count) place images cached")
        }
    }
    
    // MARK: - Optional Skeleton Loading
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
        tabContentContainer.alpha = 0.3
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
            self.tabContentContainer.alpha = 1.0
            self.userListView.alpha = 1.0
        })
        
        hideSkeletonLoading(skeleton)
        skeletonLoadingView = nil
    }
    
    // MARK: - Lifecycle (continued)
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Logger.debug("🟢 CirclesHomeViewController viewWillAppear called")
        Logger.debug("🟢 Instance: \(ObjectIdentifier(self))")
        Logger.debug("   hasStartedLoading: \(hasStartedLoading)")
        Logger.debug("   isReturningFromFullScreenMap: \(isReturningFromFullScreenMap)")
        Logger.debug("   circles.count: \(circles.count)")
        Logger.debug("   allPlaces.count: \(allPlaces.count)")
        Logger.debug("   preloadedData: \(preloadedData != nil)")
        
        // The avatar chip may have been built before your profile finished
        // loading (nil photo → generic glyph); this picks up the real one.
        updateSelectedConnectionAvatar()

        // Instant pins — paint the last session's complete place set
        // from disk while the network refresh (below) is in flight
        paintPlacesFromDiskCacheIfEmpty()

        // Optional skeleton loading - only for slow connections
        scheduleOptionalSkeletonLoading()

        // (Removed: tryFastAPIAsAlternative — it fetched home/homescreen on
        // every appearance and discarded the result on the normal launch
        // paths; the endpoints below load the same data.)

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
        
        // The content segment survives navigation: coming back from a place
        // page (or any push/modal) lands on the tab you left. Only the
        // tab-bar Home re-tap resets to Activity (resetContentTabToActivity).
        // A moment that was paused on the way out resumes.
        momentsTab.resumePlaybackIfVisible()

        // If the map was left in list view, flip it back to the map (filters
        // are intentionally preserved across a tab switch — the Home re-tap
        // clears those via resetMapToDefault).
        resetPlacesListToMap()
        
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

        // Start immediately — the old 0.3s debounce timer added flat latency
        // to every no-preload launch (viewWillAppear runs once on this path;
        // hasStartedLoading above already guards re-entry).
        Logger.debug("🟢 Starting initial data load")
        performInitialDataLoad()

        // Don't show filter stack here - let hideMapLoadingState handle it
        // This prevents the filter from showing then hiding again
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Check if onboarding needs to be retried
        checkAndRetryOnboardingIfNeeded()

        // Surface the sign-in-time duplicate-account hint (once per login)
        promptForDuplicateAccountsIfNeeded()

        // "At Beach Haus? Check in" — one-tap check-in when opening the app
        // at a saved place (CirclesHomeViewController+ProximityCheckIn)
        maybeShowProximityCheckInChip()

        // New accounts: the first-session chain (SceneDelegate) normally
        // presents the first-people sheet; this is the fallback for launches
        // where the chain isn't running (e.g. killed the app between the
        // carousel and the sheet — account still <48h, sheet not yet seen).
        if presentedViewController == nil && !OnboardingManager.shared.isFirstSessionFlowActive {
            if !WelcomeConnectionsViewController.presentIfNeeded(from: self) {
                // Old accounts instead get the one-time legacy-privacy nudge
                promptLegacyCirclePrivacyIfNeeded()
            }
        }
        
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
        // While the first-session chain's modals are up, defer — the chain
        // calls this as its terminal step. Returning WITHOUT burning the
        // once-per-session flag is the point.
        guard !OnboardingManager.shared.isFirstSessionFlowActive else {
            Logger.debug("⏸ First-session chain active — tutorial check deferred to chain end")
            return
        }

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

            // Kick off the 4-step home tour after a brief delay for UI to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.runHomeTourWhenSettled()
            }
        }
    }

    /// The first bubble must not fight the system location dialog or a chain
    /// modal still animating out — wait until both are gone, then start.
    private func runHomeTourWhenSettled(attempt: Int = 0) {
        guard OnboardingManager.shared.shouldShowTutorial,
              TutorialStep.allCases.contains(where: { !OnboardingManager.shared.hasCompletedStep($0) }) else { return }
        let blockedByLocation = CLLocationManager().authorizationStatus == .notDetermined
        let blockedByModal = presentedViewController != nil
        if (blockedByLocation || blockedByModal) && attempt < 30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runHomeTourWhenSettled(attempt: attempt + 1)
            }
            return
        }
        runHomeTour()
    }

    /// The home tour: shows the first incomplete step; each Next completes the
    /// step and calls back here, so the four bubbles chain until done (the
    /// last completeStep fires completeOnboarding automatically). Skip on any
    /// bubble ends the whole tour.
    func runHomeTour() {
        guard OnboardingManager.shared.shouldShowTutorial else { return }
        guard let step = TutorialStep.allCases.first(where: { !OnboardingManager.shared.hasCompletedStep($0) }) else { return }

        let advance: () -> Void = { [weak self] in
            // Small beat between bubbles so the dismiss/present don't overlap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.runHomeTour()
            }
        }

        switch step {
        case .addPlaces:
            // Button sits at the screen top — bubble goes BELOW it (arrow .top);
            // above it would clamp over the status bar, unreadable
            scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                // A modal may have appeared during the settle delay — never
                // show a bubble underneath one (stray taps hit its buttons)
                guard self.presentedViewController == nil else {
                    self.runHomeTourWhenSettled()
                    return
                }
                OnboardingManager.shared.showTutorialStep(
                    .addPlaces, targetView: self.quickAddPlaceButton, in: self,
                    arrowDirection: .top, onAdvance: advance)
            }
        case .followUsers:
            scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                // A modal may have appeared during the settle delay — never
                // show a bubble underneath one (stray taps hit its buttons)
                guard self.presentedViewController == nil else {
                    self.runHomeTourWhenSettled()
                    return
                }
                OnboardingManager.shared.showTutorialStep(
                    .followUsers, targetView: self.userListView, in: self,
                    arrowDirection: .top, onAdvance: advance)
            }
        case .viewActivity:
            // The activity segment can sit below the fold on small phones —
            // reveal it first, then point (bubble above it, arrow .bottom)
            let target = contentSegmentedControl.convert(contentSegmentedControl.bounds, to: scrollView)
                .insetBy(dx: 0, dy: -80)
            scrollView.scrollRectToVisible(target, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self = self else { return }
                // A modal may have appeared during the settle delay — never
                // show a bubble underneath one (stray taps hit its buttons)
                guard self.presentedViewController == nil else {
                    self.runHomeTourWhenSettled()
                    return
                }
                OnboardingManager.shared.showTutorialStep(
                    .viewActivity, targetView: self.contentSegmentedControl, in: self,
                    arrowDirection: .bottom, onAdvance: advance)
            }
        case .seeRewards:
            // Nav-bar $ button — scroll position is irrelevant, but return to
            // the top so the tour ends where the session starts
            scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
            let rewardsView = rewardsBarButton?.customView
                ?? (rewardsBarButton?.value(forKey: "view") as? UIView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                // A modal may have appeared during the settle delay — never
                // show a bubble underneath one (stray taps hit its buttons)
                guard self.presentedViewController == nil else {
                    self.runHomeTourWhenSettled()
                    return
                }
                OnboardingManager.shared.showTutorialStep(
                    .seeRewards, targetView: rewardsView, in: self,
                    arrowDirection: .top, onAdvance: advance)
            }
        }
    }
    
    /// Hand-off from the suggested-users overlay: the tutorial check's
    /// once-per-session latch is already burned by the time the overlay
    /// dismisses, so the tour must be started explicitly here.
    func startHomeTourIfNeededAfterOverlay() {
        OnboardingManager.shared.checkIfUserNeedsTutorial { [weak self] needsTutorial in
            guard let self = self else { return }
            if needsTutorial {
                OnboardingManager.shared.startTutorial()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.runHomeTourWhenSettled()
                }
            } else {
                self.showAddPlaceTutorialIfNeeded()
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
        // The home tour's first bubble already teaches Add Place — don't
        // double-teach while the tour still has steps to show
        let tourPending = OnboardingManager.shared.shouldShowTutorial &&
            TutorialStep.allCases.contains { !OnboardingManager.shared.hasCompletedStep($0) }
        guard !tourPending else { return }

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
        
        // The notification bell's badge is attached in makeRightBarButtons(),
        // once notificationBarButton actually exists.

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
        // Avatar first so "who is being mapped" reads before the controls
        // The hamburger and Me chips are gone for good — the dropdown header
        // covers everything they did (connection switching, category
        // filtering, Me scoping). Only the selected-connection avatar remains
        // in this row, and only while a specific connection is chosen.
        filterStackView.addArrangedSubview(selectedConnectionAvatarButton)
        contentView.addSubview(listToggleButton)
        listToggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listToggleButton.topAnchor.constraint(equalTo: mapExpandButton.bottomAnchor, constant: 8),
            listToggleButton.trailingAnchor.constraint(equalTo: mapExpandButton.trailingAnchor),
            listToggleButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        contentView.addSubview(emptyStateView)
        
        // Add activity feed section
        contentView.addSubview(activityFeedSection)
        activityFeedSection.addSubview(activityHeaderLabel)
        activityFeedSection.addSubview(contentSegmentedControl)
        activityFeedSection.addSubview(momentsCameraButton)
        activityFeedSection.addSubview(tabContentContainer)
        embedContentTabs()
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
            // Below the dropdown header row (8 + 40 + 8)
            filterContainer.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: 56),
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
            // Same row as the ☰/Me chips, below the dropdown header
            mapExpandButton.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: 56),
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

            // Half-sheet: the list covers the bottom ~55% of the map area so the
            // map stays visible and pannable above it. listToggleTapped grows the
            // map container in list mode so both the map slice and list have room.
            placesListTableView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            placesListTableView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            placesListTableView.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor),
            placesListTableView.heightAnchor.constraint(equalTo: mapContainerView.heightAnchor, multiplier: 0.55),

            // Location status label
            
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
            
            // Content tabs (same slot as the inline content views)
            tabContentContainer.topAnchor.constraint(equalTo: contentSegmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            tabContentContainer.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor),
            tabContentContainer.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor),
            tabContentContainer.bottomAnchor.constraint(equalTo: activityFeedSection.bottomAnchor),

            // Floating record button - positioned at top left
            floatingRecordButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            floatingRecordButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            floatingRecordButton.widthAnchor.constraint(equalToConstant: 56),
            floatingRecordButton.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        // Create height constraints - reduced for iPhone 16 Pro to show more activity content
        mapHeightConstraint = mapContainerView.heightAnchor.constraint(equalToConstant: 320)
        mapHeightConstraint?.isActive = true
        
        // The content area is a fixed 600pt; the tabs scroll inside it. This
        // one constraint sizes the whole activity section.
        contentTabHeightConstraint = tabContentContainer.heightAnchor.constraint(equalToConstant: 600)
        contentTabHeightConstraint?.isActive = true
        
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
        // Same category + state chips as the profile map, so the two maps
        // filter identically. The hamburger's Category submenu is gone — the
        // chips are its replacement, always visible instead of two taps deep.
        mapVC.showsFilterChips = true
        // The dropdown header is the only control at the map's top now — the
        // old overlay row is retired, so no clearance needed.
        mapVC.embeddedChipsTopInset = 8
        // Seed the Connection dropdown's roster and its current selection.
        mapVC.setAvailableConnections(NetworkManager.shared.connections)
        mapVC.setConnectionSelection(id: selectedConnectionId, user: selectedConnectionUser)
        NotificationCenter.default.addObserver(
            forName: .connectionsLoaded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.mapViewController?.setAvailableConnections(NetworkManager.shared.connections)
        }
        
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
        
        // Ensure the overlay controls stay above the map child
        contentView.bringSubviewToFront(filterContainer)
        contentView.bringSubviewToFront(mapExpandButton)
        contentView.bringSubviewToFront(listToggleButton)
        contentView.bringSubviewToFront(mapPlaceCountLabel)

        // Show the chip for the launch selection (My Places = your own face).
        // Previously only selectConnection() refreshed it, so the default scope
        // showed no avatar at all until you picked someone from the dropdown.
        // viewWillAppear re-runs this once your profile has actually loaded.
        updateSelectedConnectionAvatar()
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
    
    func isCacheValid() -> Bool { state.isCacheValid }
    
    func invalidateCache() {
        state.invalidateCache()
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
        
        // Preloaded places are incomplete (the splash deliberately skips them),
        // so a full fetch below still REPLACES everything. But instead of
        // clearing to an empty map while that runs, paint the last session's
        // complete set from disk (stale-while-revalidate).
        paintPlacesFromDiskCacheIfEmpty()

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
            
            // Default filter: Everyone (nil) — matches the property default and
            // the dropdown header; the expanded map inherits whatever is set
            // here, so home and modal always open on the same scope.
            self.selectedConnectionId = nil
            self.selectedConnectionUser = nil
            self.mapViewController?.setConnectionSelection(id: nil, user: nil)

            // Don't mark as ready - we need to fetch places
            self.isMapDataReady = false
            
            // Apply filters and update map
            // Don't update map yet - we need to fetch all places first
            
            // Update empty state visibility
            self.updateEmptyState()
            
            // Reload activity and moments UI if we have data
            if !self.activities.isEmpty {
                self.activityTab.showLoadedActivities()
            }
            
            if !self.reels.isEmpty {
                self.momentsTab.collectionView.reloadData()
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
            activityTab.refreshTab()
        case 1:
            momentsTab.refreshTab()
        default:
            specialsTab.refreshTab()
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
            // Show Activity feed (loads if empty)
            momentsTab.setTabVisible(false) // pauses any playing moment
            specialsTab.setTabVisible(false)
            momentsCameraButton.isHidden = true
            activityHeaderLabel.text = "Recent Activity"
            activityTab.setTabVisible(true)
        case 1:
            // Show Moments feed; the tab resets to the first video, refreshes
            // and autoplays once loaded
            activityTab.setTabVisible(false)
            specialsTab.setTabVisible(false)
            momentsCameraButton.isHidden = false
            activityHeaderLabel.text = "Moments"
            momentsTab.setTabVisible(true)
        default:
            // Show Specials (live offers + announcements from participating venues)
            activityTab.setTabVisible(false)
            momentsTab.setTabVisible(false) // pauses any playing moment
            momentsCameraButton.isHidden = true
            activityHeaderLabel.text = "Specials"
            specialsTab.setTabVisible(true)
        }
    }

    // MARK: - Content tab hosting

    /// Adds the extracted tabs as child view controllers filling
    /// `tabContentContainer`. Every tab starts hidden; the segment switch
    /// (`contentSegmentChanged`) shows the selected one.
    func embedContentTabs() {
        for tab in [activityTab, momentsTab, specialsTab] as [UIViewController & HomeContentTab] {
            addChild(tab)
            tab.view.translatesAutoresizingMaskIntoConstraints = false
            tab.view.isHidden = true
            tabContentContainer.addSubview(tab.view)
            NSLayoutConstraint.activate([
                tab.view.topAnchor.constraint(equalTo: tabContentContainer.topAnchor),
                tab.view.leadingAnchor.constraint(equalTo: tabContentContainer.leadingAnchor),
                tab.view.trailingAnchor.constraint(equalTo: tabContentContainer.trailingAnchor),
                tab.view.bottomAnchor.constraint(equalTo: tabContentContainer.bottomAnchor)
            ])
            tab.didMove(toParent: self)
        }
        // Activity is the default segment. Mark it active directly (not via
        // setTabVisible) so it doesn't fetch here — the initial load brings
        // the feed — but does react to that load as the visible tab.
        activityTab.isActiveTab = true
        activityTab.view.isHidden = false
    }

    // MARK: - Activity feed (forwarded to the Activity tab)
    func fetchActivities(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        activityTab.fetchActivities(loadMore: loadMore, completion: completion)
    }

    func updateActivityFeed() {
        activityTab.updateActivityFeed()
    }

    /// SSE: merge just the newest activities so scroll position survives.
    func refreshActivityFeedWithNewItem() {
        activityTab.refreshWithNewItems()
    }

    /// Deep link / notification tap: open a moment in the inline Moments tab.
    func navigateToVideo(withId videoId: String) {
        activityTab.navigateToVideo(withId: videoId, showsLoading: true)
    }

    // MARK: - Moments (forwarded to the Moments tab)
    func fetchReels(loadMore: Bool = false, completion: ((Bool) -> Void)? = nil) {
        momentsTab.fetchReels(loadMore: loadMore, completion: completion)
    }

    /// Stops any playing moment and hands the audio session back.
    func pauseAllVideos() {
        momentsTab.pauseAllVideos()
    }

    /// Switch the home content to the Moments tab and land on a specific moment.
    /// Used when a moment activity (or its thumbnail) is tapped: instead of a
    /// modal player, drop the user into the inline Moments feed positioned on
    /// that moment. Setting selectedSegmentIndex in code does not fire
    /// .valueChanged, so this mirrors contentSegmentChanged's Moments case —
    /// minus its refresh, since present(moment:) loads the feed itself.
    func openMomentInMomentsTab(_ video: PlaceVideo) {
        contentSegmentedControl.selectedSegmentIndex = 1
        activityTab.setTabVisible(false)
        specialsTab.setTabVisible(false)
        momentsCameraButton.isHidden = false
        activityHeaderLabel.text = "Moments"
        momentsTab.present(moment: video)
    }

    // MARK: - Data Fetching (forwarded to HomeDataLoader)
    func performInitialDataLoad() { loader.performInitialDataLoad() }
    
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
            self.allPlaces = removeDuplicatePlaces(places + self.allPlaces)
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
        let placesToDisplay = applyFiltersToPlaces(!isFromCache ? allPlaces : places)
        mapRefreshDidFilter(placesToDisplay)

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
    
    func fetchCircles(completion: (() -> Void)? = nil) { loader.fetchCircles(completion: completion) }
    
    func fetchNetworkCircles(completion: (() -> Void)? = nil) { loader.fetchNetworkCircles(completion: completion) }
    
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
    
    func paintPlacesFromDiskCacheIfEmpty() { loader.paintPlacesFromDiskCacheIfEmpty() }

    func fetchAllPlacesFromCircles() { loader.fetchAllPlacesFromCircles() }
    
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
        // Retired. The embedded map now draws its own pill, counting pins in
        // the CURRENT viewport after every filter — including the chip filters
        // this label never knew about. Two stacked pills with different
        // numbers was the original "always 257" bug; this one bows out.
        DispatchQueue.main.async { [weak self] in
            self?.mapPlaceCountLabel.isHidden = true
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

        // NOTE: the "Browse by Location" nav button was removed — the map's own
        // filter header (Me · Category · Place, with states/countries) covers
        // that need in-place. LocationBrowseViewController and the /api/browse
        // endpoints remain available (browseByLocationTapped still works) if a
        // surface wants them again.
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
            image: .checkInIcon,
            style: .plain,
            target: self,
            action: #selector(checkInButtonTapped)
        )
        checkInButton.accessibilityLabel = "Check in"

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
        // Attach the unseen-dot custom view now that the bar button exists, then
        // refresh its visibility from the server count.
        setupNotificationBadge()
        updateNotificationBadge()

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

        // Clear the bell's unseen dot as soon as the Notifications screen marks
        // everything read (see .notificationsMarkedRead)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationsMarkedRead),
            name: .notificationsMarkedRead,
            object: nil
        )

        // Premium resolves after launch (StoreKit, then backend sync). Without
        // this the nav bar keeps whatever it was built with, so a premium user
        // saw the upgrade crown until a tab switch happened to rebuild it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubscriptionStatusChanged),
            name: .subscriptionStatusChanged,
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

        // Your OWN place-add isn't echoed back to you over SSE (that only goes
        // to your connections/followers), so the activity feed used to stay
        // stale until a manual refresh. AddPlaceViewController posts this when
        // a place is saved to a circle — refresh the feed to show your own add.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaceAddedToActivityFeed),
            name: Notification.Name("PlaceAddedToCircle"),
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
        
        // A block anywhere in the app must scrub that user from the home
        // feeds immediately — the server filters on the next fetch, so just
        // refetch
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserBlocked(_:)),
            name: .userBlocked,
            object: nil
        )
    }

    @objc func handleUserBlocked(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let blockedId = notification.userInfo?["userId"] as? String {
                // Drop their content locally right away, then refetch for truth
                self.momentsTab.removeReels(by: blockedId)
                self.activityTab.removeActivities(by: blockedId)
            }
            self.fetchActivities()
            self.fetchReels()
        }
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
    
    @objc func handleShowOnboardingTour(_ notification: Notification) {
        // Called when user taps "Show Welcome Tour" from Help view — replays
        // the 4-bubble home tour (local reset only; the server's
        // hasCompletedTutorial stays true so fresh launches don't re-run it)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Make sure we're on the Home tab
            if let tabBar = self.tabBarController {
                tabBar.selectedIndex = 0
            }

            OnboardingManager.shared.resetTutorial()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.runHomeTour()
            }
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
            places: excludingHiddenCircles(allPlaces),
            initialRegion: mapViewController?.currentRegion,
            selectedCategory: selectedCategory,  // Pass current category filter
            selectedConnectionId: selectedConnectionId  // Pass current connection filter
        )
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.selectedConnectionUser = selectedConnectionUser
        fullScreenMap.delegate = self  // Set delegate to handle place selection

        // Same dropdown filter header as the embedded map — expansion is the
        // same map, larger, so it carries the exact filters you were viewing.
        // (Without this flag the modal fell back to the legacy hamburger UI:
        // the expand path builds a NEW instance, it doesn't reuse the embed.)
        fullScreenMap.showsFilterChips = true
        fullScreenMap.initialChipGroup = mapViewController?.currentChipGroup ?? .all
        fullScreenMap.initialChipRegionId = mapViewController?.currentChipRegionId
        // Expansion is the same map, larger — carry the active search text too
        fullScreenMap.initialSearchQuery = activeSearchQuery
        
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

    /// Present the expanded map scoped to the user's OWN places, zoomed out to
    /// fit them all — their whole "world," or just their region if they only
    /// save locally (the fit-to-bounds math adapts automatically). Entry point
    /// for the "see all your favorite places in one view" engagement tip.
    /// Unlike `presentFullScreenMapWithCurrentState`, this passes NO initial
    /// region (so auto-zoom is allowed) and forces the fit even for My Places.
    func presentFullScreenMapShowingAllMyPlaces(focusCategory: UnifiedCategory? = nil) {
        isReturningFromFullScreenMap = true

        let fullScreenMap = FullScreenMapViewController(
            places: excludingHiddenCircles(allPlaces),
            initialRegion: nil,                     // allow fit-all zoom on load
            selectedCategory: focusCategory,
            selectedConnectionId: "my_places_only"
        )
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.selectedConnectionUser = nil
        fullScreenMap.delegate = self
        fullScreenMap.showsFilterChips = true
        fullScreenMap.fitAllPlacesOnLoad = true     // fit even for my_places_only

        let buckets = buildConnectionPlaceBuckets()
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
        // Jump to My Network — it opens on Discover, which is exactly the
        // "find friends" surface. (The phone-contacts import flow is gone.)
        tabBarController?.selectedIndex = 1
    }

    @objc func handleQuickStartPlaceAdded() {
        // Debounced full refetch (places were added outside the normal flow)
        updateMapPlaces()
    }

    /// Refresh the activity feed after the user adds a place so their own
    /// activity shows without a manual refresh. The server writes the activity
    /// just AFTER the create response returns (fire-and-forget trackPlaceAdded),
    /// so refetch on a short delay to avoid racing the write. fetchActivities
    /// already includes the user's own activity, so this works whether or not
    /// the Activity segment is currently showing.
    @objc func handlePlaceAddedToActivityFeed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.fetchActivities()
        }
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
        // Present circles in the user's own order (same as the profile grid).
        let pickerCircles = circles
        
        let circlePickerVC = CirclePickerViewController(circles: pickerCircles)
        circlePickerVC.onCircleSelected = { [weak self] circle in
            let addPlaceVC = AddPlaceViewController(circleId: circle.id, circles: pickerCircles)
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
    
    /// Own places win over network copies of the same id (rules in HomeState).
    func deduplicatePlaces(userPlaces: [Place], networkPlaces: [Place]) -> [Place] {
        let merged = HomeState.merge(userPlaces: userPlaces, networkPlaces: networkPlaces)
        Logger.debug("📍 Deduplication summary: \(userPlaces.count) user + \(networkPlaces.count) network = \(merged.count) unique places")
        return merged
    }
    
    /// First occurrence of each place id wins (rules in HomeState). No
    /// per-place logging — this runs on the main thread on every place merge.
    func removeDuplicatePlaces(_ places: [Place]) -> [Place] {
        let deduplicated = HomeState.dedupe(places)
        if deduplicated.count < places.count {
            Logger.debug("⚠️ Removed \(places.count - deduplicated.count) duplicate places (\(places.count) → \(deduplicated.count))")
        }
        return deduplicated
    }
    
    func fetchNetworkPlacesAndCombineWithCached() {
        // Network places arrive per visible map region (viewport loading), so
        // only the cached own-places need separating here.
        DispatchQueue.main.async { [weak self] in
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
            let allPlaces = self.deduplicatePlaces(userPlaces: self.cachedPlaces, networkPlaces: [])
            Logger.debug("📍 Cached places: \(self.cachedPlaces.count) → \(allPlaces.count) after deduplication")
            Logger.debug("📍 User's own places: \(self.userOwnPlaces.count)")
            
            self.allPlaces = allPlaces
            self.applyFiltersAndUpdateMap()
        }
    }
    
    /// Map-refresh paths report their freshly filtered set here. When idle it
    /// mirrors into filteredPlaces (legacy "UI consistency" for empty states);
    /// during a search it must NOT — filteredPlaces is then the search-results
    /// array the overlay table is rendering AND indexing into, and overwriting
    /// it mid-search made a tap open whatever place happened to share the row
    /// number in the map's array.
    func mapRefreshDidFilter(_ places: [Place]) {
        if !isSearching {
            filteredPlaces = places
        }
    }

    func applyFiltersAndUpdateMap() {
        // Apply filtering to all places
        let filteredPlaces = applyFiltersToPlaces(allPlaces)
        mapRefreshDidFilter(filteredPlaces)

        // Mark data as ready and update map
        isMapDataReady = true
        updateMapWhenReady()
        
        // Clean up loading states
        isLoadingPlaces = false
        hideLoadingState()
    }
    
    /// Drops places whose owning circle is known locally and has been hidden
    /// from the home map (showOnMap == false). Places whose circle isn't
    /// loaded locally pass through — the server already excludes hidden
    /// circles from network viewport results.
    func excludingHiddenCircles(_ places: [Place]) -> [Place] {
        state.excludingHiddenCircles(places)
    }

    /// Everything `HomePlaceFilter` needs, read once per filter pass: the
    /// state's selection + circles, plus who counts as "everyone" from the
    /// auth/network services.
    func placeFilterContext() -> HomePlaceFilter.Context {
        state.placeFilterContext(currentUserId: AuthService.shared.getUserId() ?? "",
                                 acceptedConnectionUserIds: acceptedConnectionUserIds,
                                 everyoneAuthorIds: everyoneAuthorIds)
    }

    /// People selection + category chip scoping. Rules live in `HomePlaceFilter`
    /// (unit tested); this just supplies the current state.
    func applyFiltersToPlaces(_ places: [Place]) -> [Place] {
        let context = placeFilterContext()
        let filtered = HomePlaceFilter.apply(places, context: context)
        Logger.debug("📍 Filter (\(context.selectedConnectionId ?? "everyone"), \(context.selectedCategory.map { "\($0)" } ?? "all categories")) → \(filtered.count)/\(places.count) places")
        return filtered
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
        state.connectionPlaceBuckets(currentUserId: AuthService.shared.getUserId() ?? "",
                                     connectionUserIds: acceptedConnectionUserIds)
    }

    /// One-time nudge for accounts created before the all-public default
    /// (Jul 2026): their starter circles are myNetwork/private, which makes
    /// their places invisible to non-connections — owners read that as "the
    /// app lost my places" (launch-night confusion, 2026-08-15). Offers to
    /// open the starter circles up; never changes anything silently.
    func promptLegacyCirclePrivacyIfNeeded() {
        guard let userId = AuthService.shared.getUserId() else { return }
        let seenKey = "legacyPrivacyNudgeShown_\(userId)"
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }

        let defaultNames: Set<String> = ["Favorite Local Spots", "Want to Try", "Vacation"]
        let nonPublicDefaults = circles.filter {
            IDNormalizer.isSameUser($0.owner, userId) &&
            defaultNames.contains($0.name) &&
            $0.privacy != .public
        }
        // Only nudge accounts from the pre-public era — someone who chose
        // privacy recently chose it on purpose
        guard !nonPublicDefaults.isEmpty,
              let created = AuthService.shared.currentUser?.createdAt,
              created < ISO8601DateFormatter().date(from: "2026-07-23T00:00:00Z") ?? .distantPast else { return }

        UserDefaults.standard.set(true, forKey: seenKey)
        AlertPresenter.showConfirmation(
            title: "Let friends see your places?",
            message: "Your starter circles (\(nonPublicDefaults.map { $0.name }.joined(separator: ", "))) are currently visible only to your network. Newer accounts start public — want yours public too, so friends can find your places?",
            confirmTitle: "Make Public",
            cancelTitle: "Keep As Is",
            from: self,
            onConfirm: { [weak self] in
                let group = DispatchGroup()
                for circle in nonPublicDefaults {
                    group.enter()
                    CircleService.shared.updateCircle(id: circle.id, privacy: .public) { _ in group.leave() }
                }
                group.notify(queue: .main) {
                    self?.showSuccess("Your circles are now public")
                    self?.loadData()
                }
            }
        )
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
            modal.updatePlaces(excludingHiddenCircles(allPlaces), adjustRegion: modalShouldZoom)
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

    /// Viewport-based network place loading; see `HomeDataLoader.fetchViewportPlaces`.
    func fetchViewportPlaces(region: MKCoordinateRegion, for controller: FullScreenMapViewController) {
        loader.fetchViewportPlaces(region: region, for: controller)
    }

    // MARK: - Per-connection place loading (fetches forwarded to HomeDataLoader)

    /// The connection (as tapped) whose places are still loading, if any. Both
    /// maps hold their "no places" banner while this is set.
    private var pendingConnectionFetchId: String?

    private func setConnectionFetchPending(_ connectionId: String?) {
        pendingConnectionFetchId = connectionId
        let pending = connectionId != nil
        mapViewController?.isConnectionFetchPending = pending
        presentedFullScreenMap?.isConnectionFetchPending = pending
    }

    /// Clears the pending flag if `connectionId` is still the one being waited on
    /// (a later tap on someone else keeps its own fetch pending).
    func finishConnectionFetch(_ connectionId: String) {
        guard pendingConnectionFetchId == connectionId else { return }
        setConnectionFetchPending(nil)
    }

    func fetchAllPlacesForConnection(_ connectionId: String) { loader.fetchAllPlacesForConnection(connectionId) }

    func prefetchAllConnectionPlaces() { loader.prefetchAllConnectionPlaces() }

    func fetchPlacesForConnectionCircles(_ connectionCircles: [Circle], for connectionId: String) {
        loader.fetchPlacesForConnectionCircles(connectionCircles, for: connectionId)
    }
    
    
    func buildMapMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        // Connection filter submenu
        let currentUserId = AuthService.shared.getUserId() ?? ""
        var connectionActions: [UIAction] = [
            UIAction(title: "Everyone", state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                self?.selectConnection(id: nil, user: nil)
            },
            UIAction(title: "My Connections", state: selectedConnectionId == "my_connections_only" ? .on : .off) { [weak self] _ in
                self?.selectConnection(id: "my_connections_only", user: nil)
            },
            UIAction(title: "My Places Only", state: selectedConnectionId == "my_places_only" ? .on : .off) { [weak self] _ in
                self?.selectConnection(id: "my_places_only", user: nil)
            }
        ]
        var listedIds = Set<String>()
        for connection in NetworkManager.shared.connections {
            let otherUserId = connection.otherUserId(currentUserId: currentUserId)
            listedIds.insert(otherUserId)
            connectionActions.append(
                UIAction(
                    title: connection.connectedUser?.displayName ?? "Unknown",
                    state: selectedConnectionId == otherUserId ? .on : .off
                ) { [weak self] _ in
                    self?.selectConnection(id: otherUserId, user: connection.connectedUser)
                }
            )
        }
        // Followed non-connections round out the roster — the map can scope
        // to anyone you follow, not just mutual connections
        for user in NetworkManager.shared.followingUsers {
            guard !user.id.isEmpty, !listedIds.contains(user.id),
                  !IDNormalizer.isSameUser(user.id, currentUserId) else { continue }
            listedIds.insert(user.id)
            connectionActions.append(
                UIAction(title: user.displayName, state: selectedConnectionId == user.id ? .on : .off) { [weak self] _ in
                    self?.selectConnection(id: user.id, user: user)
                }
            )
        }
        let connectionSubtitle = selectedConnectionUser?.displayName
            ?? (selectedConnectionId == "my_places_only" ? "My Places Only"
                : selectedConnectionId == "my_connections_only" ? "My Connections" : "Everyone")
        elements.append(UIMenu(
            title: "Connections",
            subtitle: connectionSubtitle,
            image: UIImage(systemName: "person.2"),
            children: connectionActions
        ))

        // No Category submenu here anymore — category filtering moved into the
        // always-visible chip bars on the map itself, matching the profile map.

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
        // Category chips reflect only the places visible under the people selection
        let visiblePlaces = applyConnectionFilterToPlaces(allPlaces)
        if let cleared = state.refreshAvailableCategories(visiblePlaces: visiblePlaces) {
            Logger.debug("🏷️ [Categories] Previously selected category '\(cleared.displayName)' no longer available, clearing selection")
        }
        Logger.debug("🏷️ [Categories] \(selectedConnectionId ?? "everyone"): \(availableCategories.count) categories from \(visiblePlaces.count)/\(allPlaces.count) places")
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
            } else if connectionId == "my_connections_only" {
                // Accepted connections' places only
                let connectedIds = acceptedConnectionUserIds
                filteredPlaces = places.filter { place in
                    if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                        return connectedIds.contains { IDNormalizer.isSameUser(circle.owner, $0) }
                    }
                    return connectedIds.contains { IDNormalizer.isSameUser(place.addedBy, $0) }
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

    /// User ids of all accepted connections (the "My Connections" map scope)
    var acceptedConnectionUserIds: [String] {
        let currentUserId = AuthService.shared.getUserId() ?? ""
        return NetworkManager.shared.connections
            .map { $0.otherUserId(currentUserId: currentUserId) }
            .filter { !$0.isEmpty }
    }

    /// Author ids for the default "Everyone" map scope: yourself + accepted
    /// connections + everyone you follow. (Following is loaded lazily, so this
    /// grows once `loadFollowingUsers` completes — the map refreshes then.)
    var everyoneAuthorIds: Set<String> {
        var ids = Set(acceptedConnectionUserIds)
        if let me = AuthService.shared.getUserId(), !me.isEmpty { ids.insert(me) }
        ids.formUnion(NetworkManager.shared.followingUsers.map { $0.id }.filter { !$0.isEmpty })
        return ids
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

        // Half-sheet: the list sits over the bottom ~55% of the map, so the map
        // stays visible and pannable above it. Grow the map container in list
        // mode so both the map slice and the list get usable room.
        placesListTableView.isHidden = !isShowingPlacesList
        mapHeightConstraint?.constant = isShowingPlacesList ? 500 : 320
        // Map controls stay put now that the map is still shown; the place-count
        // label is pinned low (behind the sheet), so it still hides.
        mapPlaceCountLabel.isHidden = isShowingPlacesList
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// Force the home map's list overlay back to the map (no-op if already on
    /// the map). Called when the Home tab is tapped so the map never stays
    /// stuck in list view. Reuses listToggleTapped so all side effects (icon,
    /// expand button, place-count) stay in sync.
    func resetPlacesListToMap() {
        if isShowingPlacesList {
            listToggleTapped()
        }
    }

    /// Rebuilds the distance-sorted data source for the places list from the
    /// currently filtered places. Places without a location sort last.
    func rebuildDistanceSortedPlaces() {
        // Run through the embedded map's chip filters too (category group +
        // region) — the list sits beside the pins and must show the same set.
        var filtered = applyFiltersToPlaces(allPlaces)
        if let mapVC = mapViewController {
            filtered = mapVC.applyChipFilters(filtered)
            filtered = mapVC.applySearchFilter(filtered)
        }
        let referenceLocation = mapViewController?.currentUserLocation
            ?? mapViewController.map { CLLocation(latitude: $0.currentRegion.center.latitude, longitude: $0.currentRegion.center.longitude) }
        let currentUserId = AuthService.shared.getUserId() ?? ""

        // The map/list is fed by every save doc, so a venue saved by several
        // people appeared multiple times. Group by the real-world venue (shared
        // Place.venueDedupeKey — same key the full-screen list uses) and show it
        // once, while still collecting the saver names for this row.
        var order: [String] = []
        var groups: [String: [Place]] = [:]
        for place in filtered {
            let key = place.venueDedupeKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(place)
        }

        let deduped: [(place: Place, distance: CLLocationDistance?, savedBy: [String])] = order.map { key in
            let group = groups[key] ?? []
            let hasPhotos: (Place) -> Bool = { !($0.photos?.isEmpty ?? true) }
            // Representative selection, in priority order: the user's own copy
            // WITH photos → any copy with photos (fixes "no picture on tap" when
            // a photo-less duplicate was picked) → the user's own copy → first.
            let representative = group.first(where: { $0.addedBy == currentUserId && hasPhotos($0) })
                ?? group.first(where: hasPhotos)
                ?? group.first(where: { $0.addedBy == currentUserId })
                ?? group[0]

            // Saver names, "You" first, de-duplicated.
            var names: [String] = []
            if group.contains(where: { $0.addedBy == currentUserId }) { names.append("You") }
            for place in group where place.addedBy != currentUserId {
                let name = place.addedByUser?.displayName ?? place.addedByDisplayName
                if !name.isEmpty, name != "Unknown", !names.contains(name) { names.append(name) }
            }

            let distance: CLLocationDistance?
            if let reference = referenceLocation, let placeLocation = representative.location?.clLocation {
                distance = reference.distance(from: placeLocation)
            } else {
                distance = nil
            }
            return (place: representative, distance: distance, savedBy: names)
        }

        distanceSortedPlaces = deduped.sorted { lhs, rhs in
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
            emptyLabel.text = activeSearchQuery.map { "No places match \"\($0)\"" } ?? "No places to show"
            emptyLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            emptyLabel.textColor = Constants.Colors.secondaryLabel
            emptyLabel.textAlignment = .center
            placesListTableView.backgroundView = emptyLabel
        } else {
            placesListTableView.backgroundView = nil
        }
    }

    /// "Saved by You, Jane +3" style subtitle for a deduped venue row.
    func savedByText(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        if names.count <= 2 { return "Saved by " + names.joined(separator: ", ") }
        return "Saved by \(names[0]), \(names[1]) +\(names.count - 2)"
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

    /// Pushes the detail screen for a place (used by the places list). Falls
    /// back to a nil circle (rather than doing nothing) when the place's circle
    /// isn't loaded — e.g. the deduped representative is a connection's copy —
    /// so a tap always opens the place.
    func presentDetailForPlace(_ place: Place) {
        let circle = resolveCircle(for: place)
        if circle == nil {
            Logger.debug("⚠️ Place not found in any circle (circleId: \(place.circleId ?? "nil")); opening without circle")
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
        userListView.selectedUserId = (id == nil || id == "my_places_only" || id == "my_connections_only") ? nil : id

        Logger.debug("📍 Connection filter changed to: \(selectedConnectionId ?? "All Connections")")

        // Tell the embedded map so it zooms to the selected connection's places
        mapViewController?.setConnectionFilterContext(selectedConnectionId)
        // ...and keep its dropdown header narrating the same selection.
        mapViewController?.setConnectionSelection(id: id, user: user)

        // Update available categories based on new connection filter
        updateAvailableCategories()

        if let connectionId = id, connectionId != "my_places_only", connectionId != "my_connections_only" {
            // Re-scope pins with what's already loaded BEFORE any async fetch —
            // otherwise other connections' pins linger until this connection's
            // places arrive. Keep the camera exactly where it is: switching
            // connections must not move the map (you're comparing who-saved-what
            // in the same view). If the connection has nothing in view, the
            // coverage banner offers to expand — we never auto-zoom here.
            // The banner stays hidden until this connection's places are in
            // (see fetchAllPlacesForConnection) — judging it now would flash
            // "no places" against a half-loaded set.
            setConnectionFetchPending(connectionId)
            refreshMapDisplay(adjustRegion: false)

            if networkCircles.isEmpty {
                Logger.debug("📍 Need to fetch network circles for connection filtering")
                fetchNetworkCircles { [weak self] in
                    guard let self = self else { return }
                    self.updateAvailableCategories()
                    // Ensure ALL of this connection's places are loaded (not viewport-bounded)
                    self.fetchAllPlacesForConnection(connectionId)
                }
            } else {
                fetchAllPlacesForConnection(connectionId)
            }
        } else {
            // Following / My Connections / My Places Only: refresh with what's
            // loaded, keeping the current camera (no zoom on connection change).
            setConnectionFetchPending(nil)
            refreshMapDisplay(adjustRegion: false)
            // "Following" and "My Connections" must mean ALL of those places,
            // not just the viewport-loaded subset — pull every connection's
            // full set in the background
            if id == nil || id == "my_connections_only" {
                prefetchAllConnectionPlaces()
            }
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

        // Tap on the visible map (anywhere outside the results list and the
        // bar) while results are up = "show me the MAP": drop the list into a
        // peek — the search stays live, the pins stay filtered, and the
        // floating Show List pill (or refocusing the bar) brings the list back.
        if isSearching && !isSearchOverlayDismissed && !searchResultsTableView.isHidden,
           let gesture = gesture {
            let location = gesture.location(in: view)
            let overlayFrame = searchResultsTableView.convert(searchResultsTableView.bounds, to: view)
            let searchBarFrame = searchBar.convert(searchBar.bounds, to: view)
            if !overlayFrame.contains(location) && !searchBarFrame.contains(location) {
                enterSearchMapPeek()
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

    @objc func browseByLocationTapped() {
        navigationController?.pushViewController(LocationBrowseViewController(), animated: true)
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
        // Attach the badge to the ACTUAL bell bar button. This must run after
        // notificationBarButton exists (it's created in makeRightBarButtons) —
        // otherwise the custom view is assigned to nil and the badge is orphaned,
        // which is why the bell never showed an unseen indicator before.
        guard let barButton = notificationBarButton else { return }

        // Reuse the custom button across rebuilds so we don't stack subviews
        let button: UIButton
        if let existing = barButton.customView as? UIButton {
            button = existing
        } else {
            button = UIButton(type: .custom)
            button.setImage(UIImage(systemName: "bell"), for: .normal)
            // Match the sibling bar buttons (which render in the label color),
            // otherwise the custom-view bell picks up the blue app tint.
            button.tintColor = Constants.Colors.label
            button.addTarget(self, action: #selector(notificationButtonTapped), for: .touchUpInside)
            button.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            barButton.customView = button
        }

        // Build the dot once and keep it
        if notificationBadgeLabel?.superview !== button {
            notificationBadgeLabel?.removeFromSuperview()
            button.clipsToBounds = false // don't clip the dot at the button edge

            // Unseen indicator: a small red dot (not a count). It only needs to
            // say "something's waiting" — presence, not precision — and clears
            // when the Notifications screen marks everything read. A plain UIView
            // with an explicit red renders reliably (a UILabel background did not).
            let dot = UIView()
            dot.backgroundColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0) // system red
            dot.layer.cornerRadius = 5
            dot.layer.masksToBounds = true
            dot.isHidden = true
            dot.isUserInteractionEnabled = false
            dot.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(dot)

            // Sit on the bell's top-right, fully inside the 30pt button so the
            // bar doesn't clip it.
            NSLayoutConstraint.activate([
                dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
                dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10)
            ])

            self.notificationBadgeLabel = dot
        }
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
                    // Red dot = presence only; any unread shows it, zero hides it.
                    self.notificationBadgeLabel?.isHidden = count <= 0
                case .failure(let error):
                    Logger.debug("❌ [updateNotificationBadge] Failed to get unread count: \(error)")
                    self.notificationBadgeLabel?.isHidden = true
                }
            }
        }
    }
    
    @objc func rewardsButtonTapped() {
        // The '$' hub: store-loyalty Rewards + the FavCoin piggy bank.
        let hubVC = RewardsHubViewController()
        navigationController?.pushViewController(hubVC, animated: true)
    }

    @objc func handleRewardBalanceChanged() {
        updateRewardsBadge()
    }

    @objc func handleNotificationsMarkedRead() {
        // Optimistically hide the dot, then reconcile with the server count
        notificationBadgeLabel?.isHidden = true
        updateNotificationBadge()
    }

    @objc func handleSubscriptionStatusChanged() {
        updateNavigationBarForSubscription()
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

// MARK: - HomeDataLoaderDelegate
// Most requirements are satisfied by existing presentation methods above
// (loading states, empty state, map refreshes). These are the few hooks
// that used to be inline view pokes in the loading code.
extension CirclesHomeViewController: HomeDataLoaderDelegate {
    var embeddedMapViewController: FullScreenMapViewController? { mapViewController }

    func refreshUserList() {
        userListView.refresh()
    }

    func loaderDidLoadFeed(activities: [Activity], reels: [PlaceVideo]) {
        self.activities = activities
        self.reels = reels
    }

    func presentFilteredPlaces(_ places: [Place], adjustRegionAfterDelay: Bool) {
        mapRefreshDidFilter(places)
        mapViewController?.updatePlaces(places)
        if adjustRegionAfterDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.mapViewController?.adjustMapRegion()
            }
        }
        updatePlaceCountLabel(count: places.count)
    }

    func connectionIdWasCanonicalized(_ canonicalId: String) {
        mapViewController?.setConnectionFilterContext(canonicalId)
        // The presented full map filters independently - without
        // the canonical id its added-by match finds nothing
        presentedFullScreenMap?.setConnectionFilterContext(canonicalId)
        userListView.selectedUserId = canonicalId
    }
}

// MARK: - HomeContentTabHost
extension CirclesHomeViewController: HomeContentTabHost {
    func endRefreshing() {
        scrollView.refreshControl?.endRefreshing()
    }

    func layoutContentIfNeeded() {
        view.layoutIfNeeded()
    }

    func attachFullScreenOverlay(_ overlay: UIView) {
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - VideoLinkInputDelegate
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

// MARK: - Notification badge timer
extension CirclesHomeViewController {
    func startNotificationBadgeRefresh() {
        notificationBadgeTimer?.invalidate()

        // Refresh the badge every 30 seconds so it stays current even if
        // SSE events are missed
        notificationBadgeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateNotificationBadge()
        }
    }

    func stopNotificationBadgeRefresh() {
        notificationBadgeTimer?.invalidate()
        notificationBadgeTimer = nil
        Logger.debug("🔔 [Timer] Stopped periodic notification badge refresh")
    }
}
