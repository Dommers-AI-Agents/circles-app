import UIKit
import MapKit
import CoreLocation

class ProfileViewController: BaseViewController, PlaceSearchable, FullScreenMapViewControllerDelegate {
    
    // MARK: - Properties
    var user: User? {
        didSet {
            updateOrganizeButtonVisibility()
            momentsTab.userId = user?.id
            uploadsTab.userId = user?.id
        }
    }
    var circles: [Circle] = []
    var displayItems: [CircleDisplayItem] = []
    var circleGroups: [CircleGroup] = []
    var isShowingMap = false
    var allPlaces: [Place] = []
    var filteredPlaces: [Place] = []
    var selectedCategory: PlaceCategory?
    var availableCategories: [UnifiedCategory] = []
    var selectedCity: String?
    var selectedConnectionId: String? // nil means "All Connections" (default)

    // MARK: Places lens
    //
    // How the profile is currently being viewed. Circles organise places by
    // whatever scheme made sense when they were created — city, type, person,
    // a particular trip — so `places` exists to cut across all of them at once.
    enum ProfileViewMode { case circles, map }
    var viewMode: ProfileViewMode = .circles
    var selectedPlacesGroup: PlaceCategoryGroup = .all
    // Region chips (see RegionGrouper): one per state, most places first.
    var placesRegionGroups: [RegionGroup] = []
    var selectedRegionGroupId: String?
    /// Anchor for the lens's "Near me" chip. Resolved once, never prompts.
    let lensLocationProvider = OneShotLocationProvider()
    var lensOrigin: CLLocation?
    var selectedRegionGroup: RegionGroup? {
        selectedRegionGroupId.flatMap { id in placesRegionGroups.first { $0.id == id } }
    }

    /// Opens the circle advisor. Only shown on your own profile, on the
    /// Circles segment — it has nothing to say about anyone else's circles or
    /// about the flat Places list.
    lazy var organizeCirclesButton: UIButton = {
        let button = UIButton.iconButton(systemName: "wand.and.stars", pointSize: 16)
        button.accessibilityLabel = "Organize circles"
        button.addTarget(self, action: #selector(organizeCirclesTapped), for: .touchUpInside)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    lazy var placesCategoryChipBar: CategoryChipBar = {
        let bar = CategoryChipBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    lazy var placesCityChipBar = BrowseChipBar()

    var isSearching = false
    var searchResultsHeightConstraint: NSLayoutConstraint?
    
    // MARK: - Drag & Drop Properties
    var dragAndDropEnabled = false
    
    // Request deduplication
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No circles found" }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var reloadsDataOnAppear: Bool { true }
    
    // MARK: - Public Methods
    func configureWith(user: User) {
        self.user = user
        // Don't call loadUserProfile here - let the view lifecycle handle it
        // This prevents duplicate API calls when reloadsDataOnAppear is true
    }
    
    func resetToListViewIfNeeded() {
        if viewMode != .circles {
            setViewMode(.circles)
        }
    }

    /// Returns the profile to its default state — Circles tab, list (not map),
    /// scrolled to the top, sticky bar hidden. Called when the Me tab is tapped
    /// so re-entering the profile always starts fresh.
    func resetToDefaultState() {
        // Back to the Circles tab
        if contentTypeSegmentedControl.selectedSegmentIndex != 0 {
            contentTypeSegmentedControl.selectedSegmentIndex = 0
            contentTypeChanged()
        }
        // Map → list
        resetToListViewIfNeeded()
        // Scroll to the top
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
        // Collapse the sticky tab bar (we're back at the top)
        setStickyTabBar(visible: false)
    }
    
    /// Force clear all profile picture caches and refresh the profile
    /// Call this when profile picture corruption is detected
    func forceRefreshProfileAndClearCache() {
        Logger.debug("🚨 ProfileViewController: Force clearing all profile caches and refreshing")
        
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
            Logger.debug("✅ ProfileViewController: Profile refreshed after cache clear")
            // Reload circles as well to ensure correct order
            self?.loadUserCircles()
        }
    }
    
    // MARK: - UI Elements
    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()
    
    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Profile Header Section
    let profileHeaderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let profileImageView: UIImageView = {
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
    let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Premium badge
    let premiumBadgeView: UIView = {
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

        // "i" affordance — tap the badge to see what Premium includes
        let infoIcon = UIImageView()
        infoIcon.image = UIImage(systemName: "info.circle")
        infoIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
        infoIcon.contentMode = .scaleAspectFit
        infoIcon.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(crownIcon)
        view.addSubview(label)
        view.addSubview(infoIcon)
        view.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            crownIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            crownIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crownIcon.widthAnchor.constraint(equalToConstant: 12),
            crownIcon.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: crownIcon.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            infoIcon.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            infoIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            infoIcon.widthAnchor.constraint(equalToConstant: 11),
            infoIcon.heightAnchor.constraint(equalToConstant: 11),
            infoIcon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            view.heightAnchor.constraint(equalToConstant: 24)
        ])

        return view
    }()
    
    // Place-milestone badge (Explorer, Adventurer, ... - see PlaceMilestones);
    // shown next to the name once the profile's place count reaches a tier
    let milestoneBadgeIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    let milestoneBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var milestoneBadgeView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true

        // "i" affordance — tap the badge to see all the place levels
        let infoIcon = UIImageView()
        infoIcon.image = UIImage(systemName: "info.circle")
        infoIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
        infoIcon.contentMode = .scaleAspectFit
        infoIcon.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(milestoneBadgeIcon)
        view.addSubview(milestoneBadgeLabel)
        view.addSubview(infoIcon)
        view.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            milestoneBadgeIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            milestoneBadgeIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            milestoneBadgeIcon.widthAnchor.constraint(equalToConstant: 12),
            milestoneBadgeIcon.heightAnchor.constraint(equalToConstant: 12),

            milestoneBadgeLabel.leadingAnchor.constraint(equalTo: milestoneBadgeIcon.trailingAnchor, constant: 4),
            milestoneBadgeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            infoIcon.leadingAnchor.constraint(equalTo: milestoneBadgeLabel.trailingAnchor, constant: 4),
            infoIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            infoIcon.widthAnchor.constraint(equalToConstant: 11),
            infoIcon.heightAnchor.constraint(equalToConstant: 11),
            infoIcon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            view.heightAnchor.constraint(equalToConstant: 24)
        ])

        return view
    }()

    // Milestone badge sits after the premium badge when that's showing,
    // directly after the name otherwise (hidden views still hold layout space)
    var milestoneBadgeToPremiumConstraint: NSLayoutConstraint?
    var milestoneBadgeToNameConstraint: NSLayoutConstraint?

    // Stats containers
    let topStatsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let bottomStatsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Individual stat views
    let circlesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let placesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let connectionsStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let followersStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let followingStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Bio section
    let fullNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let bioLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Location label to display home city
    let locationLabel: UILabel = {
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
    let buttonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var editProfileButton = UIButton.smallActionButton(title: "Edit profile", style: .secondary)
    
    lazy var shareProfileButton = UIButton.smallActionButton(title: "Share profile", style: .secondary)
    
    lazy var visitHistoryButton = UIButton.smallActionButton(title: "Visit History", style: .secondary)
    
    lazy var suggestedButton: UIButton = {
        let button = UIButton.iconButton(systemName: "person.badge.plus")
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        return button
    }()
    
    // Buttons for viewing other users (connections)
    lazy var messageButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Message", style: .primary)
        button.isHidden = true
        return button
    }()
    
    lazy var followButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Follow", style: .secondary)
        button.isHidden = true
        return button
    }()
    
    lazy var connectButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Connect", style: .primary)
        button.backgroundColor = Constants.Colors.secondary
        button.isHidden = true
        return button
    }()
    
    
    lazy var logoutButton = UIButton.smallActionButton(title: "Log Out", style: .danger)
    
    let versionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Notification Settings (for connected users)
    // Brand storefront card (business accounts) — sits between the profile
    // header and the circles area; pinned to zero height on normal profiles
    let storefrontCard = StorefrontCardView()
    var storefrontCardCollapsedConstraint: NSLayoutConstraint?
    var loadedStorefrontUserId: String?

    let notificationsSectionContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let notificationsSectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Notifications"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let notificationsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let notificationTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Activity Updates"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let notificationDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Get notified when they add places, share moments, or create circles"
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var activityNotificationsToggle: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true // Default to enabled
        toggle.addTarget(self, action: #selector(activityNotificationsToggled), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    // Separator line
    let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Content type segmented control
    let contentTypeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Circles", "Moments", "Uploads"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    // MARK: - Sticky tab bar
    // A mirror of the tab control (+ add-circle button) pinned to the top,
    // revealed once the profile header scrolls past it so the tabs stay
    // reachable while scrolling a long circle/uploads list.
    private lazy var stickyTabBar: ProfileStickyTabBar = {
        let bar = ProfileStickyTabBar()
        bar.segmentedControl.addTarget(self, action: #selector(stickySegmentChanged), for: .valueChanged)
        bar.addButton.addTarget(self, action: #selector(createCircleButtonTapped), for: .touchUpInside)
        return bar
    }()
    private var isStickyTabBarVisible = false


    // Search bar container
    let searchBarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Search bar
    // Search scope: the field searches places by default, circles on demand
    enum ProfileSearchScope { case places, circles }
    var profileSearchScope: ProfileSearchScope = .places
    var filteredCircles: [Circle] = []

    lazy var searchScopeButton: UIButton = {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search places..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    // Map toggle button (now next to search bar)
    /// Circles / Map.
    ///
    /// There was briefly a third "Places" segment (a filterable flat list), but
    /// it duplicated the map's list mode — so the category/state filter chips
    /// moved onto the Map view itself and the list segment went away. Circles
    /// is the default; Map is the cross-circle browse (chips + pins + a
    /// closest-first list with distances).
    lazy var mapToggleButton: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Circles", "Map"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: #selector(viewModeChanged), for: .valueChanged)
        return control
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
    let circlesHeaderView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let circlesHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "" // No text for Instagram style
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    
    let circlesCollectionView: UICollectionView = {
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
    
    var circlesCollectionHeightConstraint: NSLayoutConstraint?
    
    // Moments and Uploads are child view controllers (Controllers/Profile/Tabs)
    // sharing the circles grid's slot; they report their grid height and the
    // profile sizes them.
    lazy var momentsTab = ProfileMomentsTabViewController()
    lazy var uploadsTab = ProfileUploadsTabViewController()
    var momentsTabHeightConstraint: NSLayoutConstraint?
    var uploadsTabHeightConstraint: NSLayoutConstraint?

    /// The log-out button sits under whichever tab content is showing
    /// (circles grid, map, Moments grid, Uploads grid) — one slot, re-pinned
    /// on every tab/view-mode change.
    var logoutButtonTopConstraint: NSLayoutConstraint?

    func pinLogoutButton(below anchor: NSLayoutYAxisAnchor) {
        logoutButtonTopConstraint?.isActive = false
        let constraint = logoutButton.topAnchor.constraint(equalTo: anchor, constant: Constants.Spacing.xlarge)
        constraint.isActive = true
        logoutButtonTopConstraint = constraint
    }
    
    // Floating add button for creating circles
    lazy var floatingAddButton: UIButton = {
        let button = ProfileViewController.makeNewCircleButton()
        button.addTarget(self, action: #selector(createCircleButtonTapped), for: .touchUpInside)
        return button
    }()

    // Encompassing ring around the plus glyph so the create-circle button reads
    // as a button (sized for the 38pt constraints set at layout time)
    static func makeNewCircleButton() -> UIButton {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        b.setImage(UIImage(systemName: "plus.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = Constants.Colors.primary
        b.layer.borderWidth = 2
        b.layer.borderColor = Constants.Colors.primary.cgColor
        b.layer.cornerRadius = 19
        b.accessibilityLabel = "New circle"
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
    
    // Map view elements
    lazy var mapContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        return mapView
    }()
    
    lazy var mapExpandButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.up.left.and.arrow.down.right")
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        return button
    }()
    
    lazy var locationButton: UIButton = {
        let button = UIButton.iconButton(systemName: "location.circle.fill")
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: #selector(zoomToUserLocation), for: .touchUpInside)
        return button
    }()
    
    lazy var filterContainerView: UIView = {
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
    lazy var mapMenuChipButton: UIButton = {
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

    lazy var mapMyPlacesChipButton: UIButton = {
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

    lazy var mapListChipButton: UIButton = {
        let button = UIButton.iconButton(systemName: "list.bullet", pointSize: 15)
        button.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.separator.cgColor
        button.addTarget(self, action: #selector(mapListChipTapped), for: .touchUpInside)
        return button
    }()

    // Distance-sorted places list shown by the list/map toggle
    lazy var mapPlacesListTableView: UITableView = {
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

    var isShowingMapPlacesList = false
    var mapDistanceSortedPlaces: [(place: Place, distance: CLLocationDistance?)] = []
    let mapListDistanceFormatter = MKDistanceFormatter()
    
    // State tracking for other users
    var isFollowing: Bool = false
    var connectionStatus: ConnectionStatus?
    /// Profile, stats, circles and map-places loading.
    lazy var dataLoader: ProfileDataLoader = {
        let loader = ProfileDataLoader()
        loader.delegate = self
        return loader
    }()
    /// Follow / connect / message flows and status resolution.
    lazy var relationshipController: ProfileRelationshipController = {
        let controller = ProfileRelationshipController()
        controller.delegate = self
        return controller
    }()
    
    // Constraint references for dynamic button positioning
    var followButtonLeadingToMessageConstraint: NSLayoutConstraint?
    var followButtonLeadingToConnectConstraint: NSLayoutConstraint?
    var connectButtonLeadingConstraint: NSLayoutConstraint?
    
    // Dynamic constraints for search bar container positioning
    var searchBarContainerTopToSegmentedConstraint: NSLayoutConstraint?
    var searchBarContainerTopToSeparatorConstraint: NSLayoutConstraint?
    
    // Dynamic constraints for separator line positioning
    var separatorLineTopToProfileConstraint: NSLayoutConstraint?
    var separatorLineTopToNotificationConstraint: NSLayoutConstraint?
    
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
        
        // Always start on the circles grid
        setViewMode(.circles)
        
        // Clear any old saved view mode preference
        UserDefaults.standard.removeObject(forKey: "profileViewMode")
        
        // Register for SSE events
        SSEService.shared.addDelegate(self)

        // Sticky tab bar (revealed on scroll)
        setupStickyTabBar()
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
                    Logger.debug("🔄 ProfileViewController: Cleared profile picture cache due to potential corruption")
                    
                    // Force refresh profile data
                    loadUserProfile()
                }
            }
        }
        
        // NOTE: no viewMode reset here. "Land on Circles when navigating to the
        // Me tab" is owned by CirclesTabBarController (re-tap in shouldSelect,
        // tab-switch in didSelect) — resetting on every appearance also fired
        // when popping back from a pushed place page, yanking the user off the
        // Places/Map view they navigated from.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // StoreKit may not have resolved the subscription when the view was
        // built — re-check now that it's had time to.
        updateOrganizeButtonVisibility()

        // (The old privacy-settings tutorial bubble was removed 2026-08-19 —
        // the tour now lives entirely on the home page.)
        let isCurrentUser = user?.id == AuthService.shared.getUserId()

        // Occasional nudge to add a real photo (at most weekly; the reminder
        // owns its own gating). Only on your own profile, and never while the
        // onboarding tutorial is still running.
        if isCurrentUser && !OnboardingManager.shared.shouldShowTutorial {
            ProfilePhotoReminder.presentIfDue(from: self, user: user) { [weak self] in
                self?.editProfileButtonTapped()
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
    
    func updateAppearance() {
        // Update border colors that don't automatically adapt
        profileImageView.layer.borderColor = UIColor.separator.cgColor
        editProfileButton.layer.borderColor = UIColor.separator.cgColor
        shareProfileButton.layer.borderColor = UIColor.separator.cgColor
        visitHistoryButton.layer.borderColor = UIColor.separator.cgColor
        suggestedButton.layer.borderColor = UIColor.separator.cgColor
        let ringColor = Constants.Colors.primary.resolvedColor(with: traitCollection).cgColor
        floatingAddButton.layer.borderColor = ringColor
        stickyTabBar.addButton.layer.borderColor = ringColor
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update collection view height after layout is complete
        // This ensures the collection view has the correct width for calculations
        if !circles.isEmpty && contentTypeSegmentedControl.selectedSegmentIndex == 0 && !circlesCollectionView.isHidden {
            updateCollectionViewHeight()
        }
        
    }
    
    // MARK: - BaseViewController Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        Logger.debug("🚀 ProfileViewController: loadData called")
        Logger.debug("🚀 ProfileViewController: isLoadingData = \(isLoadingData)")
        
        // Note: BaseViewController already manages isLoadingData, so we don't need to check it here
        // BaseViewController sets isLoadingData = true before calling this method
        
        // Call loadUserProfile with completion handler
        Logger.debug("🚀 ProfileViewController: Calling loadUserProfile")
        loadUserProfile(completion: completion)
    }
    
    override func setupRefreshControl() {
        scrollView.refreshControl = refreshControl
    }
    
    // MARK: - UI Setup
    func setupUI() {
        setupNavigationBar(title: "Profile")
        
        // Add right bar button items
        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsButtonTapped))
        let videoButton = UIBarButtonItem(image: UIImage(systemName: "video.fill"), style: .plain, target: self, action: #selector(videoButtonTapped))
        let checkInButton = UIBarButtonItem(image: .checkInIcon, style: .plain, target: self, action: #selector(checkInButtonTapped))
        checkInButton.accessibilityLabel = "Check in"
        let rewardsButton = UIBarButtonItem(image: UIImage(systemName: "dollarsign.circle"), style: .plain, target: self, action: #selector(rewardsButtonTapped))
        navigationItem.rightBarButtonItems = [settingsButton, videoButton, checkInButton, rewardsButton]
        addStorefrontButtonIfEligible()

        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileHeaderView)
        profileHeaderView.addSubview(usernameLabel)
        profileHeaderView.addSubview(premiumBadgeView)
        profileHeaderView.addSubview(milestoneBadgeView)

        // Tapping a badge (via its "i") explains what it means
        premiumBadgeView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(premiumBadgeTapped)))
        milestoneBadgeView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(milestoneBadgeTapped)))
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
        
        contentView.addSubview(storefrontCard)

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
        searchBarContainer.addSubview(searchScopeButton)
        contentView.addSubview(mapToggleButton)
        contentView.addSubview(organizeCirclesButton)
        updateSearchScopeMenu()
        contentView.addSubview(circlesHeaderView)
        circlesHeaderView.addSubview(circlesHeaderLabel)
        contentView.addSubview(circlesCollectionView)
        embedGridTabs()
        
        // Add map container (initially hidden)
        contentView.addSubview(mapContainerView)

        // Filter chips (category + state) sit above the map; the old
        // hamburger/Me chips they replace are gone. The list toggle stays.
        // The list chip must be in the hierarchy BEFORE setupPlacesLens —
        // the category bar constrains its trailing edge to it.
        mapContainerView.addSubview(filterContainerView)
        filterContainerView.addSubview(mapListChipButton)
        setupPlacesLens()
        mapContainerView.addSubview(mapView)
        mapContainerView.addSubview(mapPlacesListTableView)
        mapContainerView.addSubview(mapExpandButton)
        mapContainerView.addSubview(locationButton)
        
        contentView.addSubview(logoutButton)
        contentView.addSubview(versionLabel)
        
        // Add floating add button last so it's on top
        // Add-circle button now lives beside the Circles/Moments/Uploads tabs
        // (in the scroll content) rather than as a lower-right floating button.
        contentView.addSubview(floatingAddButton)
        
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

            milestoneBadgeView.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            
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
            
            // Storefront card: zero-height until a business profile loads
            storefrontCard.topAnchor.constraint(equalTo: profileHeaderView.bottomAnchor),
            storefrontCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            storefrontCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),

            // Notification settings section
            notificationsSectionContainer.topAnchor.constraint(equalTo: storefrontCard.bottomAnchor, constant: Constants.Spacing.medium),
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
            searchBar.trailingAnchor.constraint(equalTo: searchScopeButton.leadingAnchor, constant: -4),

            searchScopeButton.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchScopeButton.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor),
            searchScopeButton.widthAnchor.constraint(equalToConstant: 32),
            searchScopeButton.heightAnchor.constraint(equalToConstant: 32),

            // Circles / Places / Map switcher — its own row. Three segments
            // cannot share the search row with the field and the scope button
            // without truncating; the old 2-state button was 60pt wide.
            mapToggleButton.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 8),
            mapToggleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            mapToggleButton.trailingAnchor.constraint(equalTo: organizeCirclesButton.leadingAnchor, constant: -8),
            mapToggleButton.heightAnchor.constraint(equalToConstant: 32),

            organizeCirclesButton.centerYAnchor.constraint(equalTo: mapToggleButton.centerYAnchor),
            organizeCirclesButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            organizeCirclesButton.widthAnchor.constraint(equalToConstant: 32),
            organizeCirclesButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Circles header
            circlesHeaderView.topAnchor.constraint(equalTo: mapToggleButton.bottomAnchor, constant: Constants.Spacing.small),
            circlesHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            circlesHeaderView.heightAnchor.constraint(equalToConstant: 0), // Hide header for Instagram style
            
            circlesHeaderLabel.centerYAnchor.constraint(equalTo: circlesHeaderView.centerYAnchor),
            circlesHeaderLabel.leadingAnchor.constraint(equalTo: circlesHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            
            
            // Circles collection view
            circlesCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Moments / Uploads tabs (same slot as the circles collection)
            momentsTab.view.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            momentsTab.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            momentsTab.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            uploadsTab.view.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            uploadsTab.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            uploadsTab.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Map container (same position as circles collection)
            mapContainerView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            mapContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mapContainerView.heightAnchor.constraint(equalToConstant: 440),

            // Filter bars above the map: category chips (with the list toggle
            // beside them) over the state chips. The chip bars themselves are
            // constrained in setupPlacesLens.
            filterContainerView.topAnchor.constraint(equalTo: mapContainerView.topAnchor),
            filterContainerView.leadingAnchor.constraint(equalTo: mapContainerView.leadingAnchor),
            filterContainerView.trailingAnchor.constraint(equalTo: mapContainerView.trailingAnchor),
            filterContainerView.heightAnchor.constraint(equalToConstant: 88),

            mapListChipButton.trailingAnchor.constraint(equalTo: filterContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            mapListChipButton.topAnchor.constraint(equalTo: filterContainerView.topAnchor, constant: 6),
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
            
            // Add-circle button: compact, just left of the tab control
            floatingAddButton.centerYAnchor.constraint(equalTo: contentTypeSegmentedControl.centerYAnchor),
            floatingAddButton.trailingAnchor.constraint(equalTo: contentTypeSegmentedControl.leadingAnchor, constant: -12),
            floatingAddButton.widthAnchor.constraint(equalToConstant: 38),
            floatingAddButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        
        // Create height constraints for collection views
        circlesCollectionHeightConstraint = circlesCollectionView.heightAnchor.constraint(equalToConstant: 400)
        circlesCollectionHeightConstraint?.isActive = true
        
        momentsTabHeightConstraint = momentsTab.view.heightAnchor.constraint(equalToConstant: 200)
        momentsTabHeightConstraint?.isActive = true
        
        uploadsTabHeightConstraint = uploadsTab.view.heightAnchor.constraint(equalToConstant: 200)
        uploadsTabHeightConstraint?.isActive = true
        
        // Create switchable constraints for logout button
        
        // Initially show collection view
        pinLogoutButton(below: circlesCollectionView.bottomAnchor)
        
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
        // Anchored below the storefront card, which sits flush with the
        // profile header at zero height on non-business profiles — so this
        // stays byte-identical to the old profileHeaderView anchor there
        separatorLineTopToProfileConstraint = separatorLine.topAnchor.constraint(
            equalTo: storefrontCard.bottomAnchor,
            constant: Constants.Spacing.medium
        )
        storefrontCardCollapsedConstraint = storefrontCard.heightAnchor.constraint(equalToConstant: 0)
        storefrontCardCollapsedConstraint?.isActive = true
        storefrontCard.isHidden = true
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
            // Other user - search bar anchored to separator. Start with the
            // compact layout (separator pinned to profile); the notification
            // section only reserves space once we know they're a connection
            searchBarContainerTopToSegmentedConstraint?.isActive = false
            searchBarContainerTopToSeparatorConstraint?.isActive = true
            separatorLineTopToNotificationConstraint?.isActive = false
            separatorLineTopToProfileConstraint?.isActive = true
            // Hide floating add button for other users
            floatingAddButton.isHidden = true
        }
        
        // Map filter menus are built on demand by the hamburger chip

        // Setup collection views
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        
        // Drag and drop disabled for now
        
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
    
    func setupDynamicButtonConstraints() {
        // Create the alternative leading constraints for follow button
        followButtonLeadingToMessageConstraint = followButton.leadingAnchor.constraint(equalTo: messageButton.trailingAnchor, constant: 6)
        followButtonLeadingToConnectConstraint = followButton.leadingAnchor.constraint(equalTo: connectButton.trailingAnchor, constant: 6)
        
        // Initially activate the constraint to message button
        followButtonLeadingToMessageConstraint?.isActive = true
    }
    
    func setupActions() {
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

        // Connections opens the same list UI. Owner-only — the API scopes
        // connections to the caller — so updateButtonVisibility() switches the
        // tap off when this profile belongs to someone else.
        let connectionsTapGesture = UITapGestureRecognizer(target: self, action: #selector(connectionsStatTapped))
        connectionsStatView.addGestureRecognizer(connectionsTapGesture)
        connectionsStatView.isUserInteractionEnabled = true


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
    
    func configureDragAndDrop() {
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
    @objc func editProfileButtonTapped() {
        let editProfileVC = EditProfileViewController()
        navigationController?.pushViewController(editProfileVC, animated: true)
    }
    
    /// Share someone ELSE's profile: universal link that opens their profile
    /// in-app when installed, preview page + App Store fallback otherwise
    @objc func shareViewedProfileTapped() {
        guard let user = user else { return }
        let shareText = "Check out \(user.displayName)'s favorite places on Circles:"
        let activityVC = UIActivityViewController(
            activityItems: [shareText, ShareLinks.user(id: user.id)],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(activityVC, animated: true)
    }

    @objc func viewedProfileModerationTapped() {
        guard let user = user else { return }
        presentUserModerationSheet(
            userId: user.id,
            userName: user.displayName,
            onBlocked: { [weak self] in
                // Blocked from their profile — nothing left to look at here
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            }
        )
    }

    @objc func shareProfileButtonTapped() {
        guard let user = user else { return }
        
        let shareProfileVC = ShareProfileViewController(user: user)
        shareProfileVC.modalPresentationStyle = .overFullScreen
        shareProfileVC.modalTransitionStyle = .crossDissolve
        present(shareProfileVC, animated: true)
    }
    
    @objc func visitHistoryButtonTapped() {
        let visitHistoryVC = VisitHistoryViewController()
        navigationController?.pushViewController(visitHistoryVC, animated: true)
    }
    
    @objc func suggestedButtonTapped() {
        shareConnectionInvite()
    }
    
    func shareConnectionInvite() {
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
    
    @objc func logoutButtonTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.logout()
        })
        
        present(alert, animated: true)
    }
    
    @objc func settingsButtonTapped() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }

    @objc func rewardsButtonTapped() {
        // The '$' hub: store-loyalty Rewards + the FavCoin piggy bank.
        let hubVC = RewardsHubViewController()
        navigationController?.pushViewController(hubVC, animated: true)
    }

    var storefrontOpensVenueAdmin = false
    private weak var storefrontClaimsDot: UIView?

    /// Store owners (and super-users) get a storefront button on their own
    /// profile — the entry point to venue management. Normal users never see
    /// it, and the consumer rewards page stays merchant-free.
    func addStorefrontButtonIfEligible() {
        RewardsService.shared.getRewardsProfile { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self,
                      self.user?.id == AuthService.shared.getUserId(),
                      case .success(let profile) = result else { return }
                let isSuper = profile.isSuperUser
                guard isSuper || profile.ownsVenues == true else { return }
                self.storefrontOpensVenueAdmin = isSuper

                let existing = self.navigationItem.rightBarButtonItems ?? []
                if !existing.contains(where: { $0.accessibilityLabel == "My Storefront" }) {
                    // Custom view so a pending-claims dot can sit on the icon
                    let button = UIButton.iconButton(systemName: "storefront", pointSize: 19)
                    button.tintColor = Constants.Colors.primary
                    button.addTarget(self, action: #selector(self.storefrontButtonTapped), for: .touchUpInside)

                    let dot = UIView()
                    dot.backgroundColor = .systemRed
                    dot.layer.cornerRadius = 4.5
                    dot.isHidden = true
                    dot.isUserInteractionEnabled = false
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(dot)
                    NSLayoutConstraint.activate([
                        button.widthAnchor.constraint(equalToConstant: 30),
                        button.heightAnchor.constraint(equalToConstant: 30),
                        dot.widthAnchor.constraint(equalToConstant: 9),
                        dot.heightAnchor.constraint(equalToConstant: 9),
                        dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
                        dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1)
                    ])
                    self.storefrontClaimsDot = dot

                    let storefrontButton = UIBarButtonItem(customView: button)
                    storefrontButton.accessibilityLabel = "My Storefront"
                    self.navigationItem.rightBarButtonItems = existing + [storefrontButton]
                }
                self.refreshStorefrontClaimsDot()
            }
        }
    }

    /// Red dot on the storefront icon while ownership claims await review —
    /// super-users only; it mirrors the claims tray in venue admin.
    private func refreshStorefrontClaimsDot() {
        guard storefrontOpensVenueAdmin else { return }
        RewardsService.shared.listClaims(status: "pending") { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let claims) = result else { return }
                self?.storefrontClaimsDot?.isHidden = claims.isEmpty
            }
        }
    }

    @objc func storefrontButtonTapped() {
        let destination: UIViewController = storefrontOpensVenueAdmin
            ? VenueAdminViewController()
            : OwnerVenuesViewController()
        navigationController?.pushViewController(destination, animated: true)
    }
    
    @objc func videoButtonTapped() {
        let contentUploadVC = ContentUploadViewController()
        contentUploadVC.delegate = self
        let navController = UINavigationController(rootViewController: contentUploadVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc func checkInButtonTapped() {
        let checkInVC = CheckInViewController()
        let navController = UINavigationController(rootViewController: checkInVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc func contentTypeChanged() {
        let isCurrentUser = user?.id == AuthService.shared.getUserId()
        
        if contentTypeSegmentedControl.selectedSegmentIndex == 0 {
            // Show circles
            circlesCollectionView.isHidden = isShowingMap
            momentsTab.setActive(false)
            uploadsTab.setActive(false)
            searchBar.placeholder = "Search places..."
            mapToggleButton.isHidden = false
            
            // Show floating add button for current user on Circles tab
            floatingAddButton.isHidden = !isCurrentUser
            
            // Ensure map container visibility matches current state
            mapContainerView.isHidden = !isShowingMap
            
            // Update circles collection height
            updateCollectionViewHeight()
            
            // Update logout button constraint
            pinLogoutButton(below: isShowingMap ? mapContainerView.bottomAnchor : circlesCollectionView.bottomAnchor)

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
            Logger.debug("📹 Switching to Moments tab")
            
            circlesCollectionView.isHidden = true
            uploadsTab.setActive(false)
            mapContainerView.isHidden = true
            searchBar.placeholder = "Search videos..."
            mapToggleButton.isHidden = true
            
            // Hide floating add button on Moments tab
            floatingAddButton.isHidden = true
            
            // Loads on first visit, re-renders after
            momentsTab.setActive(true)
            
            // Update logout button constraint to videos collection
            pinLogoutButton(below: momentsTab.view.bottomAnchor)
        } else {
            // Show uploads (tab index 2)
            Logger.debug("📷 Switching to Uploads tab")
            
            circlesCollectionView.isHidden = true
            momentsTab.setActive(false)
            mapContainerView.isHidden = true
            searchBar.placeholder = "Search uploads..."
            mapToggleButton.isHidden = true
            
            // Hide floating add button on Uploads tab
            floatingAddButton.isHidden = true
            
            // Loads on first visit, re-renders after
            uploadsTab.setActive(true)
            
            // Update logout button constraint to uploads collection
            pinLogoutButton(below: uploadsTab.view.bottomAnchor)
        }

        // Keep the sticky mirror (selection + add-button visibility) in step
        syncStickyTabBar()
    }

    /// Shows the wand only on your own Circles view, and only for Premium.
    ///
    /// The server enforces the Premium gate regardless (a free account that got
    /// here would hit the paywall), but hiding the control is kinder than
    /// offering something that can only end in an upsell.
    ///
    /// Called from three places because its three inputs resolve at different
    /// times on a cold launch: the segment (setViewMode), the profile user
    /// (didSet — loads async), and the StoreKit subscription (viewDidAppear —
    /// resolves whenever StoreKit gets around to it). Checking only at
    /// setViewMode meant the wand stayed hidden until the segments were
    /// toggled after everything had loaded.
    func updateOrganizeButtonVisibility() {
        let isOwnProfile = user?.id == AuthService.shared.getUserId()
        let isPremium = SubscriptionManager.shared.isSubscribed
        organizeCirclesButton.isHidden = (viewMode != .circles) || !isOwnProfile || !isPremium
    }

    @objc func handleSubscriptionStatusChanged() {
        Task { @MainActor in
            updateOrganizeButtonVisibility()
            if let user = user, user.id == AuthService.shared.getUserId() {
                premiumBadgeView.isHidden = !SubscriptionManager.shared.isSubscribed
                updateMilestoneBadge(placeCount: lastKnownPlaceCount)
            }
        }
    }

    @objc func organizeCirclesTapped() {
        let organizeVC = OrganizeCirclesViewController(circles: circles)
        let nav = UINavigationController(rootViewController: organizeVC)
        present(nav, animated: true)
    }

    @objc func viewModeChanged() {
        switch mapToggleButton.selectedSegmentIndex {
        case 1: setViewMode(.map)
        default: setViewMode(.circles)
        }
    }

    func setViewMode(_ mode: ProfileViewMode) {
        viewMode = mode
        isShowingMap = (mode == .map)

        if let index = [ProfileViewMode.circles, .map].firstIndex(of: mode) {
            mapToggleButton.selectedSegmentIndex = index
        }

        circlesCollectionView.isHidden = (mode != .circles)
        updateOrganizeButtonVisibility()
        mapContainerView.isHidden = (mode != .map)

        pinLogoutButton(below: mode == .map ? mapContainerView.bottomAnchor : circlesCollectionView.bottomAnchor)

        if mode == .map {
            if allPlaces.isEmpty {
                loadAllPlaces()
            } else {
                filterPlaces()
                refreshPlacesLensChips()
            }
        }

        // Update scroll view layout
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }

        // The fit computed while the map was still hidden used a stale frame —
        // redo it once the map is actually on screen so the zoom matches the
        // filtered pins (Arizona filter -> Arizona, not the whole US).
        if mode == .map {
            DispatchQueue.main.async { [weak self] in
                self?.zoomMapToFilteredPins(animated: false)
            }
        }

        // Note: We don't save view mode preference - always default to circles
    }
    
    /// Builds the hamburger chip's menu: Connections, Category and City
    /// submenus — the same structure as the home page map's menu, with the
    /// profile-specific City filter added. Rebuilt fresh on every open.
    func buildProfileMapMenuElements() -> [UIMenuElement] {
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

        // City submenu (profile-specific). lensCity prefers the server-derived
        // city and never returns a ZIP or country fragment.
        var cityPlaceCount: [String: Int] = [:]
        for place in allPlaces {
            if let city = place.lensCity {
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

    @objc func mapMyPlacesChipTapped() {
        selectedConnectionId = (selectedConnectionId == "my_places_only") ? nil : "my_places_only"
        updateMapMyPlacesChipAppearance()
        filterPlaces()
    }

    func updateMapMyPlacesChipAppearance() {
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

    @objc func mapListChipTapped() {
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
    func rebuildMapDistanceSortedPlaces() {
        let reference = mapView.userLocation.location
            ?? CLLocation(latitude: mapView.region.center.latitude, longitude: mapView.region.center.longitude)

        mapDistanceSortedPlaces = DistancePlaceSorter.sorted(filteredPlaces, from: reference)

        if mapDistanceSortedPlaces.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = emptyPlacesExplanation()
            emptyLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            emptyLabel.textColor = Constants.Colors.secondaryLabel
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            mapPlacesListTableView.backgroundView = emptyLabel
        } else {
            mapPlacesListTableView.backgroundView = nil
        }
    }

    /// A bare "No places to show" on an unconnected profile reads as "this
    /// person has nothing" when the truth is "their places are hidden until
    /// you connect" — say the true thing (2026-08-15 launch-night confusion:
    /// bianchifit's places existed but looked like zero to everyone).
    private func emptyPlacesExplanation() -> String {
        guard let user = user, user.id != AuthService.shared.getUserId() else {
            return "No places to show"
        }
        let name = user.displayName.components(separatedBy: " ").first ?? user.displayName
        switch RelationshipTier(user: user) {
        case .requestReceived:
            return "\(name) wants to connect!\nAccept their request to see the places they share with their network."
        case .requestSent:
            return "You'll see \(name)'s network-only places\nonce they accept your request."
        case .connected:
            return "No places to show"
        default:
            return "Connect with \(name)\nto see the places they share with their network."
        }
    }
    
    @objc func followersStatTapped() {
        guard let user = user else { return }
        
        // Allow viewing any user's followers list
        // This enables social discovery through connections' networks
        showFollowersList(userId: user.id, listType: .followers)
    }
    
    @objc func followingStatTapped() {
        guard let user = user else { return }
        
        // Allow viewing any user's following list
        // This enables social discovery through connections' networks
        showFollowersList(userId: user.id, listType: .following)
    }
    
    @objc func connectionsStatTapped() {
        guard let currentUserId = AuthService.shared.getUserId() else { return }

        // Own profile only: `GET /connections` always returns the caller's own
        // connections, so there's nothing to show for another user.
        let profileUserId = user?.id ?? currentUserId
        guard IDNormalizer.isSameUser(profileUserId, currentUserId) else { return }

        showFollowersList(userId: currentUserId, listType: .connections)
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    func showFollowersList(userId: String, listType: FollowListType) {
        let followersVC = FollowersListViewController()
        followersVC.userId = userId
        followersVC.listType = listType
        navigationController?.pushViewController(followersVC, animated: true)
    }
    
    @objc func profileImageTapped() {
        // Show full-screen profile image
        if let profileImageURL = user?.profilePicture {
            ImageViewerService.shared.presentImageFromURL(profileImageURL, from: self)
        } else if let currentImage = profileImageView.image {
            ImageViewerService.shared.presentImage(currentImage, from: self)
        }
    }
    
    @objc func messageButtonTapped() {
        relationshipController.messageTapped()
    }

    @objc func followButtonTapped() {
        relationshipController.followTapped()
    }

    @objc func connectButtonTapped() {
        relationshipController.connectTapped()
    }

    @objc func expandMapButtonTapped() {
        // Expand with the SAME chips as the small map: pass all places and seed
        // the current selections, so the large view opens showing exactly this
        // filter but can broaden it as well as narrow it. The hamburger is
        // replaced by the chip bars (showsFilterChips).
        let fullScreenMapVC = FullScreenMapViewController(
            places: allPlaces,
            initialRegion: mapView.region,
            selectedCategory: nil,
            selectedConnectionId: nil
        )
        fullScreenMapVC.delegate = self
        fullScreenMapVC.viewMode = .allPlaces
        fullScreenMapVC.isPresentedModally = true
        // A profile map shows one person's places — no network-connection
        // filter/avatar strip; filtering is the chip bars.
        fullScreenMapVC.showsConnectionFilter = false
        fullScreenMapVC.showsFilterChips = true
        fullScreenMapVC.initialChipGroup = selectedPlacesGroup
        fullScreenMapVC.initialChipRegionId = selectedRegionGroupId

        let navigationController = UINavigationController(rootViewController: fullScreenMapVC)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
    
    @objc func createCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        
        present(navController, animated: true, completion: nil)
    }
    
    @objc func activityNotificationsToggled() {
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
            Logger.debug("❌ No connection found for user: \(user.id)")
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
    
    func updateConnectionNotificationPreference(connectionId: String, enabled: Bool, completion: @escaping (Bool) -> Void) {
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
                Logger.debug("✅ Connection notification preference updated: \(response.success)")
                completion(response.success)
            case .failure(let error):
                Logger.debug("❌ Failed to update connection notification preference: \(error)")
                completion(false)
            }
        }
    }
    
    @objc func zoomToUserLocation() {
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
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func checkConnectionAndFollowStatus() {
        relationshipController.checkConnectionAndFollowStatus()
    }

    func updateLocalFollowingCount(increment: Bool) {
        guard let currentUserId = AuthService.shared.getUserId(),
              let user = self.user else { return }

        // On someone else's profile, the stat that changes is THEIR followers —
        // you just became (or stopped being) one. This used to bail out here,
        // so their numbers sat frozen until a pull-to-refresh.
        guard user.id == currentUserId else {
            let currentCount = user.followersCount ?? 0
            let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)
            followersStatView.configure(number: "\(newCount)", title: "Followers")
            self.user = user.copy(followersCount: newCount)
            return
        }

        // Own profile: the Following stat moves.
        let currentCount = user.followingCount ?? 0
        let newCount = increment ? currentCount + 1 : max(0, currentCount - 1)
        
        // Update the UI immediately
        followingStatView.configure(number: "\(newCount)", title: "Following")
        
        // Update the cached user data
        self.user = user.copy(followingCount: newCount)
        
        Logger.debug("📊 Updated local following count: \(currentCount) → \(newCount)")
    }
    
    func updateButtonVisibility() {
        guard let user = user else { return }
        let isCurrentUser = user.id == AuthService.shared.getUserId()

        // Only your own Connections stat opens a list; there's no endpoint for
        // another user's connections.
        connectionsStatView.isUserInteractionEnabled = isCurrentUser

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
            // Pending connections: Show connect button with appropriate state.
            // Receivers of a request see Accept only — no Follow shortcut
            // (accepting auto-follows; following someone you declined is a
            // separate, deliberate action). Senders keep the follow button,
            // which reads "Following" since connect implies follow.
            messageButton.isHidden = true
            connectButton.isHidden = false
            followButton.isHidden = user.connectionDirection == "incoming"

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
        
        // Update follow button appearance based on follow status. When they
        // already follow you, say so — "Follow Back" carries the fact that
        // this person opted in first, which is the best reason to reciprocate.
        let followsMe = user.followsYou ?? false
        let followTitle = isFollowing ? "Following" : (followsMe ? "Follow Back" : "Follow")
        followButton.setTitle(followTitle, for: .normal)
        if isFollowing {
            followButton.setStyle(.following)
        } else if followsMe {
            // Their move is already made — render ours as the primary action.
            followButton.setStyle(.primary)
        } else {
            followButton.setStyle(.secondary)
        }
        
        // Show/hide notifications section based on connection status
        let shouldShowNotifications = !isCurrentUser && isConnected
        notificationsSectionContainer.isHidden = !shouldShowNotifications

        // Re-pin the separator so the hidden section doesn't reserve space on
        // non-connected profiles (a hidden view keeps its Auto Layout height)
        if !isCurrentUser {
            if shouldShowNotifications {
                separatorLineTopToProfileConstraint?.isActive = false
                separatorLineTopToNotificationConstraint?.isActive = true
            } else {
                separatorLineTopToNotificationConstraint?.isActive = false
                separatorLineTopToProfileConstraint?.isActive = true
            }
        }
        
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
    func loadAllPlaces() {
        // Load places from all circles
        allPlaces.removeAll()
        dataLoader.loadAllPlaces()
    }

    func filterPlaces() {
        // Use centralized filtering extensions
        let unifiedCategory = selectedCategory.map { UnifiedCategory.standard($0) }
        let currentUserId = AuthService.shared.getUserId() ?? ""

        filteredPlaces = allPlaces.filtered(
            category: unifiedCategory,
            connectionId: selectedConnectionId,
            city: selectedCity,
            currentUserId: currentUserId
        )

        // Places-lens filters apply here too, so switching to the Map tab shows
        // exactly the places the lens is filtered to.
        if let group = selectedRegionGroup {
            filteredPlaces = filteredPlaces.filter { group.contains($0) }
        }
        if selectedPlacesGroup != .all {
            filteredPlaces = filteredPlaces.filter { selectedPlacesGroup.matches($0.category.rawValue) }
        }

        // Update map pins
        updateMapPins()

        // Keep the distance-sorted list in sync when it's visible
        if isShowingMapPlacesList {
            rebuildMapDistanceSortedPlaces()
            mapPlacesListTableView.reloadData()
        }
    }
    
    func updateMapPins() {
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)

        // Add filtered places as pins using PlaceAnnotation for custom styling
        for place in filteredPlaces {
            if place.location?.clLocation != nil {
                let annotation = PlaceAnnotation(place: place)
                mapView.addAnnotation(annotation)
            }
        }

        zoomMapToFilteredPins(animated: true)
    }

    /// Fits the map to exactly the filtered pins: an Arizona filter fills the
    /// screen with Arizona, a coast-to-coast result shows the country. Padded
    /// so edge pins aren't glued to the frame; a single pin gets a city-scale
    /// span instead of a useless max-zoom.
    func zoomMapToFilteredPins(animated: Bool) {
        let annotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        guard !annotations.isEmpty else { return }

        if annotations.count == 1, let only = annotations.first {
            let region = MKCoordinateRegion(
                center: only.coordinate,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            )
            mapView.setRegion(region, animated: animated)
            return
        }

        var union = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            union = union.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        let padding = UIEdgeInsets(top: 56, left: 40, bottom: 40, right: 40)
        mapView.setVisibleMapRect(union, edgePadding: padding, animated: animated)
    }
    
    
    func loadUserProfile(completion: (() -> Void)? = nil) {
        dataLoader.loadUserProfile(completion: completion)
    }

    func fetchFreshUserData(completion: (() -> Void)? = nil) {
        dataLoader.fetchFreshUserData(completion: completion)
    }

    // MARK: - Moments (forwarded to the Moments tab)

    /// Fetched alongside the profile so the Moments grid is ready when the
    /// tab is switched to; the tab only re-renders while visible.
    func fetchUserVideos() {
        momentsTab.fetchVideos()
    }

    // MARK: - Storefront card (brand accounts)

    /// Loads the profile user's public storefront and expands the card when
    /// one exists. Non-business accounts return storefront: null and the card
    /// stays collapsed — one cheap call per profile view.
    func refreshStorefrontCard() {
        let profileUserId = user?.id ?? AuthService.shared.getUserId()
        guard let userId = profileUserId else { return }
        // Same profile already loaded — don't flicker on every displayUser pass
        if loadedStorefrontUserId == userId, storefrontCard.isHidden == false { return }

        RewardsService.shared.getStorefront(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Profile may have been reconfigured while the read was in flight
                let currentId = self.user?.id ?? AuthService.shared.getUserId()
                guard currentId == userId else { return }
                self.loadedStorefrontUserId = userId

                guard case .success(let data) = result, let storefront = data.storefront else {
                    self.setStorefrontCardVisible(false)
                    return
                }
                let isOwn = self.user == nil || IDNormalizer.isSameUser(userId, AuthService.shared.getUserId() ?? "")
                self.storefrontCard.configure(
                    storefront: storefront,
                    findUsAtCircle: data.findUsAtCircle,
                    venues: data.venues,
                    isOwnProfile: isOwn
                )
                self.wireStorefrontCardActions(storefront: storefront, findUsAtCircle: data.findUsAtCircle)
                self.setStorefrontCardVisible(true)
            }
        }
    }

    private func setStorefrontCardVisible(_ visible: Bool) {
        storefrontCard.isHidden = !visible
        storefrontCardCollapsedConstraint?.isActive = !visible
        view.layoutIfNeeded()
    }

    private func wireStorefrontCardActions(storefront: StorefrontInfo, findUsAtCircle: StorefrontCircleSummary?) {
        storefrontCard.onWebsite = { [weak self] in
            self?.openStorefrontLink(storefront.website)
        }
        storefrontCard.onCatalog = { [weak self] in
            self?.openStorefrontLink(storefront.catalogUrl)
        }
        storefrontCard.onFindUsAt = { [weak self] in
            guard let self = self, let circleId = findUsAtCircle?.id else { return }
            CircleService.shared.fetchCircleById(id: circleId) { result in
                DispatchQueue.main.async {
                    guard case .success(let circle) = result else { return }
                    let detailVC = CircleDetailViewController(circle: circle)
                    self.navigationController?.pushViewController(detailVC, animated: true)
                }
            }
        }
        storefrontCard.onOffers = { [weak self] in
            // Store offers live in the rewards hub
            let hub = RewardsHubViewController()
            hub.initialTab = .rewards
            self?.navigationController?.pushViewController(hub, animated: true)
        }
        storefrontCard.onEdit = { [weak self] in
            guard let self = self else { return }
            let editor = StorefrontEditViewController()
            editor.initialStorefront = storefront
            editor.initialFindUsAtCircleId = findUsAtCircle?.id
            editor.onSaved = { [weak self] in
                self?.loadedStorefrontUserId = nil
                self?.refreshStorefrontCard()
            }
            self.navigationController?.pushViewController(editor, animated: true)
        }
    }

    private func openStorefrontLink(_ urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    func displayUser(_ user: User) {
        // Debug logging
        Logger.debug("🔍 ProfileViewController - Displaying user data:")
        Logger.debug("   - Display Name: \(user.displayName)")
        Logger.debug("   - First Name: \(user.firstName ?? "nil")")
        Logger.debug("   - Last Name: \(user.lastName ?? "nil")")
        Logger.debug("   - Phone Number: \(user.phoneNumber ?? "nil")")
        Logger.debug("   - Bio: \(user.bio ?? "nil")")
        Logger.debug("   - Location: \(user.location ?? "nil")")
        Logger.debug("   - Circles Count: \(user.circlesCount ?? 0)")
        Logger.debug("   - Places Count: \(user.placesCount ?? 0)")
        
        // Display initial counts from user object if available (for new users)
        // This ensures counts show immediately after registration
        if let circlesCount = user.circlesCount {
            circlesStatView.configure(number: "\(circlesCount)", title: "Circles")
        }
        if let placesCount = user.placesCount {
            placesStatView.configure(number: "\(placesCount)", title: "Places")
            updateMilestoneBadge(placeCount: placesCount)
        }
        
        // Update UI with user data
        if let profileImageUrl = user.profilePicture {
            // In a real app, load image from URL
            ImageService.shared.loadImage(from: profileImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Keep the initials avatar when the photo fails rather
                    // than falling back to an anonymous silhouette
                    if let image = image { self.profileImageView.image = image }
                    if image == nil {
                        self.profileImageView.tintColor = Constants.Colors.primary
                    }
                }
            }
        } else {
            profileImageView.image = AvatarPlaceholder.image(name: user.displayName, seed: user.id, diameter: 100)
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
                // Re-anchor the milestone badge now that premium visibility is known
                updateMilestoneBadge(placeCount: lastKnownPlaceCount)
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
                Logger.debug("📐 Switched to current user layout - no notification section space")
            } else {
                // Other user - search bar anchored to separator. Only pin the
                // separator below the notification section for accepted
                // connections; a hidden section still holds its Auto Layout
                // height and left a large gap on non-connected profiles
                self.searchBarContainerTopToSegmentedConstraint?.isActive = false
                self.searchBarContainerTopToSeparatorConstraint?.isActive = true
                if self.connectionStatus == .accepted {
                    self.separatorLineTopToProfileConstraint?.isActive = false
                    self.separatorLineTopToNotificationConstraint?.isActive = true
                } else {
                    self.separatorLineTopToNotificationConstraint?.isActive = false
                    self.separatorLineTopToProfileConstraint?.isActive = true
                }
                Logger.debug("📐 Switched to other-user layout - notification space only when connected")
            }
            self.view.layoutIfNeeded()
        }
        
        // Update navigation bar items based on profile type
        if isCurrentUser {
            // Current user - show settings and video buttons
            let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsButtonTapped))
            let videoButton = UIBarButtonItem(image: UIImage(systemName: "video.fill"), style: .plain, target: self, action: #selector(videoButtonTapped))
            let checkInButton = UIBarButtonItem(image: .checkInIcon, style: .plain, target: self, action: #selector(checkInButtonTapped))
            checkInButton.accessibilityLabel = "Check in"
            let rewardsButton = UIBarButtonItem(image: UIImage(systemName: "dollarsign.circle"), style: .plain, target: self, action: #selector(rewardsButtonTapped))
            navigationItem.rightBarButtonItems = [settingsButton, videoButton, checkInButton, rewardsButton]
            addStorefrontButtonIfEligible()
        } else {
            // Other user - share button (profile universal link) plus the
            // report/block "⋯" menu (App Review 1.2: abusive users must be
            // reportable and blockable from their profile)
            let shareButton = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain,
                target: self,
                action: #selector(shareViewedProfileTapped)
            )
            shareButton.accessibilityLabel = "Share profile"
            let moderationButton = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                style: .plain,
                target: self,
                action: #selector(viewedProfileModerationTapped)
            )
            moderationButton.accessibilityLabel = "Report or block"
            navigationItem.rightBarButtonItems = [moderationButton, shareButton]
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
        
        // Only show the activity notifications section for accepted connections
        // (updateConnectionUI re-evaluates once the status loads)
        notificationsSectionContainer.isHidden = isCurrentUser || connectionStatus != .accepted
        
        // Configure drag and drop based on whether this is the current user
        configureDragAndDrop()

        refreshStorefrontCard()
    }
    
    var lastKnownPlaceCount = 0

    /// Shows the place-milestone badge (see PlaceMilestones) next to the name,
    /// after the premium badge when that's visible. Hidden below the first tier.
    func updateMilestoneBadge(placeCount: Int) {
        lastKnownPlaceCount = placeCount
        if milestoneBadgeToPremiumConstraint == nil {
            milestoneBadgeToPremiumConstraint = milestoneBadgeView.leadingAnchor.constraint(
                equalTo: premiumBadgeView.trailingAnchor, constant: 6)
            milestoneBadgeToNameConstraint = milestoneBadgeView.leadingAnchor.constraint(
                equalTo: usernameLabel.trailingAnchor, constant: 8)
        }

        guard let milestone = PlaceMilestones.badge(for: placeCount) else {
            milestoneBadgeView.isHidden = true
            milestoneBadgeToPremiumConstraint?.isActive = false
            milestoneBadgeToNameConstraint?.isActive = false
            return
        }

        milestoneBadgeView.isHidden = false
        milestoneBadgeView.backgroundColor = milestone.color
        milestoneBadgeIcon.image = UIImage(systemName: milestone.iconName)
        milestoneBadgeLabel.text = milestone.name.uppercased()

        if premiumBadgeView.isHidden {
            milestoneBadgeToPremiumConstraint?.isActive = false
            milestoneBadgeToNameConstraint?.isActive = true
        } else {
            milestoneBadgeToNameConstraint?.isActive = false
            milestoneBadgeToPremiumConstraint?.isActive = true
        }
    }

    // Tapping the place-level badge shows every tier, with the current one
    // highlighted, so people can see what they've earned and what's next.
    @objc func milestoneBadgeTapped() {
        let current = PlaceMilestones.badge(for: lastKnownPlaceCount)
        let rows = PlaceMilestones.all.map { tier in
            BadgeInfoViewController.Row(
                iconName: tier.iconName,
                iconColor: tier.color,
                title: tier.name,
                subtitle: "\(tier.threshold)+ places",
                isCurrent: current?.threshold == tier.threshold
            )
        }
        let vc = BadgeInfoViewController(
            title: "Place Levels",
            subtitle: "Earn a new badge as you save more places. Your current badge shows next to your name.",
            rows: rows
        )
        present(vc, animated: true)
    }

    // Tapping the premium badge shows what the subscription includes.
    @objc func premiumBadgeTapped() {
        let rows = PremiumFeatures.features.map { feature in
            BadgeInfoViewController.Row(
                iconName: feature.iconName,
                iconColor: Constants.Colors.primary,
                title: feature.title,
                subtitle: feature.description
            )
        }
        let vc = BadgeInfoViewController(
            title: "FavCircles Premium",
            subtitle: "Thanks for being a member — here's what's included:",
            rows: rows
        )
        present(vc, animated: true)
    }

    func fetchUserStats(userId: String) {
        dataLoader.fetchUserStats(userId: userId)
    }

    func fetchOtherUserCircles(userId: String) {
        dataLoader.fetchOtherUserCircles(userId: userId)
    }

    func displayDefaultProfile() {
        // Fallback default display
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = Constants.Colors.primary
        
        usernameLabel.text = "User"
        locationLabel.isHidden = true
        bioLabel.text = "No bio available"
        bioLabel.isHidden = false
        
        circlesStatView.configure(number: "0", title: "Circles")
        placesStatView.configure(number: "0", title: "Places")
        updateMilestoneBadge(placeCount: 0)
        connectionsStatView.configure(number: "0", title: "Connections")
        followersStatView.configure(number: "0", title: "Followers")
        followingStatView.configure(number: "0", title: "Following")
    }
    
    func displayAppVersion() {
        // Get app version from Info.plist
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        versionLabel.text = "Version \(appVersion) (\(buildNumber))"
    }
    
    func setupNotificationObservers() {
        // Premium resolves asynchronously after launch, so the badge and the
        // AI-organize wand must both react to it rather than being computed at
        // whatever moment their screen happened to build.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubscriptionStatusChanged),
            name: .subscriptionStatusChanged,
            object: nil
        )

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
    
    @objc func handleCircleDeleted(_ notification: Notification) {
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
    
    @objc func handleRefreshCircles() {
        // Refresh user stats to get updated circle counts
        if let userId = self.user?.id {
            fetchUserStats(userId: userId)
        }
    }
    
    @objc func handleConnectionsLoaded() {
        // Update connections count when NetworkManager finishes loading
        if let userId = self.user?.id, userId == AuthService.shared.getUserId() {
            let connectionsCount = NetworkManager.shared.connections.count
            Logger.debug("🔍 ProfileViewController - Updated connections count after load: \(connectionsCount)")
            connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
        }
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
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
    
    @objc func keyboardWillHide(_ notification: Notification) {
        guard let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        UIView.animate(withDuration: animationDuration) {
            self.scrollView.contentInset = .zero
            self.scrollView.scrollIndicatorInsets = .zero
        }
    }
    
    func logout() {
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
    
    func updateCollectionViewHeight() {
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
        
        Logger.debug("🔍 ProfileViewController - Updating circles collection height:")
        Logger.debug("   - Circles count: \(circles.count)")
        Logger.debug("   - Rows needed: \(rows)")
        Logger.debug("   - Collection width: \(collectionWidth)")
        Logger.debug("   - Item dimensions: \(itemWidth) x \(itemHeight)")
        Logger.debug("   - Total calculated height: \(totalHeight)")
        Logger.debug("   - Final height: \(finalHeight)")
        
        circlesCollectionHeightConstraint?.constant = finalHeight
        
        // Force layout update for both collection view and scroll view
        UIView.animate(withDuration: 0.3) {
            self.circlesCollectionView.layoutIfNeeded()
            self.scrollView.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Sticky tab bar

    private func setupStickyTabBar() {
        view.addSubview(stickyTabBar)

        NSLayoutConstraint.activate([
            stickyTabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stickyTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stickyTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        view.bringSubviewToFront(stickyTabBar)
        scrollView.delegate = self
    }

    @objc private func stickySegmentChanged() {
        contentTypeSegmentedControl.selectedSegmentIndex = stickyTabBar.segmentedControl.selectedSegmentIndex
        contentTypeChanged()
    }

    /// Keeps the sticky bar's selection and add-button visibility mirrored to
    /// the inline controls. Call after any inline tab/visibility change.
    func syncStickyTabBar() {
        stickyTabBar.segmentedControl.selectedSegmentIndex = contentTypeSegmentedControl.selectedSegmentIndex
        // Add-circle only on the Circles tab; mirror the inline button's state
        stickyTabBar.addButton.isHidden = floatingAddButton.isHidden
    }

    private func setStickyTabBar(visible: Bool) {
        guard visible != isStickyTabBarVisible else { return }
        isStickyTabBarVisible = visible
        syncStickyTabBar()
        if visible { stickyTabBar.isHidden = false }
        UIView.animate(withDuration: 0.15, animations: {
            self.stickyTabBar.alpha = visible ? 1 : 0
        }, completion: { _ in
            if !visible { self.stickyTabBar.isHidden = true }
        })
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only the main profile scroll drives the sticky bar — the collection
        // views are also delegates of self and fire this too.
        guard scrollView == self.scrollView else { return }
        // Never stick while at (or above) the top. This also avoids a transient
        // false reveal on first layout: scrollViewDidScroll fires while content
        // sizes settle, when the inline control's converted frame isn't final
        // yet — which used to show the sticky bar on first visit at offset 0.
        guard scrollView.contentOffset.y > 1 else {
            setStickyTabBar(visible: false)
            return
        }
        // Reveal once the inline tab control has scrolled up under the top edge.
        let controlFrame = contentTypeSegmentedControl.convert(contentTypeSegmentedControl.bounds, to: view)
        setStickyTabBar(visible: controlFrame.minY <= view.safeAreaInsets.top)
    }

    // MARK: - Grid tab hosting

    /// Adds the Moments and Uploads tabs as child view controllers in the
    /// circles grid's slot. Both start hidden; contentTypeChanged shows the
    /// selected one. Each reports its grid height; the profile animates the
    /// slot to fit (the old inline updateXCollectionHeight behaviour).
    private func embedGridTabs() {
        for tab in [momentsTab, uploadsTab] as [ProfileGridTabViewController] {
            addChild(tab)
            tab.view.translatesAutoresizingMaskIntoConstraints = false
            tab.view.isHidden = true
            contentView.addSubview(tab.view)
            tab.didMove(toParent: self)
        }
        momentsTab.onContentHeightChanged = { [weak self] height in
            self?.momentsTabHeightConstraint?.constant = height
            UIView.animate(withDuration: 0.3) { self?.view.layoutIfNeeded() }
        }
        uploadsTab.onContentHeightChanged = { [weak self] height in
            self?.uploadsTabHeightConstraint?.constant = height
            UIView.animate(withDuration: 0.3) { self?.view.layoutIfNeeded() }
        }
    }
}

// MARK: - ProfileRelationshipControllerDelegate

/// `user`, `isFollowing`, `connectionStatus`, `followButton`, the button
/// renderer and the alert helpers already satisfy the requirements by name.
extension ProfileViewController: ProfileRelationshipControllerDelegate {}


// MARK: - ProfileDataLoaderDelegate

extension ProfileViewController: ProfileDataLoaderDelegate {
    func loaderDidLoadPlaces(_ places: [Place]) {
        allPlaces.append(contentsOf: places)
        filterPlaces()
    }

    func loaderDidLoadOwnCircles(_ circles: [Circle]) {
        // Calculate total places from the same fetch
        var totalPlaces = 0
        for circle in self.circles {
            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
            totalPlaces += placeCount
            Logger.debug("   Circle '\(circle.name)': placesCount=\(circle.placesCount ?? -1), places array=\(circle.places?.count ?? 0)")
        }

        // Update both stats
        circlesStatView.configure(number: "\(self.circles.count)", title: "Circles")
        placesStatView.configure(number: "\(totalPlaces)", title: "Places")
        updateMilestoneBadge(placeCount: totalPlaces)
        Logger.debug("   Total places calculated: \(totalPlaces)")

        circlesCollectionView.reloadData()
        updateCollectionViewHeight()

        // Also fetch videos
        fetchUserVideos()

        // Load all places for search functionality
        loadAllPlacesFromCircles(circles)
    }

    func loaderDidFailOwnCircles(_ error: Error) {
        circlesStatView.configure(number: "0", title: "Circles")
        placesStatView.configure(number: "0", title: "Places")
        updateMilestoneBadge(placeCount: 0)
        circlesCollectionView.reloadData()
        updateCollectionViewHeight()

        // Also fetch videos
        fetchUserVideos()
        showErrorWithRetry(error) {
            self.loadUserProfile(completion: nil)
        }
    }

    func presentLocalOwnProfileCounts() {
        // Fetch connections count
        let connectionsCount = NetworkManager.shared.connections.count
        Logger.debug("🔍 ProfileViewController - Connections count: \(connectionsCount)")
        connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")

        // Add followers/following stats from user data
        if let user = self.user {
            let followersCount = user.followersCount ?? 0
            let followingCount = user.followingCount ?? 0
            followersStatView.configure(number: "\(followersCount)", title: "Followers")
            followingStatView.configure(number: "\(followingCount)", title: "Following")
            Logger.debug("🔍 ProfileViewController - Followers: \(followersCount), Following: \(followingCount)")
        } else {
            followersStatView.configure(number: "0", title: "Followers")
            followingStatView.configure(number: "0", title: "Following")
        }
    }

    func loaderDidLoadOtherUserCircles(_ data: UserCirclesData) {
        // Calculate total places
        var totalPlaces = 0
        for circle in data.circles {
            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
            totalPlaces += placeCount
        }

        // Update stats
        circlesStatView.configure(number: "\(data.circles.count)", title: "Circles")
        placesStatView.configure(number: "\(totalPlaces)", title: "Places")
        updateMilestoneBadge(placeCount: totalPlaces)

        // Use user data for followers/following/connections
        let user = data.user
        let connectionsCount = user.connectionsCount ?? 0
        let followersCount = user.followersCount ?? 0
        let followingCount = user.followingCount ?? 0

        connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
        followersStatView.configure(number: "\(followersCount)", title: "Followers")
        followingStatView.configure(number: "\(followingCount)", title: "Following")

        // Update user data to get latest info
        self.user = user

        // Re-check connection and follow status with fresh data
        checkConnectionAndFollowStatus()

        circlesCollectionView.reloadData()
        updateCollectionViewHeight()

        // Load all places for search functionality
        loadAllPlacesFromCircles(data.circles)
    }
}
