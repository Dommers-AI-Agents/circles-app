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
    private var isShowingMap = false
    var allPlaces: [Place] = []
    var filteredPlaces: [Place] = []
    private var selectedCategory: PlaceCategory?
    private var availableCategories: [UnifiedCategory] = []
    private var selectedCity: String?
    var isSearching = false
    var searchResultsHeightConstraint: NSLayoutConstraint?
    
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
    
    // Buttons container
    private let buttonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var editProfileButton = UIButton.smallActionButton(title: "Edit profile", style: .secondary)
    
    private lazy var shareProfileButton = UIButton.smallActionButton(title: "Share profile", style: .secondary)
    
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
    
    // Separator line
    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
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
    
    private lazy var addCircleButton: UIButton = {
        let button = UIButton.iconButton(systemName: "plus")
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 25
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.3
        return button
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
    private var logoutButtonTopToCollectionConstraint: NSLayoutConstraint?
    private var logoutButtonTopToMapConstraint: NSLayoutConstraint?
    
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
    
    private lazy var categoryFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Categories", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Style as dropdown button
        button.backgroundColor = UIColor.systemBackground
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.layer.cornerRadius = 8
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 32)
        
        // Add chevron down icon
        let chevronImage = UIImage(systemName: "chevron.down")
        button.setImage(chevronImage, for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: -12)
        
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        
        return button
    }()
    
    private lazy var cityFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Cities", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Style as dropdown button
        button.backgroundColor = UIColor.systemBackground
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.layer.cornerRadius = 8
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 32)
        
        // Add chevron down icon
        let chevronImage = UIImage(systemName: "chevron.down")
        button.setImage(chevronImage, for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: -12)
        
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        
        return button
    }()
    
    // State tracking for other users
    private var isFollowing: Bool = false
    private var connectionStatus: ConnectionStatus?
    
    // Constraint references for dynamic button positioning
    private var followButtonLeadingToMessageConstraint: NSLayoutConstraint?
    private var followButtonLeadingToConnectConstraint: NSLayoutConstraint?
    private var connectButtonLeadingConstraint: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    init(user: User? = nil) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        displayAppVersion()
        setupNotificationObservers()
        
        // Always start in list view
        isShowingMap = false
        circlesCollectionView.isHidden = false
        mapContainerView.isHidden = true
        if let toggleButton = navigationItem.rightBarButtonItems?[1] {
            toggleButton.title = "Map"
        }
        
        // Clear any old saved view mode preference
        UserDefaults.standard.removeObject(forKey: "profileViewMode")
        
        // Register for SSE events
        SSEService.shared.addDelegate(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Always reset to list view when navigating to Profile tab
        if isShowingMap {
            isShowingMap = false
            
            // Update toggle button title
            if let toggleButton = navigationItem.rightBarButtonItems?[1] {
                toggleButton.title = "Map"
            }
            
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
        suggestedButton.layer.borderColor = UIColor.separator.cgColor
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
        let toggleButton = UIBarButtonItem(title: "Map", style: .plain, target: self, action: #selector(toggleViewMode))
        navigationItem.rightBarButtonItems = [settingsButton, toggleButton]
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileHeaderView)
        profileHeaderView.addSubview(usernameLabel)
        profileHeaderView.addSubview(profileImageView)
        profileHeaderView.addSubview(topStatsContainer)
        profileHeaderView.addSubview(bottomStatsContainer)
        topStatsContainer.addSubview(circlesStatView)
        topStatsContainer.addSubview(placesStatView)
        topStatsContainer.addSubview(connectionsStatView)
        bottomStatsContainer.addSubview(followersStatView)
        bottomStatsContainer.addSubview(followingStatView)
        profileHeaderView.addSubview(bioLabel)
        profileHeaderView.addSubview(buttonsContainer)
        buttonsContainer.addSubview(editProfileButton)
        buttonsContainer.addSubview(shareProfileButton)
        buttonsContainer.addSubview(suggestedButton)
        buttonsContainer.addSubview(messageButton)
        buttonsContainer.addSubview(followButton)
        buttonsContainer.addSubview(connectButton)
        
        contentView.addSubview(separatorLine)
        contentView.addSubview(searchBar)
        contentView.addSubview(circlesHeaderView)
        circlesHeaderView.addSubview(circlesHeaderLabel)
        contentView.addSubview(circlesCollectionView)
        
        // Add map container (initially hidden)
        contentView.addSubview(mapContainerView)
        mapContainerView.addSubview(filterContainerView)
        filterContainerView.addSubview(categoryFilterButton)
        filterContainerView.addSubview(cityFilterButton)
        mapContainerView.addSubview(mapView)
        mapContainerView.addSubview(mapExpandButton)
        mapContainerView.addSubview(locationButton)
        
        contentView.addSubview(logoutButton)
        contentView.addSubview(versionLabel)
        
        // Add floating add button last so it's on top
        view.addSubview(addCircleButton)
        
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
            usernameLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
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
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.medium),
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
            editProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.44),
            
            // Share profile button
            shareProfileButton.leadingAnchor.constraint(equalTo: editProfileButton.trailingAnchor, constant: 6),
            shareProfileButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            shareProfileButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            shareProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.44),
            
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
            
            // Separator line
            separatorLine.topAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: Constants.Spacing.medium),
            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),
            
            // Search bar
            searchBar.topAnchor.constraint(equalTo: separatorLine.bottomAnchor, constant: Constants.Spacing.small),
            searchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            searchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            // Circles header
            circlesHeaderView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Constants.Spacing.small),
            circlesHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            circlesHeaderView.heightAnchor.constraint(equalToConstant: 0), // Hide header for Instagram style
            
            circlesHeaderLabel.centerYAnchor.constraint(equalTo: circlesHeaderView.centerYAnchor),
            circlesHeaderLabel.leadingAnchor.constraint(equalTo: circlesHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            
            // Floating add button
            addCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            addCircleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            addCircleButton.widthAnchor.constraint(equalToConstant: 50),
            addCircleButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Circles collection view
            circlesCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
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
            
            // Category filter button
            categoryFilterButton.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            categoryFilterButton.centerYAnchor.constraint(equalTo: filterContainerView.centerYAnchor),
            categoryFilterButton.heightAnchor.constraint(equalToConstant: 36),
            categoryFilterButton.widthAnchor.constraint(equalToConstant: 140),
            
            // City filter button
            cityFilterButton.leadingAnchor.constraint(equalTo: categoryFilterButton.trailingAnchor, constant: Constants.Spacing.medium),
            cityFilterButton.centerYAnchor.constraint(equalTo: filterContainerView.centerYAnchor),
            cityFilterButton.heightAnchor.constraint(equalToConstant: 36),
            cityFilterButton.widthAnchor.constraint(equalToConstant: 120),
            
            // Map view
            mapView.topAnchor.constraint(equalTo: filterContainerView.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainerView.bottomAnchor),
            
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
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Create height constraint for collection view
        circlesCollectionHeightConstraint = circlesCollectionView.heightAnchor.constraint(equalToConstant: 200)
        circlesCollectionHeightConstraint?.isActive = true
        
        // Create switchable constraints for logout button
        logoutButtonTopToCollectionConstraint = logoutButton.topAnchor.constraint(equalTo: circlesCollectionView.bottomAnchor, constant: Constants.Spacing.xlarge)
        logoutButtonTopToMapConstraint = logoutButton.topAnchor.constraint(equalTo: mapContainerView.bottomAnchor, constant: Constants.Spacing.xlarge)
        
        // Initially show collection view
        logoutButtonTopToCollectionConstraint?.isActive = true
        logoutButtonTopToMapConstraint?.isActive = false
        
        // Setup filter menus
        setupCategoryFilterMenu()
        setupCityFilterMenu()
        
        // Setup collection view
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        
        // Enable drag and drop for reordering
        circlesCollectionView.dragDelegate = self
        circlesCollectionView.dropDelegate = self
        circlesCollectionView.dragInteractionEnabled = true
        
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
        suggestedButton.addTarget(self, action: #selector(suggestedButtonTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        addCircleButton.addTarget(self, action: #selector(addCircleButtonTapped), for: .touchUpInside)
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
    
    @objc private func toggleViewMode() {
        isShowingMap.toggle()
        
        // Update toggle button title
        if let toggleButton = navigationItem.rightBarButtonItems?[1] {
            toggleButton.title = isShowingMap ? "List" : "Map"
        }
        
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
    
    private func setupCategoryFilterMenu() {
        var menuActions: [UIAction] = []
        
        // Add "All Categories" option
        let allCategoriesAction = UIAction(title: "All Categories") { [weak self] _ in
            guard let self = self else { return }
            self.selectedCategory = nil
            self.categoryFilterButton.setTitle("All Categories", for: .normal)
            self.filterPlaces()
            // Refresh the menu to update checkmarks
            self.setupCategoryFilterMenu()
        }
        
        // Add checkmark for selected category
        if selectedCategory == nil {
            allCategoriesAction.state = .on
        }
        menuActions.append(allCategoriesAction)
        
        // Add available categories
        for category in availableCategories {
            let isSelected: Bool
            switch category {
            case .standard(let placeCategory):
                isSelected = selectedCategory == placeCategory
            case .custom:
                isSelected = false // Custom categories not supported in current selectedCategory
            }
            
            let action = UIAction(title: category.displayName) { [weak self] _ in
                guard let self = self else { return }
                // For now, only support standard categories in filter
                if case .standard(let placeCategory) = category {
                    self.selectedCategory = placeCategory
                    self.categoryFilterButton.setTitle(category.displayName, for: .normal)
                    self.filterPlaces()
                    // Refresh the menu to update checkmarks
                    self.setupCategoryFilterMenu()
                }
            }
            
            // Add checkmark for selected category
            if isSelected {
                action.state = .on
            }
            
            menuActions.append(action)
        }
        
        categoryFilterButton.menu = UIMenu(title: "", children: menuActions)
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
    
    private func setupCityFilterMenu() {
        // Get unique cities and count places per city
        var cityPlaceCount: [String: Int] = [:]
        
        for place in allPlaces {
            if let city = extractCityFromAddress(place.address) {
                cityPlaceCount[city, default: 0] += 1
            }
        }
        
        // Sort cities alphabetically
        let sortedCities = cityPlaceCount.keys.sorted()
        
        // Create menu options with place counts
        let cityOptions: [String?] = [nil] + sortedCities
        var cityNames: [String] = ["All Cities"]
        
        for city in sortedCities {
            let count = cityPlaceCount[city] ?? 0
            let pluralSuffix = count == 1 ? "place" : "places"
            cityNames.append("\(city) (\(count) \(pluralSuffix))")
        }
        
        var menuActions: [UIAction] = []
        
        for (index, city) in cityOptions.enumerated() {
            let action = UIAction(title: cityNames[index]) { [weak self] _ in
                guard let self = self else { return }
                self.selectedCity = city
                // Update button title - use shorter version without count for selected item
                if let city = city {
                    self.cityFilterButton.setTitle(city, for: .normal)
                } else {
                    self.cityFilterButton.setTitle("All Cities", for: .normal)
                }
                self.filterPlaces()
                // Refresh the menu to update checkmarks
                self.setupCityFilterMenu()
            }
            
            // Add checkmark for selected city
            if city == selectedCity {
                action.state = .on
            }
            
            menuActions.append(action)
        }
        
        cityFilterButton.menu = UIMenu(title: "", children: menuActions)
    }
    
    @objc private func addCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        let navController = UINavigationController(rootViewController: createCircleVC)
        present(navController, animated: true)
    }
    
    @objc private func followersStatTapped() {
        guard let user = user,
              user.id == AuthService.shared.getUserId() else {
            // Only allow owner to view their followers list
            return
        }
        
        // Show followers list
        showFollowersList(userId: user.id, listType: .followers)
    }
    
    @objc private func followingStatTapped() {
        guard let user = user,
              user.id == AuthService.shared.getUserId() else {
            // Only allow owner to view their following list
            return
        }
        
        // Show following list
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
            // Find the connection to accept
            let connections = NetworkManager.shared.connections
            guard let connection = connections.first(where: { 
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
        
        // Check if user is in current user's connections
        let connections = NetworkManager.shared.connections
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let connection = connections.first { $0.otherUserId(currentUserId: currentUserId) == user.id }
        
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
            followButton.backgroundColor = Constants.Colors.primary
            followButton.setTitleColor(.white, for: .normal)
            followButton.layer.borderWidth = 0
        } else {
            followButton.backgroundColor = .clear
            followButton.setTitleColor(Constants.Colors.primary, for: .normal)
            followButton.layer.borderWidth = 1
            followButton.layer.borderColor = Constants.Colors.primary.cgColor
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
                        // Update city filter menu with new places
                        self.setupCityFilterMenu()
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
            city: selectedCity,
            currentUserId: currentUserId
        )
        
        // Update map pins
        updateMapPins()
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
    
    private func displayUser(_ user: User) {
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
        
        // Combine full name and bio like Instagram
        var bioText = ""
        if let firstName = user.firstName, let lastName = user.lastName {
            bioText = "\(firstName) \(lastName)"
        } else if let firstName = user.firstName {
            bioText = firstName
        } else if let lastName = user.lastName {
            bioText = lastName
        }
        
        if let bio = user.bio, !bio.isEmpty {
            if !bioText.isEmpty {
                bioText += "\n\(bio)"
            } else {
                bioText = bio
            }
        }
        
        bioLabel.text = bioText.isEmpty ? nil : bioText
        
        // Show/hide buttons based on whether this is the current user
        let isCurrentUser = user.id == AuthService.shared.getUserId()
        editProfileButton.isHidden = !isCurrentUser
        shareProfileButton.isHidden = !isCurrentUser
        suggestedButton.isHidden = !isCurrentUser
        
        // For other users, check connection status and follow status
        if !isCurrentUser {
            checkConnectionAndFollowStatus()
        } else {
            // Hide connection buttons for current user
            messageButton.isHidden = true
            followButton.isHidden = true
            connectButton.isHidden = true
        }
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
                        for circle in circles {
                            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
                            totalPlaces += placeCount
                            print("   Circle '\(circle.name)': placesCount=\(circle.placesCount ?? -1), places array=\(circle.places?.count ?? 0)")
                        }
                        
                        // Update both stats
                        self.circlesStatView.configure(number: "\(circles.count)", title: "Circles")
                        self.placesStatView.configure(number: "\(totalPlaces)", title: "Places")
                        print("   Total places calculated: \(totalPlaces)")
                        
                        self.circlesCollectionView.reloadData()
                        self.updateCollectionViewHeight()
                        
                        // Load all places for search functionality
                        self.loadAllPlacesFromCircles(circles)
                    case .failure(let error):
                        self.circles = []
                        self.circlesStatView.configure(number: "0", title: "Circles")
                        self.placesStatView.configure(number: "0", title: "Places")
                        self.circlesCollectionView.reloadData()
                        self.updateCollectionViewHeight()
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
        // Fetch circles from network endpoint for other users
        let endpoint = "network/user-circles/\(userId)"
        let completion = createAPICompletion { (result: Result<UserCirclesResponse, Error>) in
            DispatchQueue.main.async {
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
        bioLabel.text = "No bio available"
        
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
        let totalHorizontalSpacing = interitemSpacing * (itemsPerRow - 1)
        let itemWidth = (view.bounds.width - totalHorizontalSpacing) / itemsPerRow
        let itemHeight = itemWidth + 50 // Square cells + 50 for labels (matching flow layout delegate)
        
        let rows = ceil(CGFloat(circles.count) / itemsPerRow)
        let totalHeight = (rows * itemHeight) + ((rows - 1) * lineSpacing)
        
        circlesCollectionHeightConstraint?.constant = max(totalHeight, 100) // Minimum height
        
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
}

// MARK: - UICollectionViewDataSource
extension ProfileViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return circles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as? CircleCell else {
            return UICollectionViewCell()
        }
        
        let circle = circles[indexPath.item]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let circle = circles[indexPath.item]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
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
        shareText += "\n🔗 Get Circles App: https://testflight.apple.com/join/n1sBRMG3"
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
        // Circular grid with 3 columns
        let spacing: CGFloat = 12
        let numberOfColumns: CGFloat = 3
        let totalSpacing = spacing * (numberOfColumns - 1)
        let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
        let itemHeight = itemWidth + 50 // Extra height for labels below circles
        return CGSize(width: itemWidth, height: itemHeight)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 16
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 12
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
        let circle = circles[indexPath.item]
        let itemProvider = NSItemProvider(object: circle.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = circle
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate
extension ProfileViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if collectionView.hasActiveDrag {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UICollectionViewDropProposal(operation: .forbidden)
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        var destinationIndexPath: IndexPath
        
        if let indexPath = coordinator.destinationIndexPath {
            destinationIndexPath = indexPath
        } else {
            let row = collectionView.numberOfItems(inSection: 0)
            destinationIndexPath = IndexPath(item: row - 1, section: 0)
        }
        
        if coordinator.proposal.operation == .move {
            self.reorderItems(coordinator: coordinator, destinationIndexPath: destinationIndexPath, collectionView: collectionView)
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
        allPlaces.removeAll()
        let dispatchGroup = DispatchGroup()
        
        for circle in circles {
            dispatchGroup.enter()
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
                guard let self = self else { 
                    dispatchGroup.leave()
                    return 
                }
                
                switch result {
                case .success(let places):
                    DispatchQueue.main.async {
                        self.allPlaces.append(contentsOf: places)
                    }
                case .failure:
                    // Continue loading other circles
                    break
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
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
        // Get unique categories from all places, including custom categories
        availableCategories = PlaceCategory.uniqueCategories(from: allPlaces)
        
        // Update the category filter menu
        setupCategoryFilterMenu()
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
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            configureSearchResultCell(cell, at: indexPath)
            return cell
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == searchResultsTableView {
            handleSearchResultSelection(at: indexPath)
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

