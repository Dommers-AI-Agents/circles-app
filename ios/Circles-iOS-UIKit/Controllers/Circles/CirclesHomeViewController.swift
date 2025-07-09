import UIKit
import CoreLocation
import UniformTypeIdentifiers

class CirclesHomeViewController: UIViewController {
    
    // MARK: - Properties
    private var circles: [Circle] = []
    private var networkCircles: [Circle] = []
    private var isShowingNetworkCircles = false
    private var allPlaces: [Place] = []
    private var filteredPlaces: [Place] = []
    private var isSearching = false
    private var selectedCategory: PlaceCategory?
    private var mapUpdateTimer: Timer? // Debounce timer for map updates
    private var isReturningFromFullScreenMap = false // Prevent map updates when returning from full screen
    private var isLoadingCircles = false // Track when circles are being loaded
    private var isLoadingPlaces = false // Track when places are being loaded
    private var isPerformingInitialLoad = false // Track if we're in the middle of initial loading
    private var isShowingLoadingUI = false // Track if loading UI is currently shown
    private static var hasLoadedInitialData = false // Track if we've loaded data at least once this session
    private static var cachedPlaces: [Place] = [] // Cache places to show immediately on subsequent views
    private static var isCurrentlyLoading = false // Global flag to prevent concurrent loads
    private var hasStartedLoading = false // Instance flag to prevent multiple loads in the same instance
    private var loadDebounceTimer: Timer? // Debounce timer to prevent rapid successive loads
    
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
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search your places..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let quickAccessContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let homeCard: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.lightGray.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let workCard: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.lightGray.cgColor
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
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let workNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let filterContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
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
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
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
    
    private var mapViewController: FullScreenMapViewController?
    
    private let filterStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
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
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
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
    private let searchResultsTableView: UITableView = {
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
    
    private var searchResultsHeightConstraint: NSLayoutConstraint?
    
    private let categoryFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Categories", for: .normal)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = Constants.Colors.secondaryBackground
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
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
    private var availableCategories: [PlaceCategory] = []
    private var categoryDropdownHeightConstraint: NSLayoutConstraint?
    
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
        
        // Hide map initially until data loads
        mapContainerView.isHidden = true
        filterStackView.isHidden = true
        filterContainer.isHidden = true
        mapExpandButton.isHidden = true
        
        // Ensure map loading view is hidden initially
        mapLoadingView.isHidden = true
        mapLoadingIndicator.stopAnimating()
        
        // Load connections immediately
        userListView.refresh()
        
        // Don't show loading state here - let fetchCircles handle it
        // The loading will be shown when fetchAllPlacesFromCircles is called
        
        // Start with empty state hidden until data loads
        emptyStateView.isHidden = true
        
        // If we have cached places, show them immediately without filtering
        // The proper filter will be applied when circles are loaded
        if !CirclesHomeViewController.cachedPlaces.isEmpty {
            print("🟡 Found cached places: \(CirclesHomeViewController.cachedPlaces.count)")
            self.allPlaces = CirclesHomeViewController.cachedPlaces
            
            // Show all cached places initially - proper filter will be applied when circles load
            print("🟡 Showing all cached places initially (filter will be applied after circles load)")
            self.mapViewController?.updatePlaces(CirclesHomeViewController.cachedPlaces)
            
            // Show map immediately since we have cached data
            mapContainerView.isHidden = false
            filterStackView.isHidden = false
            filterContainer.isHidden = false
            mapExpandButton.isHidden = false
            mapLoadingView.isHidden = true
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
        // Reset loading flag if this instance was loading
        if isPerformingInitialLoad {
            isPerformingInitialLoad = false
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        print("🟢 CirclesHomeViewController viewWillAppear called")
        print("🟢 Instance: \(ObjectIdentifier(self))")
        print("   hasStartedLoading: \(hasStartedLoading)")
        print("   isReturningFromFullScreenMap: \(isReturningFromFullScreenMap)")
        print("   circles.count: \(circles.count)")
        print("   allPlaces.count: \(allPlaces.count)")
        
        // If returning from full screen map, skip updates
        if isReturningFromFullScreenMap {
            isReturningFromFullScreenMap = false
            return
        }
        
        // Simple check: if this instance has already started loading, don't load again
        if hasStartedLoading {
            print("🟢 Skipping load - this instance has already started loading")
            return
        }
        
        // Mark that this instance has started loading
        hasStartedLoading = true
        
        // Cancel any existing timer
        loadDebounceTimer?.invalidate()
        
        // Debounce the load to prevent rapid successive calls
        loadDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            print("🟢 Starting initial data load (after debounce)")
            // Use unified loading method
            self?.performInitialDataLoad()
            self?.userListView.refresh() // Refresh connections list
        }
        
        // Don't show filter stack here - let hideMapLoadingState handle it
        // This prevents the filter from showing then hiding again
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
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped))
        navigationItem.rightBarButtonItem = addButton
        
        // Setup empty state view
        emptyStateView.addSubview(emptyStateImageView)
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateView.addSubview(createCircleButton)
        
        // Setup quick access buttons
        setupQuickAccessButtons()
        
        view.addSubview(searchBar)
        view.addSubview(quickAccessContainer)
        quickAccessContainer.addSubview(homeCard)
        quickAccessContainer.addSubview(workCard)
        homeCard.addSubview(homeButton)
        homeCard.addSubview(homeNavigateButton)
        workCard.addSubview(workButton)
        workCard.addSubview(workNavigateButton)
        view.addSubview(quickAddPlaceButton)
        view.addSubview(userListView)
        view.addSubview(filterContainer)
        view.addSubview(mapContainerView)
        view.addSubview(mapLoadingView)
        mapLoadingView.addSubview(mapLoadingIndicator)
        mapLoadingView.addSubview(mapLoadingLabel)
        view.addSubview(mapExpandButton)
        view.addSubview(filterStackView)
        view.addSubview(locationStatusLabel)
        filterStackView.addArrangedSubview(categoryFilterButton)
        filterStackView.addArrangedSubview(connectionFilterButton)
        view.addSubview(emptyStateView)
        
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
        
        // Bring filter stack to front to ensure visibility
        view.bringSubviewToFront(filterStackView)
        
        // Ensure loading view is on top
        view.bringSubviewToFront(loadingContainerView)
        
        // Add tap gesture to dismiss dropdowns when clicking outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissDropdowns))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        NSLayoutConstraint.activate([
            // Search bar
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            searchBar.trailingAnchor.constraint(equalTo: quickAddPlaceButton.leadingAnchor, constant: -Constants.Spacing.small),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            // Quick access container
            quickAccessContainer.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Constants.Spacing.small),
            quickAccessContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickAccessContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            quickAccessContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Quick Add Place button
            quickAddPlaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            quickAddPlaceButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            quickAddPlaceButton.heightAnchor.constraint(equalToConstant: 40),
            quickAddPlaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            // Home card
            homeCard.leadingAnchor.constraint(equalTo: quickAccessContainer.leadingAnchor, constant: Constants.Spacing.large),
            homeCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            homeCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.42),
            homeCard.heightAnchor.constraint(equalToConstant: 60),
            
            // Work card
            workCard.trailingAnchor.constraint(equalTo: quickAccessContainer.trailingAnchor, constant: -Constants.Spacing.large),
            workCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            workCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.42),
            workCard.heightAnchor.constraint(equalToConstant: 60),
            
            // Home button (inside home card)
            homeButton.leadingAnchor.constraint(equalTo: homeCard.leadingAnchor),
            homeButton.topAnchor.constraint(equalTo: homeCard.topAnchor),
            homeButton.bottomAnchor.constraint(equalTo: homeCard.bottomAnchor),
            homeButton.trailingAnchor.constraint(equalTo: homeNavigateButton.leadingAnchor, constant: -8),
            
            // Home navigate button
            homeNavigateButton.centerYAnchor.constraint(equalTo: homeCard.centerYAnchor),
            homeNavigateButton.trailingAnchor.constraint(equalTo: homeCard.trailingAnchor, constant: -8),
            homeNavigateButton.widthAnchor.constraint(equalToConstant: 30),
            homeNavigateButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Work button (inside work card)
            workButton.leadingAnchor.constraint(equalTo: workCard.leadingAnchor),
            workButton.topAnchor.constraint(equalTo: workCard.topAnchor),
            workButton.bottomAnchor.constraint(equalTo: workCard.bottomAnchor),
            workButton.trailingAnchor.constraint(equalTo: workNavigateButton.leadingAnchor, constant: -8),
            
            // Work navigate button
            workNavigateButton.centerYAnchor.constraint(equalTo: workCard.centerYAnchor),
            workNavigateButton.trailingAnchor.constraint(equalTo: workCard.trailingAnchor, constant: -8),
            workNavigateButton.widthAnchor.constraint(equalToConstant: 30),
            workNavigateButton.heightAnchor.constraint(equalToConstant: 30),
            
            // User list view
            userListView.topAnchor.constraint(equalTo: quickAccessContainer.bottomAnchor, constant: Constants.Spacing.medium),
            userListView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            userListView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            userListView.heightAnchor.constraint(equalToConstant: 124),
            
            // Filter container
            filterContainer.topAnchor.constraint(equalTo: userListView.bottomAnchor, constant: Constants.Spacing.medium),
            filterContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Filter stack - center in filter container
            filterStackView.centerYAnchor.constraint(equalTo: filterContainer.centerYAnchor),
            filterStackView.centerXAnchor.constraint(equalTo: filterContainer.centerXAnchor),
            filterStackView.heightAnchor.constraint(equalToConstant: 36),
            
            // Map container - connect to filter container bottom
            mapContainerView.topAnchor.constraint(equalTo: filterContainer.bottomAnchor),
            mapContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Map loading view - same position as map container
            mapLoadingView.topAnchor.constraint(equalTo: filterContainer.bottomAnchor),
            mapLoadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapLoadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapLoadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Map loading indicator
            mapLoadingIndicator.centerXAnchor.constraint(equalTo: mapLoadingView.centerXAnchor),
            mapLoadingIndicator.centerYAnchor.constraint(equalTo: mapLoadingView.centerYAnchor, constant: -20),
            
            // Map loading label
            mapLoadingLabel.topAnchor.constraint(equalTo: mapLoadingIndicator.bottomAnchor, constant: 16),
            mapLoadingLabel.leadingAnchor.constraint(equalTo: mapLoadingView.leadingAnchor, constant: 20),
            mapLoadingLabel.trailingAnchor.constraint(equalTo: mapLoadingView.trailingAnchor, constant: -20),
            
            // Map expand button
            mapExpandButton.topAnchor.constraint(equalTo: mapContainerView.topAnchor, constant: Constants.Spacing.small),
            mapExpandButton.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor, constant: -Constants.Spacing.small),
            mapExpandButton.widthAnchor.constraint(equalToConstant: 36),
            mapExpandButton.heightAnchor.constraint(equalToConstant: 36),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            
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
            locationStatusLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        // Create height constraints for dropdowns
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
        
        setupMapView()
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
    }
    
    private func setupSearchBar() {
        searchBar.delegate = self
    }
    
    private func setupQuickAccessButtons() {
        // Configure Home button
        var homeConfig = UIButton.Configuration.filled()
        homeConfig.image = UIImage(systemName: "house.fill")
        homeConfig.title = "Home"
        homeConfig.imagePlacement = .leading
        homeConfig.imagePadding = 8
        homeConfig.baseBackgroundColor = .clear
        homeConfig.baseForegroundColor = Constants.Colors.primary
        homeConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        homeButton.configuration = homeConfig
        homeButton.addTarget(self, action: #selector(homeButtonTapped), for: .touchUpInside)
        
        // Configure Work button
        var workConfig = UIButton.Configuration.filled()
        workConfig.image = UIImage(systemName: "building.2.fill")
        workConfig.title = "Work"
        workConfig.imagePlacement = .leading
        workConfig.imagePadding = 8
        workConfig.baseBackgroundColor = .clear
        workConfig.baseForegroundColor = Constants.Colors.secondary
        workConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        workButton.configuration = workConfig
        workButton.addTarget(self, action: #selector(workButtonTapped), for: .touchUpInside)
        
        // Add targets for navigate buttons
        homeNavigateButton.addTarget(self, action: #selector(homeNavigateButtonTapped), for: .touchUpInside)
        workNavigateButton.addTarget(self, action: #selector(workNavigateButtonTapped), for: .touchUpInside)
        
        // Add shadow to container
        quickAccessContainer.layer.shadowOpacity = 0.05
        quickAccessContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        quickAccessContainer.layer.shadowRadius = 4
        
        // Apply appearance
        updateAppearance()
    }
    
    // Navigation title tap removed since we no longer show the title
    
    // MARK: - Data Fetching
    private func performInitialDataLoad() {
        // Set the global loading flag
        CirclesHomeViewController.isCurrentlyLoading = true
        
        // Unified method to load both circles and places
        print("🔄 Starting initial data load")
        
        // Show loading state once if not already showing and no cached data
        if CirclesHomeViewController.cachedPlaces.isEmpty {
            // Only show loading states if we don't have cached data
            showLoadingState()
            showMapLoadingState()
        }
        
        fetchCircles()
    }
    
    private func showMapLoadingState() {
        // Prevent showing loading state multiple times
        guard !isShowingLoadingUI else { 
            print("🗺️ Map loading state already showing")
            return 
        }
        
        print("🗺️ Showing map loading state")
        isShowingLoadingUI = true
        mapLoadingView.isHidden = false
        mapLoadingIndicator.startAnimating()
        mapContainerView.isHidden = true
        filterStackView.isHidden = true
        filterContainer.isHidden = true
        mapExpandButton.isHidden = true
    }
    
    private func hideMapLoadingState() {
        print("🗺️ Hiding map loading state, showing map")
        isShowingLoadingUI = false
        mapLoadingView.isHidden = true
        mapLoadingIndicator.stopAnimating()
        mapContainerView.isHidden = false
        filterStackView.isHidden = false
        filterContainer.isHidden = false
        mapExpandButton.isHidden = false
    }
    
    private func fetchCircles() {
        // Only show loading state on the very first app launch
        isLoadingCircles = true
        
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingCircles = false
                
                switch result {
                case .success(let circles):
                    print("✅ Successfully fetched \(circles.count) circles")
                    self?.circles = circles
                    self?.fetchAllPlacesFromCircles()
                    // Don't mark as loaded here - wait until places are fetched
                case .failure(let error):
                    print("❌ Error fetching circles: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                    
                    // If it's a duplicate request error, still need to clean up state
                    if case .duplicateRequest = error as? APIError {
                        print("❌ Duplicate request detected - cleaning up state")
                        self?.isLoadingCircles = false
                        self?.isPerformingInitialLoad = false
                        CirclesHomeViewController.isCurrentlyLoading = false
                        self?.hideLoadingState()
                        self?.hideMapLoadingState()
                        return
                    }
                    
                    // Don't use sample circles - show empty state instead
                    self?.circles = []
                    self?.allPlaces = []
                    self?.isLoadingCircles = false
                    self?.isPerformingInitialLoad = false
                    CirclesHomeViewController.isCurrentlyLoading = false
                    self?.hideLoadingState()
                    self?.hideMapLoadingState()
                }
                
                self?.updateEmptyState()
            }
        }
    }
    
    private func fetchNetworkCircles() {
        // Use CircleService to fetch network circles
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<NetworkCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ Successfully fetched \(response.data.count) network circles")
                    for circle in response.data {
                        print("📍 Network circle received: \(circle.name) by \(circle.owner), privacy: \(circle.privacy.rawValue)")
                        if circle.name.lowercased().contains("hawaii") {
                            print("🏝️ Found Hawaii circle! Privacy: \(circle.privacy.rawValue), Owner: \(circle.owner)")
                        }
                    }
                    self?.networkCircles = response.data
                    self?.updateEmptyState()
                    // Don't call updateMapPlaces here - fetchAllPlacesFromCircles handles everything
                case .failure(let error):
                    print("❌ Error fetching network circles: \(error.localizedDescription)")
                    
                    // If it's a duplicate request error, just ignore it
                    if case .duplicateRequest = error {
                        return
                    }
                    
                    self?.networkCircles = []
                    self?.updateEmptyState()
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
    
    private func showLoadingState() {
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
    
    private func hideLoadingState() {
        UIView.animate(withDuration: 0.3, animations: {
            self.loadingContainerView.alpha = 0
        }) { _ in
            self.loadingContainerView.isHidden = true
            self.loadingIndicator.stopAnimating()
        }
        updateEmptyState()
    }
    
    private func fetchAllPlacesFromCircles() {
        var allFetchedPlaces: [Place] = []
        let group = DispatchGroup()
        
        // Show loading state for places
        isLoadingPlaces = true
        
        // Loading state is already shown by performInitialDataLoad, don't show again
        
        print("📍 fetchAllPlacesFromCircles called")
        print("📍 User circles count: \(circles.count)")
        print("📍 Network circles count: \(networkCircles.count)")
        
        // If no circles at all, just update UI and return
        if circles.isEmpty && networkCircles.isEmpty {
            print("📍 No circles to fetch places from")
            self.allPlaces = []
            self.mapViewController?.updatePlaces([])
            self.isLoadingPlaces = false
            self.isPerformingInitialLoad = false
            CirclesHomeViewController.isCurrentlyLoading = false
            self.hideLoadingState()
            self.hideMapLoadingState() // Show empty map
            self.updateEmptyState()
            // Don't set hasLoadedInitialData here - we have no data
            return
        }
        
        // Debug network circles
        for circle in networkCircles {
            print("📍 Network circle: \(circle.name) by \(circle.owner), privacy: \(circle.privacy)")
        }
        
        // Fetch user's own places
        for circle in circles {
            group.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                switch result {
                case .success(let places):
                    print("✅ Fetched \(places.count) places from circle '\(circle.name)':")
                    for place in places {
                        let hasLocation = place.location?.clLocation != nil
                        print("   - '\(place.name)' (hasLocation: \(hasLocation), addedBy: \(place.addedBy))")
                    }
                    allFetchedPlaces.append(contentsOf: places)
                case .failure(let error):
                    print("❌ Failed to fetch places for circle '\(circle.name)' (id: \(circle.id)): \(error)")
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
            ) { [weak self] (result: Result<NetworkCirclesResponse, APIError>) in
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
            
            self.allPlaces = allFetchedPlaces
            
            // Cache the places for instant display on subsequent views
            CirclesHomeViewController.cachedPlaces = allFetchedPlaces
            
            print("🔍 Fetched Places Summary:")
            print("   Total places fetched: \(allFetchedPlaces.count)")
            
            // Apply connection filter if selected
            var filteredPlaces = allFetchedPlaces
                
                print("📍 Connection filter - selectedConnectionId: \(self.selectedConnectionId ?? "nil")")
                
                if let connectionId = self.selectedConnectionId {
                    if connectionId == "my_places_only" {
                        // Show all places from user's own circles
                        let userCircleIds = self.circles.map { $0.id }
                        if userCircleIds.isEmpty {
                            print("⚠️ Warning: User circles not loaded yet, showing all places")
                            filteredPlaces = allFetchedPlaces
                        } else {
                            filteredPlaces = allFetchedPlaces.filter { place in
                                userCircleIds.contains(place.circleId)
                            }
                            print("   Filtered to user's circles (\(userCircleIds.count) circles): \(filteredPlaces.count) places")
                        }
                    } else {
                        // Show only places from the selected connection
                        // Get all places from circles owned by this connection
                        filteredPlaces = allFetchedPlaces.filter { place in
                            // Find the circle this place belongs to
                            if let circle = self.networkCircles.first(where: { $0.id == place.circleId }) {
                                return circle.owner == connectionId
                            }
                            return false
                        }
                        print("   Filtered to connection '\(connectionId)': \(filteredPlaces.count) places")
                    }
                } else {
                    // "All Connections" selected - show all places (user's + connections')
                    filteredPlaces = allFetchedPlaces
                    print("   Showing all connections' places: \(filteredPlaces.count) places")
                }
                
                // Apply category filter
                if let category = self.selectedCategory {
                    let beforeCategoryFilter = filteredPlaces.count
                    filteredPlaces = filteredPlaces.filter { $0.category == category }
                    print("   Category filter '\(category.rawValue)' applied: \(beforeCategoryFilter) → \(filteredPlaces.count) places")
                }
                
                
                print("   Final places sent to map: \(filteredPlaces.count)")
                
                // Update location status label
                let placesWithLocation = filteredPlaces.filter { $0.location?.clLocation != nil }.count
                let placesWithoutLocation = filteredPlaces.count - placesWithLocation
                
                if placesWithoutLocation > 0 {
                    self.locationStatusLabel.text = "⚠️ \(placesWithoutLocation) places missing location"
                    self.locationStatusLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
                    self.locationStatusLabel.textColor = .white
                    self.locationStatusLabel.layer.cornerRadius = 14
                    self.locationStatusLabel.layer.masksToBounds = true
                    self.locationStatusLabel.isHidden = false
                    
                    // Add padding to the label
                    if self.locationStatusLabel.constraints.first(where: { $0.firstAttribute == .width }) == nil {
                        self.locationStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
                    }
                } else {
                    self.locationStatusLabel.isHidden = true
                }
                
                // Pass filtered places to map
                print("🗺️ Updating map with \(filteredPlaces.count) places")
                self.mapViewController?.updatePlaces(filteredPlaces)
                
                // Hide loading state
                self.isLoadingPlaces = false
                self.isPerformingInitialLoad = false // Reset initial load flag
                CirclesHomeViewController.isCurrentlyLoading = false // Reset global loading flag
                self.hideLoadingState()
                
                // Hide map loading state and show the map now that data is ready
                self.hideMapLoadingState()
                
                // Mark that we've loaded data only if we actually have data
                if !self.circles.isEmpty || !allFetchedPlaces.isEmpty {
                    CirclesHomeViewController.hasLoadedInitialData = true
                }
        })
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
    }
    
    @objc private func handleCircleDeleted(_ notification: Notification) {
        guard let circleId = notification.userInfo?["circleId"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            // Remove the circle from our local array
            if let index = self?.circles.firstIndex(where: { $0.id == circleId }) {
                self?.circles.remove(at: index)
                
                // Reload UI
                if self?.isShowingNetworkCircles == false {
                    self?.fetchAllPlacesFromCircles()
                }
            }
            
            // Also remove from network circles if present
            if let index = self?.networkCircles.firstIndex(where: { $0.id == circleId }) {
                self?.networkCircles.remove(at: index)
            }
            
            // Note: CircleManager caching removed - using local arrays only
            
            // Update empty state
            self?.updateEmptyState()
        }
    }
    
    @objc private func handleRefreshCircles() {
        // Refresh circles to get updated place counts
        refreshData()
    }
    
    // MARK: - Actions
    @objc private func addButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        navigationController?.pushViewController(createCircleVC, animated: true)
    }
    
    @objc private func createCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        navigationController?.pushViewController(createCircleVC, animated: true)
    }
    
    @objc private func expandMapButtonTapped() {
        // Set flag to prevent map updates when returning
        isReturningFromFullScreenMap = true
        
        // Present full screen map with all places
        let fullScreenMap = FullScreenMapViewController(places: allPlaces)
        fullScreenMap.viewMode = .allPlaces
        fullScreenMap.isPresentedModally = true
        fullScreenMap.updatePlacesWithConnections(
            allPlaces.filter { place in
                // Filter user's own places
                place.addedBy == AuthService.shared.getUserId()
            },
            connections: [],
            connectionPlaces: [:]
        )
        fullScreenMap.modalPresentationStyle = .fullScreen
        present(fullScreenMap, animated: true)
    }
    
    @objc private func quickAddPlaceButtonTapped() {
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
        let circlePickerVC = CirclePickerViewController(circles: circles)
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
            // Only fetch if not already loading
            if !(self?.isLoadingPlaces ?? false) && !(self?.isPerformingInitialLoad ?? false) {
                self?.fetchAllPlacesFromCircles()
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
        // Get unique categories from all places
        var categoriesSet = Set<PlaceCategory>()
        for place in allPlaces {
            categoriesSet.insert(place.category)
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
    }
    
    @objc private func refreshData() {
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
            loadingAlert.dismiss(animated: true) {
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
                    DispatchQueue.main.async {
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
    
    // MARK: - Search Results
    private func showSearchResults() {
        // Calculate height based on number of results (max 5 visible)
        let maxVisibleResults = 5
        let cellHeight: CGFloat = 60
        let numberOfResults = min(filteredPlaces.count, maxVisibleResults)
        let height = CGFloat(numberOfResults) * cellHeight
        
        searchResultsTableView.isHidden = false
        searchResultsHeightConstraint?.constant = height
        
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 1
            self.view.layoutIfNeeded()
        }
        
        searchResultsTableView.reloadData()
    }
    
    private func hideSearchResults() {
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 0
            self.searchResultsHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.searchResultsTableView.isHidden = true
        }
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
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self?.circles.remove(at: indexPath.row)
                    self?.updateEmptyState()
                    
                case .failure(let error):
                    self?.presentAlert(
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
        } else if tableView == searchResultsTableView {
            return filteredPlaces.count
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
            updateMapPlaces()
            hideConnectionDropdown()
            isConnectionDropdownOpen = false
        } else if tableView == searchResultsTableView {
            let place = filteredPlaces[indexPath.row]
            
            // Find the circle this place belongs to
            var circle: Circle?
            if let userCircle = circles.first(where: { $0.id == place.circleId }) {
                circle = userCircle
            } else if let networkCircle = networkCircles.first(where: { $0.id == place.circleId }) {
                circle = networkCircle
            }
            
            if let circle = circle {
                // Navigate to place detail
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
                
                // Clear search
                searchBar.text = ""
                searchBar.resignFirstResponder()
                isSearching = false
                filteredPlaces = []
                hideSearchResults()
            }
        }
    }
}

// MARK: - CreateCircleDelegate
protocol CreateCircleDelegate: AnyObject {
    func didCreateCircle(_ circle: Circle)
}

extension CirclesHomeViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        updateEmptyState()
        updateMapPlaces()
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
            navigationController?.pushViewController(placeDetailVC, animated: true)
        } 
        // Then check network circles
        else if let networkCircle = networkCircles.first(where: { $0.places?.contains(place.id) == true }) {
            let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}


// MARK: - UISearchBarDelegate
extension CirclesHomeViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredPlaces = []
            hideSearchResults()
        } else {
            isSearching = true
            filteredPlaces = allPlaces.filter { place in
                place.name.localizedCaseInsensitiveContains(searchText) ||
                (place.address).localizedCaseInsensitiveContains(searchText) ||
                (place.description ?? "").localizedCaseInsensitiveContains(searchText)
            }
            
            if !filteredPlaces.isEmpty {
                showSearchResults()
            } else {
                hideSearchResults()
            }
        }
        updateEmptyState()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        hideSearchResults()
        updateEmptyState()
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }
}

// MARK: - HorizontalUserListViewDelegate
extension CirclesHomeViewController: HorizontalUserListViewDelegate {
    func didSelectUser(_ user: User, connectionId: String) {
        // Navigate to user's circles
        let userCirclesVC = UserCirclesViewController(userId: user.id ?? "", userName: user.displayName, connectionId: connectionId)
        navigationController?.pushViewController(userCirclesVC, animated: true)
    }
}

// MARK: - Navigation from Notifications
extension CirclesHomeViewController {
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
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circle):
                        let detailVC = CircleDetailViewController(circle: circle)
                        self?.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load circle: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(alert, animated: true)
                    }
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
        if !searchResultsTableView.isHidden && searchResultsTableView.frame.contains(location) {
            return false
        }
        
        return true
    }
}
