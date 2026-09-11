import UIKit
import MapKit
import CoreLocation

protocol FullScreenMapViewControllerDelegate: AnyObject {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place)
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion)
    /// Fired when the connection filter changes inside the full-screen map, so
    /// the presenter can keep its own selection in sync across dismissal.
    func mapViewController(_ controller: FullScreenMapViewController, didChangeConnectionFilter connectionId: String?)
    /// Fired when the category/region chip filters change, so an embedding
    /// parent (the home page) can re-filter its own list to match the pins.
    func mapViewControllerDidChangeChipFilters(_ controller: FullScreenMapViewController)
    /// Fired whenever a search-text filter is actually APPLIED to the pins
    /// (debounce landed, or the query cleared). The home page uses it to keep
    /// its distance list live and — from the modal — to mirror the query back
    /// so the search survives dismissal until the user clears it.
    func mapViewController(_ controller: FullScreenMapViewController, didApplySearchQuery query: String?)
}

// Default no-ops so existing conformers don't need to handle every event
extension FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion) {}
    func mapViewController(_ controller: FullScreenMapViewController, didChangeConnectionFilter connectionId: String?) {}
    func mapViewControllerDidChangeChipFilters(_ controller: FullScreenMapViewController) {}
    func mapViewController(_ controller: FullScreenMapViewController, didApplySearchQuery query: String?) {}
}

enum MapViewMode {
    case circle
    case allPlaces
}


class FullScreenMapViewController: UIViewController, MKMapViewDelegate, UITableViewDelegate {
    
    // MARK: - Properties
    private var places: [Place]
    private var initialRegion: MKCoordinateRegion
    private var selectedCategory: UnifiedCategory?
    private var filteredPlaces: [Place] = []
    private var availableCategories: [UnifiedCategory] = []
    private var selectedConnectionId: String?
    /// Force a fit-to-all-places zoom on load even for the My Places scope
    /// (which normally centers on the user's location). Set by the "see all your
    /// places" engagement-tip entry point so the whole collection is framed.
    var fitAllPlacesOnLoad = false
    private var connections: [Connection] = []
    private var connectionPlaces: [String: [Place]] = [:] // connectionId -> places
    private let locationManager = CLLocationManager()
    private var pendingAddPlaceAfterCircleCreation = false // "+" chip flow paused on circle creation
    private var awaitingPlaceAddedFromMap = false // An add-place flow launched from this map is in flight
    /// Tap-a-POI → add to circle flow (action sheet, picker, AddPlace hand-off).
    private lazy var poiCoordinator: MapPOIAddCoordinator = {
        let coordinator = MapPOIAddCoordinator(presenter: self, mapView: mapView)
        coordinator.delegate = self
        return coordinator
    }()
    private var isAdjustingRegion = false // Prevent concurrent region adjustments
    private var hasInitiallyZoomed = false // Track if we've done the initial zoom
    private var hasExplicitInitialRegion = false // Caller provided a region to open at
    private var viewportFetchTimer: Timer? // Debounce for viewport (region-change) notifications

    // MARK: - Google-style pin decluttering (full pins vs. dots)
    // Every place renders at its true location; the places nearest the user
    // (or map center) hold full category pins until pins would overlap, and
    // the rest render as small category-colored dots that promote to full
    // pins on zoom-in. No numbered cluster bubbles, ever. The differential
    // annotation update and the tiering live in MapAnnotationManager.
    private lazy var annotationManager: MapAnnotationManager = {
        let manager = MapAnnotationManager(mapView: mapView)
        manager.adjustRegion = { [weak self] in self?.adjustMapRegion() }
        return manager
    }()
    
    weak var delegate: FullScreenMapViewControllerDelegate?
    var viewMode: MapViewMode = .circle
    var isPresentedModally: Bool = false
    /// A profile map shows ONE person's places, so the network-connection
    /// filter (avatar strip, Connections menu, "My Places") is meaningless
    /// there. Set false to show only the content filter (Category) + list
    /// toggle. Default true keeps the home map's behavior unchanged.
    var showsConnectionFilter: Bool = true
    var showFilters: Bool = true // Control whether to show category/connection filters
    /// Profile-style filtering: replaces the hamburger's Category menu with the
    /// same category + state chip bars the profile map uses, overlaid on the
    /// map. Seed the initial selections so expanding carries the small view's
    /// filters over (while still letting the user broaden them here).
    var showsFilterChips: Bool = false
    var initialChipGroup: PlaceCategoryGroup = .all
    var initialChipRegionId: String?
    /// Seed for the search-text pin filter, like initialChipGroup — set by the
    /// presenter so expanding the map carries the home search query over.
    var initialSearchQuery: String?

    /// Read access for the presenter, so expansion can copy the live state.
    var currentChipGroup: PlaceCategoryGroup { selectedChipGroup }
    var currentChipRegionId: String? { selectedChipRegionId }

    // MARK: - Search-text pin filter (shared by the embedded child and the modal)
    /// Normalized (trimmed, never "") — nil means no text filter.
    private var searchQuery: String?
    private var searchDebounceTimer: Timer?

    /// Applies (debounced) a search-text filter to the pins. Single debounce
    /// owner: the home page's persistent bar and the modal's own bar both land
    /// here. nil/empty clears IMMEDIATELY (cancelling any pending apply).
    /// Search NEVER moves the camera — the zoom the user set is theirs (Wes:
    /// the expanded map "wasn't retaining the zoom level when using search");
    /// matches outside the view are offered through the tappable
    /// searchEmptyLabel instead.
    func setSearchFilter(_ query: String?) {
        let newValue = MapChipFilter.normalizedQuery(query)
        // Invalidate BEFORE the equality check: typing "p" then deleting it
        // makes the second call a no-op by value, but the "p" timer must die
        // with it or stale text filters an empty bar.
        searchDebounceTimer?.invalidate()
        guard newValue != searchQuery else { return }
        if newValue == nil {
            searchQuery = nil
            applyFilter(adjustRegion: false)
            delegate?.mapViewController(self, didApplySearchQuery: nil)
            return
        }
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.searchQuery = newValue
            self.applyFilter(adjustRegion: false)
            self.delegate?.mapViewController(self, didApplySearchQuery: newValue)
        }
    }

    /// Runs any place list through the current search filter — public for the
    /// same reason as applyChipFilters: the home page's list sits beside the
    /// pins and must show the same set.
    func applySearchFilter(_ list: [Place]) -> [Place] {
        MapChipFilter.applySearch(list, query: searchQuery)
    }

    /// Returns the chip filters to their load state (All Categories · All
    /// Places) — the Home tab's reset uses this so a re-tap really does put
    /// the whole map header back to "Me · All Categories · All Places".
    func resetChipFilters() {
        guard showsFilterChips else { return }
        guard selectedChipGroup != .all || selectedChipRegionId != nil || searchQuery != nil else { return }
        selectedChipGroup = .all
        selectedChipRegionId = nil
        searchDebounceTimer?.invalidate()
        let hadSearchQuery = searchQuery != nil
        searchQuery = nil
        // Only the modal mounts a bar of its own; don't instantiate the lazy
        // view on the embedded child just to blank it.
        if isPresentedModally && isViewLoaded {
            mapSearchBar.text = ""
        }
        refreshFilterChips()
        applyFilter(adjustRegion: false)
        if hadSearchQuery {
            delegate?.mapViewController(self, didApplySearchQuery: nil)
        }
    }

    /// The place set scoped to the current connection filter — the shared base
    /// for applyFilter AND the facet counts in the dropdown menus. Only the
    /// MODAL scopes for itself; the embedded child receives places already
    /// filtered by the home controller, and re-filtering them by addedBy drops
    /// places saved under a connection's legacy account id (circle owner and
    /// place adder can be different ids for the same person).
    private func connectionScopedPlaces() -> [Place] {
        guard viewMode == .allPlaces, isPresentedModally else { return places }

        let currentUserId = AuthService.shared.getUserId() ?? ""
        var context = MapPlaceScope.Context()
        context.currentUserId = currentUserId
        context.selectedConnectionId = selectedConnectionId
        context.acceptedConnectionUserIds = connections.map { $0.otherUserId(currentUserId: currentUserId) }
        context.followingUserIds = NetworkManager.shared.followingUsers.map { $0.id }
        context.bucketedPlaces = connectionPlaces
        return MapPlaceScope.apply(places, context: context)
    }

    /// Applies the current chip selections (category group + region) to any
    /// place list. Public so the embedding home page can run its OWN list
    /// through the exact same filter the pins use — the chips live in this
    /// controller, and a list that ignores them contradicts the map beside it.
    func applyChipFilters(_ list: [Place]) -> [Place] {
        var context = MapChipFilter.Context()
        context.group = selectedChipGroup
        context.regionId = selectedChipRegionId
        context.regionGroups = chipRegionGroups
        context.importOrigin = selectedImportOrigin
        return MapChipFilter.apply(list, context: context)
    }

    /// Anchor for the "Near me" chip. Resolved once, quietly; nil (no
    /// permission, no fix yet) just means the chip doesn't appear.
    private let chipLocationProvider = OneShotLocationProvider()
    private var chipOrigin: CLLocation?

    /// When embedded (home page map), the chip bars pin this far below the
    /// map's top so the parent's own overlay row (avatar / ☰ / Me / list)
    /// keeps its space. Parents with taller overlays raise it.
    var embeddedChipsTopInset: CGFloat = 8

    private var selectedChipGroup: PlaceCategoryGroup = .all
    private var chipRegionGroups: [RegionGroup] = []
    private var selectedChipRegionId: String?

    /// Origin sub-filter under My Places: nil = all my places, "in_app" =
    /// added in the app, otherwise an importSource value ("google_maps").
    /// Only meaningful while the connection scope is My Places — any other
    /// scope clears it. Users who never imported never see the option.
    private var selectedImportOrigin: String?

    /// Applies the My Places origin sub-filter (no-op when none selected).
    private func applyOriginFilter(_ list: [Place]) -> [Place] {
        MapChipFilter.applyOrigin(list, origin: selectedImportOrigin)
    }

    /// Zooms to enclose exactly the filtered places (tap NJ → the camera frames
    /// New Jersey). Computed from the places themselves rather than the
    /// annotations, so it doesn't race the batched pin updates. Extra top
    /// padding keeps pins clear of the overlaid chip bars.
    private func zoomToFilteredPlaces(animated: Bool = true) {
        let coordinates = filteredPlaces.compactMap { $0.location?.clLocation?.coordinate }
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let only = coordinates.first {
            mapView.setRegion(MapRegionFitter.singleRegion(only), animated: animated)
            return
        }

        guard let union = MapRegionFitter.enclosingRect(coordinates) else { return }
        let padding = UIEdgeInsets(top: 170, left: 44, bottom: 70, right: 44)
        mapView.setVisibleMapRect(union, edgePadding: padding, animated: animated)
    }

    /// Translucent backing so the chips read over any map content.
    // One row, three dropdowns: Connection | Category | Place. Each always
    // shows its active selection ("Me", "All Categories", "Arizona"), so the
    // header doubles as a sentence describing exactly what the map is showing.
    // Replaced two rows of scrolling chips — same power, half the chrome.
    private lazy var connectionFilterButton = makeFilterDropdown()
    private lazy var categoryFilterButton = makeFilterDropdown()
    private lazy var placeFilterButton = makeFilterDropdown()

    private lazy var filterChipsContainer: UIView = {
        // Transparent container; each dropdown is its own frosted pill so the
        // map shows through between them — a solid full-width bar read as a
        // black slab over the map.
        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [connectionFilterButton, categoryFilterButton, placeFilterButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        // Profile-originated maps have one person by definition.
        connectionFilterButton.isHidden = !(viewMode == .allPlaces && showsConnectionFilter)

        connectionFilterButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            guard let self = self else { done([]); return }
            // Menus can't be mutated once shown, so fetch any uncached avatars
            // BEFORE building — the deferred element's own loading state covers
            // the (capped) wait, and the first open gets faces, not placeholders.
            self.menuBuilder.withConnectionAvatarsWarmed {
                done(self.menuBuilder.connectionMenuElements())
            }
        }])
        categoryFilterButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.menuBuilder.categoryMenuElements() ?? [])
        }])
        placeFilterButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.menuBuilder.placeMenuElements() ?? [])
        }])

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 32)
        ])
        return container
    }()

    /// Modal-only pin search: filters the annotations by name/address/notes.
    /// The embedded child has no bar of its own — the home page's persistent
    /// search bar drives it through setSearchFilter.
    private lazy var mapSearchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search places"
        bar.searchBarStyle = .minimal
        bar.returnKeyType = .search
        bar.delegate = self
        // Frosted dark backing so the field reads over any map content
        bar.searchTextField.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        bar.searchTextField.textColor = .white
        bar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search places",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.7)]
        )
        bar.searchTextField.leftView?.tintColor = UIColor.white.withAlphaComponent(0.7)
        bar.tintColor = .white
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var searchEmptyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        // "N matches outside this view" mode is the one sanctioned way search
        // moves the camera: an explicit tap.
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(searchEmptyLabelTapped)))
        return label
    }()

    @objc private func searchEmptyLabelTapped() {
        guard searchQuery != nil, !filteredPlaces.isEmpty else { return }
        zoomToFilteredPlaces()
    }

    private func makeFilterDropdown() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7

        // Brand-blue capsule, white text — matches the app's primary buttons
        // and reads as a control, not a bar. Soft shadow lifts it off the map.
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 16
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        return button
    }

    private func setDropdownTitle(_ button: UIButton, _ title: String) {
        var attributed = AttributedString(title)
        attributed.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.configuration?.attributedTitle = attributed
    }

    /// The three labels always narrate the current view: "Me · Coffee · Arizona".
    private func updateFilterHeaderTitles() {
        let connectionTitle: String
        switch selectedConnectionId {
        case nil: connectionTitle = "Everyone"
        case HomePlaceFilter.myConnectionsOnlyId: connectionTitle = "My Connections"
        case HomePlaceFilter.myPlacesOnlyId:
            if let origin = selectedImportOrigin {
                connectionTitle = "My Places › \(MapChipFilter.originTitle(origin))"
            } else {
                connectionTitle = "My Places"
            }
        default: connectionTitle = selectedConnectionUser?.displayName ?? "Connection"
        }
        setDropdownTitle(connectionFilterButton, connectionTitle)
        setDropdownTitle(categoryFilterButton, selectedChipGroup == .all ? "All Categories" : selectedChipGroup.title)
        let regionTitle = selectedChipRegionId
            .flatMap { id in chipRegionGroups.first { $0.id == id }?.title } ?? "All Places"
        setDropdownTitle(placeFilterButton, regionTitle)
    }

    // MARK: Dropdown menus

    /// Builds the three header dropdowns; row taps come back through
    /// `menuBuilder(_:perform:)` so the selection logic stays here.
    private lazy var menuBuilder: MapFilterMenuBuilder = {
        let builder = MapFilterMenuBuilder()
        builder.delegate = self
        return builder
    }()

    /// One path for every chip change: refresh the header, re-filter, re-zoom,
    /// and tell the delegate — the home page keeps its own list in lockstep.
    private func chipFiltersChanged(zoomToRegion: Bool = false) {
        updateFilterHeaderTitles()
        applyFilter(adjustRegion: false)
        // Category changes (coffee / drinks / restaurants) keep the user's
        // current view — they just want to see the pins change where they're
        // already looking, not fly the camera out to fit every match. Only
        // picking a specific region deliberately moves the camera to it.
        if zoomToRegion { zoomToFilteredPlaces() }
        delegate?.mapViewControllerDidChangeChipFilters(self)
    }

    private func selectConnectionFromHeader(id: String?, user: User?) {
        selectedConnectionUser = user
        if isPresentedModally {
            // The modal filters for itself — through the one path every other
            // connection control (Me chip, hamburger) already uses, so chip
            // appearance, header label, zoom and delegate mirroring all happen
            // identically no matter which control made the change.
            selectConnection(id)
        } else {
            // Embedded: the home controller owns connection scope (it feeds
            // this map AND the rest of the page). Round-trips back through
            // setConnectionSelection, which keeps the two in lockstep.
            delegate?.mapViewController(self, didChangeConnectionFilter: id)
        }
    }

    /// Parent-driven label sync — no delegate fire, so no loops.
    func setConnectionSelection(id: String?, user: User?) {
        selectedConnectionId = id
        selectedConnectionUser = user
        // The origin sub-filter only makes sense under My Places
        if id != HomePlaceFilter.myPlacesOnlyId { selectedImportOrigin = nil }
        updateFilterHeaderTitles()
    }

    /// Supplies the Connection dropdown's roster when embedded (the modal path
    /// already receives connections with its places).
    func setAvailableConnections(_ list: [Connection]) {
        connections = list
        updateFilterHeaderTitles()
        // Start avatar downloads now, long before the dropdown can be opened —
        // by first tap the cache is warm and the menu shows faces immediately.
        menuBuilder.withConnectionAvatarsWarmed {}
    }
    // IDs of the current user's own places. When set, the default map region
    // centers on the user's favorites instead of just their raw location.
    var ownPlaceIds: Set<String> = []
    
    // MARK: - UI Elements
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        
        // Enable map controls
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        
        return mapView
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 22
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let placesCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = Constants.Colors.primary
        label.layer.cornerRadius = 20
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Overlay control chips (hamburger menu, Me toggle, list toggle) — dark
    // style to sit on the full-bleed map, mirroring the home map's controls
    private lazy var menuChipButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.buildOverlayMenuElements() ?? [])
            }
        ])
        return button
    }()

    private lazy var myPlacesChipButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.imagePlacement = .top
        config.imagePadding = 0
        config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
        config.image = UIImage(systemName: "person", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        var title = AttributedString("Me")
        title.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        config.attributedTitle = title
        config.baseForegroundColor = .white

        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(myPlacesChipTapped), for: .touchUpInside)
        return button
    }()

    private lazy var listChipButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: "list.bullet", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(listChipTapped), for: .touchUpInside)
        return button
    }()

    /// Blue "+" chip under the list/map toggle — launches the standard
    /// add-place flow so a place can be added without leaving the map
    private lazy var addPlaceChipButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        button.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Add a place"
        button.addTarget(self, action: #selector(addPlaceChipTapped), for: .touchUpInside)
        return button
    }()

    private let overlayChipStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Whose places are on the map: the selected connection's avatar shown
    /// beside the control chips (hidden when no connection filter is active).
    /// Tapping opens their profile.
    private lazy var connectionAvatarChip: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.imageView?.contentMode = .scaleAspectFill
        button.tintColor = .white
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Selected connection"
        button.addTarget(self, action: #selector(connectionAvatarChipTapped), for: .touchUpInside)
        return button
    }()

    /// The user whose places the map is filtered to; drives the avatar chip
    var selectedConnectionUser: User? {
        didSet { updateConnectionAvatarChip() }
    }

    private func updateConnectionAvatarChip() {
        guard isViewLoaded else { return }
        guard let user = selectedConnectionUser,
              selectedConnectionId != nil, selectedConnectionId != HomePlaceFilter.myPlacesOnlyId else {
            connectionAvatarChip.isHidden = true
            return
        }
        connectionAvatarChip.isHidden = false
        connectionAvatarChip.setImage(UIImage(systemName: "person.crop.circle.fill"), for: .normal)
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            let expectedUserId = user.id
            ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: "profile_\(user.id)_\(profilePicture)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, let image = image,
                          self.selectedConnectionUser?.id == expectedUserId else { return }
                    self.connectionAvatarChip.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                }
            }
        }
    }

    @objc private func connectionAvatarChipTapped() {
        guard let user = selectedConnectionUser else { return }
        presentProfile(for: user)
    }

    // Distance-sorted list shown by the list/map toggle
    private lazy var placesListTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.rowHeight = 72
        tableView.isHidden = true
        // Half-sheet look: rounded top corners where it meets the map above it
        tableView.layer.cornerRadius = 16
        tableView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tableView.clipsToBounds = true
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        tableView.register(QuickAccessPlaceCell.self, forCellReuseIdentifier: "FullScreenPlaceListCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private var isShowingPlacesList = false
    private var distanceSortedPlaces: [(place: Place, distance: CLLocationDistance?)] = []
    private let listDistanceFormatter = MKDistanceFormatter()
    
    // MARK: - Init
    init(places: [Place] = [], initialRegion: MKCoordinateRegion? = nil, selectedCategory: UnifiedCategory? = nil, selectedConnectionId: String? = nil) {
        self.places = places
        self.selectedCategory = selectedCategory
        self.selectedConnectionId = selectedConnectionId
        self.filteredPlaces = places

        // Calculate initial region
        if let region = initialRegion {
            self.initialRegion = region
            // An explicitly provided region (e.g. expanding the embedded map)
            // should be honored — don't recenter on the user or re-zoom
            self.hasExplicitInitialRegion = true
        } else if let firstPlace = places.first(where: { $0.location != nil }),
                  let location = firstPlace.location?.clLocation {
            self.initialRegion = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
        } else {
            // Default to San Francisco if no location available
            self.initialRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                latitudinalMeters: 20000,
                longitudinalMeters: 20000
            )
        }
        
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    // MARK: - Public Methods

    /// The map's currently visible region (for viewport-based place loading)
    var currentRegion: MKCoordinateRegion {
        return mapView.region
    }

    /// The user's current location, if known (for distance sorting)
    var currentUserLocation: CLLocation? {
        return locationManager.location ?? mapView.userLocation.location
    }

    /// Syncs the connection filter selected in a parent controller (embedded mode).
    /// The parent passes already-filtered places via updatePlaces; this only tells
    /// adjustMapRegion to zoom to the filtered places instead of the user's location.
    /// Connection avatar row overlaid on the modal map (allPlaces mode only)
    private var userListView: HorizontalUserListView?

    /// Replaces the per-connection place buckets (owner-mapped by the
    /// presenter) without touching the place list. Callers follow up with
    /// updatePlaces, which re-applies the filter.
    func updateConnectionBuckets(_ buckets: [String: [Place]]) {
        connectionPlaces = buckets
    }

    func setConnectionFilterContext(_ connectionId: String?) {
        let changed = selectedConnectionId != connectionId
        selectedConnectionId = connectionId
        if changed { resetCoverageBannerDismissal() }
        if connectionId == nil || connectionId == HomePlaceFilter.myPlacesOnlyId || connectionId == HomePlaceFilter.myConnectionsOnlyId {
            selectedConnectionUser = nil
        }
        updateConnectionAvatarChip()
        // Re-scope the pins when the presenter resolves a canonical id for the
        // current selection. No delegate echo — this call came FROM the
        // presenter, so notifying it back would loop. Modal only: it filters
        // its own place set. The embedded child gets already-filtered places
        // via updatePlaces right after this call — re-filtering here would
        // zoom to fit the STALE unfiltered set (framing the whole country
        // instead of the selected connection's city)
        if changed && isViewLoaded && isPresentedModally {
            // Keep the camera put on connection change (no re-frame).
            applyFilter(adjustRegion: false)
        }
    }

    func updatePlaces(_ newPlaces: [Place], adjustRegion: Bool = true) {
        // Don't update if we're going from empty to empty (still loading)
        if self.places.isEmpty && newPlaces.isEmpty {
            // Keep showing "Loading..." - don't update
            return
        }

        self.places = newPlaces
        updateAvailableCategories()
        refreshFilterChips()
        // Apply existing filters to the new places
        applyFilter(adjustRegion: adjustRegion)
        // adjustMapRegion is already called in addAnnotationsToMap, no need to call it again

        // Show place count when places are loaded
        showPlaceCount()
    }
    
    /// The embedded map's frame settles AFTER the first data pass — a count
    /// computed against the pre-layout visibleMapRect can be wrong in either
    /// direction (empty rect → hidden pill, or world-rect → inflated count).
    /// Recount whenever geometry settles; it's one cheap pass over
    /// filteredPlaces and idempotent.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePlacesCount()
    }

    func hidePlaceCount() {
        placesCountLabel.isHidden = true
    }

    /// Route through the counter rather than blindly unhiding: revealing the
    /// pill without setting its text is how the empty blue circle happened —
    /// visible from load until the first filter change or pan finally wrote a
    /// number into it. updatePlacesCount owns both the text and visibility.
    func showPlaceCount() {
        updatePlacesCount()
    }
    
    func updatePlacesWithConnections(_ userPlaces: [Place], connections: [Connection], connectionPlaces: [String: [Place]]) {
        // Debug logging
        Logger.debug("🔍 FullScreenMap: updatePlacesWithConnections called")
        Logger.debug("🔍 Connections count: \(connections.count)")
        for (index, connection) in connections.enumerated() {
            Logger.debug("  \(index): \(connection.connectedUser?.displayName ?? "Unknown") - ID: \(connection.connectedUserId)")
        }
        Logger.debug("🔍 Connection places map keys: \(connectionPlaces.keys.sorted())")
        
        // Combine all places
        var allPlaces = userPlaces
        for (userId, places) in connectionPlaces {
            Logger.debug("  User \(userId) has \(places.count) places")
            allPlaces.append(contentsOf: places)
        }
        
        self.places = allPlaces
        // Same ranking as the home connections row, so the dropdown lists
        // people in the order muscle memory expects.
        self.connections = HorizontalUserListView.rankedConnections(connections)
        self.connectionPlaces = connectionPlaces
        menuBuilder.withConnectionAvatarsWarmed {}
        
        // Note: we intentionally do NOT reset hasInitiallyZoomed here anymore.
        // adjustMapRegion() keeps the current camera when the selected
        // connection has places in view, and only re-frames when it doesn't.

        // Reflect the connection filter in the overlay controls
        if viewMode == .allPlaces {
            updateMyPlacesChipAppearance()
        }

        applyFilter()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Carry the small view's chip selections into the expanded view
        selectedChipGroup = initialChipGroup
        selectedChipRegionId = initialChipRegionId
        // Same for the search query — set the ivar directly (no debounce/zoom
        // on load); the applyFilter() below picks it up, and setupUI seeds the
        // bar text.
        let seededQuery = initialSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = (seededQuery?.isEmpty ?? true) ? nil : seededQuery
        setupUI()
        setupMap()
        setupTableView()
        updateAvailableCategories()
        refreshFilterChips()
        applyFilter()

        // Drop the new pin as soon as an add launched from the "+" chip saves
        // (the presenter's own refresh reconciles later)
        if isPresentedModally && showFilters {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePlaceAddedFromMap(_:)),
                name: Notification.Name("PlaceAddedToCircle"),
                object: nil
            )
        }

        // Kick off the Near me anchor. When the fix lands the chip row gains
        // its leading chip; selection and state order are untouched, so the
        // rebuild is invisible unless the new chip is the thing you wanted.
        if showsFilterChips && chipOrigin == nil {
            chipLocationProvider.requestLocation { [weak self] location in
                DispatchQueue.main.async {
                    guard let self = self, let location = location else { return }
                    self.chipOrigin = location
                    self.refreshFilterChips()
                    // A region selection may have been waiting on this fix
                    // (seeded "Near me" from the small map) — apply it now that
                    // the group finally exists, and frame the result.
                    if self.selectedChipRegionId != nil {
                        self.applyFilter(adjustRegion: false)
                        self.zoomToFilteredPlaces()
                    }
                }
            }
        }
    }

    /// Rebuilds both chip bars from the full place set (chip-bar mode only), so
    /// the expanded view can broaden a filter as well as narrow it.
    private func refreshFilterChips() {
        guard showsFilterChips else { return }
        chipRegionGroups = RegionGrouper.groups(for: places, origin: chipOrigin)
        if selectedChipRegionId != nil && !chipRegionGroups.contains(where: { $0.id == selectedChipRegionId }) {
            // "Near me" only exists once a location fix lands. A seeded Near me
            // (expanding from the small map) must SURVIVE the fix-less opening
            // moments — resetting it here silently unfiltered the modal: pins
            // showed everything while the carried-over camera made the map
            // LOOK filtered, and the list exposed the mismatch. Keep the
            // selection; the fix below re-validates once the origin arrives.
            if selectedChipRegionId != "near-me" || chipOrigin != nil {
                selectedChipRegionId = nil
            }
        }
        // Menus are deferred and rebuilt on every open — only the visible
        // titles need refreshing here.
        updateFilterHeaderTitles()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add map view
        view.addSubview(mapView)
        
        // Add close button only if presented modally
        if isPresentedModally {
            view.addSubview(closeButton)
            closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        }
        
        // Add places count label
        view.addSubview(placesCountLabel)
        // Hide place count initially until places are loaded
        placesCountLabel.isHidden = true

        // Coverage banner (shown when a selected connection has nothing in view)
        view.addSubview(coverageBanner)
        
        // Add overlay control chips only if presented modally and filters are enabled
        if isPresentedModally && showFilters {
            // Dropdown-header mode: the three filter dropdowns replace the
            // avatar chip, the hamburger, the Me chip AND the avatar row — one
            // header instead of four controls. The list toggle survives, moved
            // to the right edge under the close button.
            if !showsFilterChips {
                if showsConnectionFilter {
                    overlayChipStack.addArrangedSubview(connectionAvatarChip)
                }
                overlayChipStack.addArrangedSubview(menuChipButton)
                if viewMode == .allPlaces && showsConnectionFilter {
                    overlayChipStack.addArrangedSubview(myPlacesChipButton)
                }
                overlayChipStack.addArrangedSubview(listChipButton)
                overlayChipStack.addArrangedSubview(addPlaceChipButton)
                updateConnectionAvatarChip()
            }
            // Header mode adds no ☰/Me row — the dropdowns cover both, so the
            // second row holds only close and the list toggle on the right.

            // List added before the chips so the chips stay tappable above it
            view.addSubview(placesListTableView)
            if !showsFilterChips {
                view.addSubview(overlayChipStack)
            }
            if showsFilterChips {
                view.addSubview(filterChipsContainer)
                view.addSubview(listChipButton)
                listChipButton.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(addPlaceChipButton)
                view.addSubview(mapSearchBar)
                view.addSubview(searchEmptyLabel)
                mapSearchBar.text = searchQuery
            }

            // Legacy avatar row only in hamburger mode — the Connection
            // dropdown covers switching in header mode.
            if !showsFilterChips && viewMode == .allPlaces && showsConnectionFilter {
                let row = HorizontalUserListView(frame: .zero, initialConnections: connections)
                row.translatesAutoresizingMaskIntoConstraints = false
                row.backgroundColor = .clear
                row.delegate = self
                if let selected = selectedConnectionId, selected != HomePlaceFilter.myPlacesOnlyId {
                    row.selectedUserId = selected
                }
                view.addSubview(row)
                userListView = row
            }
        }
        
        // Embedded chip bars (home page map): the modal overlay block above is
        // skipped for child-VC embeds, but the filter rows are exactly why the
        // embed exists — so they get their own mount, pinned below whatever
        // overlay row the parent draws over the map.
        if !isPresentedModally && showsFilterChips {
            view.addSubview(filterChipsContainer)
            NSLayoutConstraint.activate([
                filterChipsContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: embeddedChipsTopInset),
                filterChipsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                filterChipsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
            ])
        }

        // Setup base constraints
        var constraints: [NSLayoutConstraint] = [
            // Map view - full screen
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Places count label - above zoom buttons on right side
            placesCountLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -70),
            placesCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            placesCountLabel.heightAnchor.constraint(equalToConstant: 40),
            placesCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            // Coverage banner: top-center, below the filter chips, over the map
            // (top anchor added per-mode below — the modal header mode has a
            // search-bar row the banner must clear)
            coverageBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coverageBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            coverageBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12)
        ]

        if isPresentedModally && showFilters && showsFilterChips {
            constraints.append(coverageBanner.topAnchor.constraint(equalTo: mapSearchBar.bottomAnchor, constant: 8))
        } else {
            constraints.append(coverageBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56))
        }
        
        // Add close button constraints only if presented modally. In header
        // mode the dropdown row owns the top edge, so close moves to the
        // second row (mirroring the embedded map's expand button).
        if isPresentedModally {
            if showsFilterChips && showFilters {
                constraints.append(closeButton.topAnchor.constraint(equalTo: filterChipsContainer.bottomAnchor, constant: 8))
            } else {
                constraints.append(closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16))
            }
            constraints.append(contentsOf: [
                closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 44),
                closeButton.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        // Overlay chip + list constraints, only if presented modally with filters
        if isPresentedModally && showFilters {
            NSLayoutConstraint.activate([
                // Half-sheet: the list covers the bottom ~55% of the screen so the
                // map stays visible and pannable above it (the filter chips stay
                // over the map's top half).
                placesListTableView.heightAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.55),
                placesListTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                placesListTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                placesListTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            if showsFilterChips {
                // Header mode: the dropdown row owns the full top edge.
                // Second row below it — ☰/Me left, close then list stacked on
                // the right. Same shape as the embedded home map.
                NSLayoutConstraint.activate([
                    filterChipsContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                    filterChipsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                    filterChipsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

                    // Search shares the second row with the close button
                    mapSearchBar.topAnchor.constraint(equalTo: filterChipsContainer.bottomAnchor, constant: 8),
                    mapSearchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                    mapSearchBar.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
                    mapSearchBar.heightAnchor.constraint(equalToConstant: 44),

                    searchEmptyLabel.topAnchor.constraint(equalTo: mapSearchBar.bottomAnchor, constant: 8),
                    searchEmptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    searchEmptyLabel.heightAnchor.constraint(equalToConstant: 30),
                    searchEmptyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

                    listChipButton.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
                    listChipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                    listChipButton.widthAnchor.constraint(equalToConstant: 36),
                    listChipButton.heightAnchor.constraint(equalToConstant: 36),

                    addPlaceChipButton.topAnchor.constraint(equalTo: listChipButton.bottomAnchor, constant: 8),
                    addPlaceChipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                    addPlaceChipButton.widthAnchor.constraint(equalToConstant: 36),
                    addPlaceChipButton.heightAnchor.constraint(equalToConstant: 36)
                ])
            } else {
                NSLayoutConstraint.activate([
                    overlayChipStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                    overlayChipStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                    overlayChipStack.heightAnchor.constraint(equalToConstant: 36),
                    menuChipButton.widthAnchor.constraint(equalToConstant: 36),
                    listChipButton.widthAnchor.constraint(equalToConstant: 36),
                    addPlaceChipButton.widthAnchor.constraint(equalToConstant: 36),
                    connectionAvatarChip.widthAnchor.constraint(equalToConstant: 36),
                    connectionAvatarChip.heightAnchor.constraint(equalToConstant: 36)
                ])
            }

            if viewMode == .allPlaces {
                myPlacesChipButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
            }

            if let row = userListView {
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: overlayChipStack.bottomAnchor, constant: 8),
                    row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                    row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                    row.heightAnchor.constraint(equalToConstant: 118)
                ])
            }
        }
        
        
        // Add padding to label
        placesCountLabel.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        
        // Add user location button
        let userLocationButton = MKUserTrackingButton(mapView: mapView)
        userLocationButton.translatesAutoresizingMaskIntoConstraints = false
        userLocationButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        userLocationButton.layer.cornerRadius = 5
        view.addSubview(userLocationButton)
        
        NSLayoutConstraint.activate([
            userLocationButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            userLocationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
    private func setupMap() {
        mapView.delegate = self
        Logger.debug("🗺️ Map delegate set. View mode: \(viewMode)")
        
        // Enable POI selection for iOS 16+ only in allPlaces mode
        // In circle mode, we don't want POI selection to interfere with place annotations
        if #available(iOS 16.0, *) {
            if viewMode == .allPlaces {
                mapView.selectableMapFeatures = [.pointsOfInterest]
            } else {
                mapView.selectableMapFeatures = []
            }
        }
        
        // Request location permission and zoom to user location if available
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        if hasExplicitInitialRegion {
            // The caller told us exactly where to open (e.g. expanding the
            // embedded map) — keep that view instead of recentering on the user
            mapView.setRegion(initialRegion, animated: false)
            hasInitiallyZoomed = true
        } else if let location = locationManager.location {
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
            mapView.setRegion(region, animated: false)
            hasInitiallyZoomed = true
        } else {
            mapView.setRegion(initialRegion, animated: false)
            hasInitiallyZoomed = true
        }
    }
    
    private func setupTableView() {
        if isPresentedModally && showFilters {
            placesListTableView.delegate = self
            placesListTableView.dataSource = self
        }
    }
    
    // MARK: - Map Annotations
    private func addAnnotationsToMap(adjustRegion: Bool = true) {
        // Differential update: only what changed is removed or added
        annotationManager.update(with: filteredPlaces, adjustRegion: adjustRegion)
    }

    /// Debounced pin-tier recompute — region changes land here.
    func schedulePinTierRecompute(delay: TimeInterval = 0.25) {
        annotationManager.schedulePinTierRecompute(delay: delay)
    }

    // MARK: - Helper Extensions
    
    func adjustMapRegion() {
        // Honor an explicitly provided opening region (e.g. expanding the
        // embedded map) — cleared when the user changes a filter in here
        guard !hasExplicitInitialRegion else {
            Logger.debug("📍 adjustMapRegion: Skipping - honoring explicit initial region")
            return
        }

        // Prevent concurrent adjustments
        guard !isAdjustingRegion else {
            Logger.debug("📍 adjustMapRegion: Skipping - already adjusting")
            return
        }
        isAdjustingRegion = true
        var issuedRegionChange = false

        Logger.debug("📍 adjustMapRegion called:")
        Logger.debug("  - selectedConnectionId: \(selectedConnectionId ?? "nil")")
        Logger.debug("  - selectedCategory: \(selectedCategory?.displayName ?? "nil")")
        Logger.debug("  - filteredPlaces.count: \(filteredPlaces.count)")
        Logger.debug("  - hasInitiallyZoomed: \(hasInitiallyZoomed)")
        
        // If a specific connection is selected, always zoom to show their places.
        // fitAllPlacesOnLoad forces the same worldwide fit for the My Places
        // scope, which otherwise centers on the user's current location.
        let shouldZoomToFilteredPlaces = fitAllPlacesOnLoad ||
                                        (selectedConnectionId != nil && selectedConnectionId != HomePlaceFilter.myPlacesOnlyId) ||
                                        selectedCategory != nil
        
        Logger.debug("  - shouldZoomToFilteredPlaces: \(shouldZoomToFilteredPlaces)")
        
        if shouldZoomToFilteredPlaces && filteredPlaces.count > 0 {
            // Every filter change re-frames the map to include ALL of the
            // selection's places — even worldwide. The fly-over as you tap
            // through connections is intentional; the my-location button
            // brings the user back to their own area.
            var coordinates: [CLLocationCoordinate2D] = []
            for place in filteredPlaces {
                if let location = place.location?.clLocation {
                    coordinates.append(location.coordinate)
                }
            }

            Logger.debug("  - Coordinates for zoom: \(coordinates.count)")

            // Padded to the span, clamped to MapKit's valid limits so
            // setRegion never silently rejects the region
            if let region = MapRegionFitter.boundingRegion(coordinates, clampSpan: true) {
                Logger.debug("  - Setting region to center: \(region.center), span: \(region.span)")
                mapView.setRegion(region, animated: true)
                issuedRegionChange = true
                hasInitiallyZoomed = true
            }
        } else {
            // Default behavior: center on the user in a usable radius that shows
            // their own favorite places (falling back to all visible places)
            let userLocation = locationManager.location ?? mapView.userLocation.location

            let ownPlaces = filteredPlaces.filter { ownPlaceIds.contains($0.id) }
            let focusPlaces = ownPlaces.isEmpty ? filteredPlaces : ownPlaces

            if let userLocation = userLocation {
                let distances = focusPlaces.compactMap { place -> CLLocationDistance? in
                    guard let placeLocation = place.location?.clLocation else { return nil }
                    return userLocation.distance(from: placeLocation)
                }
                let radius = MapRegionFitter.focusRadius(distances: distances)

                Logger.debug("  - Default region: \(focusPlaces.count) focus places (\(ownPlaces.count) own), radius \(Int(radius))m")

                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: radius * 2,
                    longitudinalMeters: radius * 2
                )
                mapView.setRegion(region, animated: !hasInitiallyZoomed)
                issuedRegionChange = true
                hasInitiallyZoomed = true
            } else if filteredPlaces.count > 0 {
                // No user location - fit the focus places instead
                var coordinates: [CLLocationCoordinate2D] = []
                for place in focusPlaces {
                    if let location = place.location?.clLocation {
                        coordinates.append(location.coordinate)
                    }
                }
                
                if let region = MapRegionFitter.boundingRegion(coordinates, clampSpan: false) {
                    mapView.setRegion(region, animated: !hasInitiallyZoomed)
                    issuedRegionChange = true
                    hasInitiallyZoomed = true
                }
            }
        }

        if issuedRegionChange {
            // Reset the flag after a delay to allow the animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isAdjustingRegion = false
            }
        } else {
            // No zoom was issued - don't hold the guard, or a real zoom that
            // follows moments later (e.g. a connection's places arriving from
            // the network) gets silently skipped
            isAdjustingRegion = false
        }
    }
    
    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // A drag under the search keyboard means "back to the map" — but only
        // a USER gesture: this also fires for programmatic zooms (including
        // the debounced zoom-to-matches while typing), which must not steal
        // the keyboard mid-word.
        guard isPresentedModally, showsFilterChips,
              (mapView.subviews.first?.gestureRecognizers ?? []).contains(where: {
                  $0.state == .began || $0.state == .changed || $0.state == .ended
              })
        else { return }
        mapSearchBar.resignFirstResponder()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Every zoom/pan changes which pins have room to be full-size —
        // re-tier regardless of view mode
        schedulePinTierRecompute()

        // Notify the delegate (debounced) so it can load places for the new viewport.
        // Fires for programmatic zooms too — that's how the initial viewport load happens.
        guard viewMode == .allPlaces else { return }

        viewportFetchTimer?.invalidate()
        viewportFetchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.mapViewController(self, regionDidChangeTo: self.mapView.region)
        }

        // The badge tracks the viewport, so every settle re-counts. Cheap: one
        // pass over the already-filtered array, only at gesture end.
        updatePlacesCount()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }

        guard let placeAnnotation = annotation as? PlaceAnnotation else {
            return nil
        }

        // Demoted tier: small category-colored dot at the true location
        // (promotes to a full pin when decluttering frees up space on zoom)
        if !annotationManager.promotedPlaceIds.contains(placeAnnotation.place.id) {
            let dotView = (mapView.dequeueReusableAnnotationView(withIdentifier: PlaceDotAnnotationView.reuseIdentifier) as? PlaceDotAnnotationView)
                ?? PlaceDotAnnotationView(annotation: annotation, reuseIdentifier: PlaceDotAnnotationView.reuseIdentifier)
            dotView.annotation = annotation
            dotView.setCategoryColor(placeAnnotation.place.category.color)
            return dotView
        }

        let identifier = "PlaceAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true

            // Create detail button with explicit target-action as a workaround
            let detailButton = UIButton(type: .detailDisclosure)
            // Remove custom target-action to prevent double presentation
            // The standard calloutAccessoryControlTapped delegate method will handle this
            annotationView?.rightCalloutAccessoryView = detailButton

            // Ensure the annotation view is interactive
            annotationView?.isEnabled = true
            annotationView?.isUserInteractionEnabled = true
        } else {
            annotationView?.annotation = annotation
            // Ensure button is still there and interactive
            if annotationView?.rightCalloutAccessoryView == nil {
                let detailButton = UIButton(type: .detailDisclosure)
                // Remove custom target-action to prevent double presentation
                // The standard calloutAccessoryControlTapped delegate method will handle this
                annotationView?.rightCalloutAccessoryView = detailButton
            }
        }

        // Customize marker appearance based on category
        if let markerView = annotationView {
            // Left accessory: one-tap check-in with this place pre-filled
            // (calloutAccessoryControlTapped branches on left vs right).
            if markerView.leftCalloutAccessoryView == nil {
                let checkInButton = UIButton(type: .system)
                checkInButton.setImage(.checkInIcon, for: .normal)
                checkInButton.tintColor = Constants.Colors.primary
                checkInButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                markerView.leftCalloutAccessoryView = checkInButton
            }
            markerView.markerTintColor = placeAnnotation.place.category.color
            markerView.glyphImage = UIImage(systemName: placeAnnotation.place.category.systemIconName)
            // NO clusteringIdentifier: numbered cluster bubbles hide the
            // places (rejected 2026-08-20). Density is handled by our own
            // pin/dot tiering instead — see recomputePinTiers().
            markerView.clusteringIdentifier = nil
            // We declutter ourselves; MapKit must not additionally hide pins
            markerView.displayPriority = .required
        }

        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        let timestamp = Date().timeIntervalSince1970
        Logger.debug("🔵 [DEBUG-\(timestamp)] Info button tapped!")
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else {
            Logger.debug("❌ [DEBUG-\(timestamp)] Failed to cast annotation to PlaceAnnotation")
            return
        }

        // Left accessory = check in here; right accessory keeps opening detail
        if control === view.leftCalloutAccessoryView {
            CheckInViewController.present(from: self, prefilledPlace: placeAnnotation.place)
            return
        }

        Logger.debug("✅ [DEBUG-\(timestamp)] Place: \(placeAnnotation.place.name)")
        Logger.debug("📱 [DEBUG-\(timestamp)] Delegate exists: \(delegate != nil)")
        Logger.debug("🗺️ [DEBUG-\(timestamp)] View mode: \(viewMode)")
        Logger.debug("📍 [DEBUG-\(timestamp)] isPresentedModally: \(isPresentedModally)")
        
        // Notify delegate
        if let delegate = delegate {
            Logger.debug("🎯 [DEBUG-\(timestamp)] Calling delegate.mapViewController for place: \(placeAnnotation.place.name)")
            delegate.mapViewController(self, didSelectPlace: placeAnnotation.place)
            Logger.debug("🎯 [DEBUG-\(timestamp)] Delegate call completed")
        } else {
            Logger.debug("⚠️ [DEBUG-\(timestamp)] No delegate set!")
        }
        
        // Dismiss if not in allPlaces mode — but only when the delegate didn't
        // present a detail screen on top of this map. Calling dismiss while we
        // have a presented child closes that child instead (detail opened then
        // immediately closed).
        if viewMode != .allPlaces && presentedViewController == nil {
            dismiss(animated: true)
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        // Handle POI selection for iOS 16+
        if #available(iOS 16.0, *) {
            if let featureAnnotation = annotation as? MKMapFeatureAnnotation {
                poiCoordinator.handlePOISelection(featureAnnotation)
                return
            }
        }

        // For regular place annotations, don't interfere with the default behavior
        // The callout with info button will be shown automatically
        if let placeAnnotation = annotation as? PlaceAnnotation {
            Logger.debug("📍 Selected place annotation: \(placeAnnotation.place.name)")
        }
    }
    
    @available(iOS 16.0, *)
    // MARK: - Helper Methods for POI Duplicate Detection
    
    private func findExistingPlace(name: String, coordinate: CLLocationCoordinate2D) -> Place? {
        // Check all places (including filtered and unfiltered)
        let allPlacesToCheck = viewMode == .allPlaces ? places : filteredPlaces
        return POIDuplicateMatcher.existingPlace(named: name, at: coordinate, in: allPlacesToCheck)
    }
    
    // MARK: - Actions
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    // Removed detailButtonTapped method - using standard calloutAccessoryControlTapped delegate method instead
    // to prevent double presentation of PlaceDetailViewController
    
    // MARK: - Overlay Menu & Chips

    private func buildOverlayMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        let currentUserId = AuthService.shared.getUserId() ?? ""

        // Connection filter submenu (allPlaces mode only; not on profile maps)
        if viewMode == .allPlaces && showsConnectionFilter {
            var connectionActions: [UIAction] = [
                UIAction(title: "Everyone", state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                    self?.selectConnection(nil)
                },
                UIAction(title: "My Connections", state: selectedConnectionId == HomePlaceFilter.myConnectionsOnlyId ? .on : .off) { [weak self] _ in
                    self?.selectConnection(HomePlaceFilter.myConnectionsOnlyId)
                },
                UIAction(title: "My Places Only", state: selectedConnectionId == HomePlaceFilter.myPlacesOnlyId ? .on : .off) { [weak self] _ in
                    self?.selectConnection(HomePlaceFilter.myPlacesOnlyId)
                }
            ]
            var listedIds = Set<String>()
            for connection in connections {
                let otherUserId = connection.otherUserId(currentUserId: currentUserId)
                listedIds.insert(otherUserId)
                connectionActions.append(
                    UIAction(
                        title: connection.connectedUser?.displayName ?? "Unknown",
                        state: selectedConnectionId == otherUserId ? .on : .off
                    ) { [weak self] _ in
                        self?.selectConnection(otherUserId)
                    }
                )
            }
            // Followed non-connections are pickable too (following grants
            // public-tier visibility)
            for user in NetworkManager.shared.followingUsers {
                guard !user.id.isEmpty, !listedIds.contains(user.id),
                      !IDNormalizer.isSameUser(user.id, currentUserId) else { continue }
                listedIds.insert(user.id)
                connectionActions.append(
                    UIAction(title: user.displayName,
                             state: selectedConnectionId == user.id ? .on : .off) { [weak self] _ in
                        self?.selectConnection(user.id)
                    }
                )
            }

            let connectionSubtitle: String
            if let connectionId = selectedConnectionId {
                if connectionId == HomePlaceFilter.myPlacesOnlyId {
                    connectionSubtitle = "My Places Only"
                } else if connectionId == HomePlaceFilter.myConnectionsOnlyId {
                    connectionSubtitle = "My Connections"
                } else {
                    connectionSubtitle = connections
                        .first(where: { $0.otherUserId(currentUserId: currentUserId) == connectionId })?
                        .connectedUser?.displayName
                        ?? NetworkManager.shared.followingUsers.first(where: { $0.id == connectionId })?.displayName
                        ?? "Connection"
                }
            } else {
                connectionSubtitle = "Everyone"
            }
            elements.append(UIMenu(
                title: "Connections",
                subtitle: connectionSubtitle,
                image: UIImage(systemName: "person.2"),
                children: connectionActions
            ))
        }

        // Category submenu
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

        // View Profile: the filtered connection's profile, or the user's own.
        // Omitted on profile maps — you're already looking at the profile.
        if viewMode == .allPlaces && showsConnectionFilter {
            let profileTitle: String
            if let connectionId = selectedConnectionId, connectionId != HomePlaceFilter.myPlacesOnlyId,
               let name = connections.first(where: { $0.otherUserId(currentUserId: AuthService.shared.getUserId() ?? "") == connectionId })?.connectedUser?.displayName,
               !name.isEmpty {
                profileTitle = "View \(name)'s Profile"
            } else {
                profileTitle = "View My Profile"
            }
            elements.append(UIAction(title: profileTitle, image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in
                self?.presentProfileFromMenu()
            })
        }

        return elements
    }

    private func presentProfileFromMenu() {
        // Without a configured user, ProfileViewController shows the current user's own profile
        var user: User?
        if let connectionId = selectedConnectionId, connectionId != HomePlaceFilter.myPlacesOnlyId {
            let currentUserId = AuthService.shared.getUserId() ?? ""
            user = connections.first(where: { $0.otherUserId(currentUserId: currentUserId) == connectionId })?.connectedUser
        }
        presentProfile(for: user)
    }

    private func presentProfile(for user: User?) {
        let profileVC = ProfileViewController()
        if let user = user {
            profileVC.configureWith(user: user)
        }
        let navController = UINavigationController(rootViewController: profileVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }

    @objc private func myPlacesChipTapped() {
        selectConnection(selectedConnectionId == HomePlaceFilter.myPlacesOnlyId ? nil : HomePlaceFilter.myPlacesOnlyId)
    }

    private func updateMyPlacesChipAppearance() {
        guard isPresentedModally && showFilters && viewMode == .allPlaces else { return }
        let isActive = selectedConnectionId == HomePlaceFilter.myPlacesOnlyId
        var config = myPlacesChipButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: isActive ? "person.fill" : "person",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        config.baseForegroundColor = .white
        myPlacesChipButton.configuration = config
        myPlacesChipButton.backgroundColor = isActive ? Constants.Colors.primary : UIColor.black.withAlphaComponent(0.6)
    }

    @objc private func listChipTapped() {
        isShowingPlacesList.toggle()

        // Flip the icon: show what tapping will switch to
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        listChipButton.setImage(
            UIImage(systemName: isShowingPlacesList ? "map" : "list.bullet", withConfiguration: config),
            for: .normal
        )

        if isShowingPlacesList {
            rebuildDistanceSortedPlaces()
            placesListTableView.reloadData()
        }

        // Half-sheet: the list sits over the bottom ~55%, so the map — and its
        // filter chips + people row on top — stay visible and interactive.
        placesListTableView.isHidden = !isShowingPlacesList
        updatePlacesCount()
    }

    // MARK: - Add Place from Map

    /// Same circle-selection rules as the home quick-add button: one circle or
    /// a remembered last-used circle goes straight to the add screen,
    /// otherwise the circle picker.
    @objc private func addPlaceChipTapped() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let circles) where !circles.isEmpty:
                    if circles.count == 1 {
                        self.presentAddPlace(circleId: circles[0].id, circles: circles)
                    } else if let lastUsedId = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey),
                              circles.contains(where: { $0.id == lastUsedId }) {
                        self.presentAddPlace(circleId: lastUsedId, circles: circles)
                    } else {
                        self.presentCirclePickerForAddPlace(circles: circles)
                    }
                case .success:
                    self.presentCreateCircleThenAddPlace()
                case .failure(let error):
                    AlertPresenter.showError(error, from: self)
                }
            }
        }
    }

    /// The map has no navigation stack of its own (home presents it bare), so
    /// the add screen goes up modally in its own nav controller — on save it
    /// dismisses itself and the user lands back on the map.
    private func presentAddPlace(circleId: String, circles: [Circle]? = nil) {
        let addPlaceVC = AddPlaceViewController(circleId: circleId, circles: circles)
        let navController = UINavigationController(rootViewController: addPlaceVC)
        navController.modalPresentationStyle = .fullScreen
        awaitingPlaceAddedFromMap = true
        present(navController, animated: true)
    }

    private func presentCirclePickerForAddPlace(circles: [Circle]) {
        // Circles arrive in the user's own order (same as the profile grid).
        let circlePickerVC = CirclePickerViewController(circles: circles)
        circlePickerVC.onCircleSelected = { [weak self] circle in
            self?.presentAddPlace(circleId: circle.id, circles: circles)
        }
        circlePickerVC.onCreateNewCircle = { [weak self] in
            self?.presentCreateCircleThenAddPlace()
        }

        let navController = UINavigationController(rootViewController: circlePickerVC)
        if UIDevice.current.userInterfaceIdiom == .pad {
            navController.modalPresentationStyle = .formSheet
            navController.preferredContentSize = CGSize(width: 400, height: 600)
        } else {
            navController.modalPresentationStyle = .pageSheet
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(navController, animated: true)
    }

    private func presentCreateCircleThenAddPlace() {
        pendingAddPlaceAfterCircleCreation = true
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        let navController = UINavigationController(rootViewController: createCircleVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }

    /// Drops the freshly saved place onto the map right away; the presenter's
    /// own data refresh reconciles the full set later.
    @objc private func handlePlaceAddedFromMap(_ notification: Notification) {
        guard awaitingPlaceAddedFromMap else { return }
        guard let place = notification.userInfo?["place"] as? Place else { return }
        awaitingPlaceAddedFromMap = false
        guard !places.contains(where: { $0.id == place.id }) else { return }
        // A circle-mode map shows a single circle — only reflect adds that
        // actually went to it (the add screen's dropdown can switch circles)
        if viewMode == .circle,
           let shownCircleId = places.first?.circleId,
           place.circleId != shownCircleId {
            return
        }
        updatePlaces(places + [place], adjustRegion: false)
    }

    /// Rebuilds the distance-sorted data source for the places list from the
    /// currently filtered places. Places without a location sort last.
    private func rebuildDistanceSortedPlaces() {
        let reference = currentUserLocation
            ?? CLLocation(latitude: currentRegion.center.latitude, longitude: currentRegion.center.longitude)

        // Collapse multiple save docs for the same venue to one (a place saved
        // by several people, or into multiple circles, was showing twice) —
        // mirrors the home list via the shared Place.dedupedByVenue.
        let deduped = Place.dedupedByVenue(filteredPlaces, preferredOwnerId: AuthService.shared.getUserId() ?? "")
        distanceSortedPlaces = DistancePlaceSorter.sorted(deduped, from: reference)

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

    private func selectCategory(_ category: UnifiedCategory?) {
        selectedCategory = category
        // A filter change is explicit user intent — allow zooming to results
        hasExplicitInitialRegion = false
        applyFilter()
    }

    private func selectConnection(_ connectionId: String?) {
        Logger.debug("🔍 FullScreenMap: selectConnection called with: \(connectionId ?? "nil")")
        selectedConnectionId = connectionId
        if connectionId == nil || connectionId == HomePlaceFilter.myPlacesOnlyId || connectionId == HomePlaceFilter.myConnectionsOnlyId {
            selectedConnectionUser = nil
        }
        // The origin sub-filter only makes sense under My Places
        if connectionId != HomePlaceFilter.myPlacesOnlyId { selectedImportOrigin = nil }
        updateConnectionAvatarChip()
        updateMyPlacesChipAppearance()
        // The dropdown header narrates this selection too — every path that
        // changes the connection (Me chip, hamburger, dropdown) lands here,
        // so this one call keeps the label honest for all of them.
        updateFilterHeaderTitles()
        // Keep the avatar row's highlight ring in sync (also covers changes
        // made through the hamburger menu)
        userListView?.selectedUserId = (connectionId == nil || connectionId == HomePlaceFilter.myPlacesOnlyId || connectionId == HomePlaceFilter.myConnectionsOnlyId) ? nil : connectionId
        // Let the presenter mirror the selection so it survives dismissal
        delegate?.mapViewController(self, didChangeConnectionFilter: connectionId)
        // Switching connections keeps the current camera — you're comparing
        // who-saved-what in the same view, so don't re-frame. (The coverage
        // banner offers to expand when the selection has nothing in view.)
        resetCoverageBannerDismissal()
        hasExplicitInitialRegion = false
        applyFilter(adjustRegion: false)
    }

    private func applyFilter(adjustRegion: Bool = true) {
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        Logger.debug("🔍 FullScreenMap: applyFilter called")
        Logger.debug("  selectedConnectionId: \(selectedConnectionId ?? "nil")")
        Logger.debug("  viewMode: \(viewMode)")
        Logger.debug("  Total places: \(places.count)")
        
        // Start with all places or connection-specific places
        let placesToFilter = connectionScopedPlaces()

        // Update available categories based on connection-filtered places
        updateAvailableCategories(from: placesToFilter)

        // Apply category filter
        filteredPlaces = placesToFilter.filtered(by: selectedCategory)

        // Chip-bar mode: the always-visible category-group + state chips
        // (replacing the hamburger's Category menu)
        if showsFilterChips {
            filteredPlaces = applyChipFilters(filteredPlaces)
        }

        // Search text is a pure additional AND predicate — composes with the
        // connection scope (modal) or home's pre-filter (embedded child)
        // without double-filtering either. Deliberately outside
        // applyChipFilters: that method is also the home list's chip contract,
        // and non-chip maps run applyFilter too.
        filteredPlaces = applySearchFilter(filteredPlaces)
        Logger.debug("  Final filtered places: \(filteredPlaces.count)")
        
        updatePlacesCount()
        // The annotation pipeline zooms exactly once: at batch completion when
        // pins were added, or immediately when only removals occurred. A second
        // delayed adjustMapRegion here caused visible double-zoom animations.
        addAnnotationsToMap(adjustRegion: adjustRegion)

        // Keep the distance-sorted list in sync when it's visible
        if isShowingPlacesList {
            rebuildDistanceSortedPlaces()
            placesListTableView.reloadData()
        }
    }
    
    private func updateAvailableCategories(from placesToAnalyze: [Place]? = nil) {
        // Use centralized utility to get unique categories from the specified places
        // (the hamburger menu rebuilds itself on every open, so no UI refresh needed)
        let placesForAnalysis = placesToAnalyze ?? places
        availableCategories = PlaceCategory.uniqueCategories(from: placesForAnalysis)
    }
    
    private func updatePlacesCount() {
        // Don't show "0 places" during initial loading
        if filteredPlaces.isEmpty && placesCountLabel.text == "Loading..." {
            // Keep showing Loading...
            return
        }

        // The badge answers "how many pins am I looking at" — places inside
        // the CURRENT viewport, after every filter. It used to show the whole
        // filtered set, which never moved as you panned or zoomed, so 343 sat
        // in the corner regardless of what the screen actually showed.
        let visibleRect = mapView.visibleMapRect
        let visibleCount = filteredPlaces.filter { place in
            guard let coordinate = place.location?.clLocation?.coordinate else { return false }
            return visibleRect.contains(MKMapPoint(coordinate))
        }.count

        placesCountLabel.text = "\(visibleCount)"

        // This method owns the pill's visibility. The map's own pill now shows
        // on every surface — the home screen's duplicate is retired, since two
        // stacked pills with different numbers was the original "always 257"
        // bug in a new outfit.
        placesCountLabel.isHidden = isShowingPlacesList || visibleCount == 0

        // Search feedback (modal only — the embedded map's overlay list is
        // already explaining results while the user types). Search never moves
        // the camera, so when the matches sit outside the current view the
        // pill says so and a tap frames them — the user opts into the zoom.
        if isPresentedModally && showsFilterChips {
            if let query = searchQuery, filteredPlaces.isEmpty {
                searchEmptyLabel.text = "  No places match \"\(query)\"  "
                searchEmptyLabel.isHidden = false
            } else if searchQuery != nil, !filteredPlaces.isEmpty, visibleCount == 0 {
                let n = filteredPlaces.count
                searchEmptyLabel.text = "  \(n) match\(n == 1 ? "" : "es") outside this view — tap to show  "
                searchEmptyLabel.isHidden = false
            } else {
                searchEmptyLabel.isHidden = true
            }
        }

        updateConnectionCoverageBanner()
    }

    // MARK: - Connection coverage banner
    //
    // Switching connections keeps the camera put (no auto-zoom). When the
    // selected person — or you — has nothing showing in the current view, this
    // banner explains and offers ONE tap: show their other-category places that
    // ARE in view, or expand to frame their places. A dismiss ✕ hides it so you
    // can just pick another connection without it in the way.

    private var coverageBannerAction: (() -> Void)?
    private var coverageBannerDismissedForId: String?
    /// Set by the home controller while a tapped connection's circles/places are
    /// still loading. Until then the place set is incomplete (and the selected id
    /// may not yet be the canonical one the owner-match needs), so judging "no
    /// places" would flash a wrong verdict that the fetch then reverses.
    var isConnectionFetchPending = false {
        didSet { if oldValue != isConnectionFetchPending { updateConnectionCoverageBanner() } }
    }

    lazy var coverageBanner: MapCoverageBannerView = {
        let banner = MapCoverageBannerView()
        banner.onAction = { [weak self] in self?.coverageBannerAction?() }
        banner.onDismiss = { [weak self] in
            guard let self = self else { return }
            self.coverageBannerDismissedForId = self.selectedConnectionId ?? ""
            self.hideCoverageBanner()
        }
        return banner
    }()

    /// Reset the dismiss so the banner can re-evaluate for a new selection.
    func resetCoverageBannerDismissal() { coverageBannerDismissedForId = nil }

    /// Only for a specific person or your own places — aggregates (Everyone / My
    /// Connections) have no single "their places" to expand to.
    func updateConnectionCoverageBanner() {
        guard isViewLoaded else { return }
        // While a search query is active the search empty-state owns the
        // messaging — the banner's actions (clear category / zoom to their
        // places) would fight the text filter.
        guard searchQuery == nil else { hideCoverageBanner(); return }
        // Hold the verdict until the tapped connection's places have arrived.
        guard !isConnectionFetchPending else { hideCoverageBanner(); return }
        let id = selectedConnectionId
        let isSelf = (id == HomePlaceFilter.myPlacesOnlyId)
        let isPerson = (id != nil && id != HomePlaceFilter.myPlacesOnlyId && id != HomePlaceFilter.myConnectionsOnlyId)
        guard isSelf || isPerson else { hideCoverageBanner(); return }

        // Honor a dismiss until the selection changes.
        if let dismissed = coverageBannerDismissedForId, dismissed == (id ?? "") {
            hideCoverageBanner(); return
        }

        let rect = mapView.visibleMapRect
        func inView(_ list: [Place]) -> Int {
            list.filter { place in
                guard let c = place.location?.clLocation?.coordinate else { return false }
                return rect.contains(MKMapPoint(c))
            }.count
        }

        // Places from this selection are already showing — nothing to say.
        if inView(filteredPlaces) > 0 { hideCoverageBanner(); return }

        let scoped = connectionScopedPlaces()   // their places, all categories
        let anyInView = inView(scoped)
        let name = isSelf ? "You" : (selectedConnectionUser?.displayName ?? "This person")
        let has = isSelf ? "have" : "has"
        let their = isSelf ? "your" : "their"

        if anyInView > 0, selectedChipGroup != .all {
            // They have pins in view, just filtered out by the category chip.
            let cat = selectedChipGroup.title.lowercased()
            showCoverageBanner(
                message: "\(name) \(has) no \(cat) here.",
                actionTitle: "Show \(their) \(anyInView) place\(anyInView == 1 ? "" : "s") here"
            ) { [weak self] in self?.clearCategoryKeepingCamera() }
        } else if scoped.count > 0 {
            // Nothing in view, but they have places elsewhere.
            showCoverageBanner(
                message: "\(name) \(has) no places in this view.",
                actionTitle: "Show \(their) places"
            ) { [weak self] in self?.showConnectionPlaces() }
        } else {
            let msg = isSelf ? "You haven't saved any places yet."
                             : "\(name) hasn't saved any places yet."
            showCoverageBanner(message: msg, actionTitle: nil, action: nil)
        }
    }

    private func showCoverageBanner(message: String, actionTitle: String?, action: (() -> Void)?) {
        coverageBanner.configure(message: message, actionTitle: actionTitle)
        coverageBannerAction = action
        view.bringSubviewToFront(coverageBanner)
        coverageBanner.isHidden = false
    }

    private func hideCoverageBanner() {
        coverageBanner.isHidden = true
        coverageBannerAction = nil
    }

    /// Clear the category chip while keeping the current camera.
    private func clearCategoryKeepingCamera() {
        selectedChipGroup = .all
        refreshFilterChips()
        updateFilterHeaderTitles()
        applyFilter(adjustRegion: false)   // re-filter pins; camera stays
        // applyFilter → updatePlacesCount → updateConnectionCoverageBanner
    }

    /// Expand the camera to frame the selected connection's places (on demand).
    private func showConnectionPlaces() {
        // If the active category hides everything, clear it so there's something
        // to frame.
        if filteredPlaces.isEmpty && selectedChipGroup != .all {
            selectedChipGroup = .all
            refreshFilterChips()
            updateFilterHeaderTitles()
            applyFilter(adjustRegion: false)
        }
        zoomToFilteredPlaces()
        hideCoverageBanner()
    }
}

// MARK: - CLLocationManagerDelegate
extension FullScreenMapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Only zoom to user location if we haven't initially zoomed yet
        if !hasInitiallyZoomed {
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
            mapView.setRegion(region, animated: false)
            hasInitiallyZoomed = true
        }
        
        // Stop updating location after first update
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

// MARK: - UITableViewDataSource
extension FullScreenMapViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == placesListTableView {
            return distanceSortedPlaces.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == placesListTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "FullScreenPlaceListCell", for: indexPath) as! QuickAccessPlaceCell
            guard indexPath.row < distanceSortedPlaces.count else { return cell }
            let entry = distanceSortedPlaces[indexPath.row]
            let distanceText = entry.distance.map { listDistanceFormatter.string(fromDistance: $0) }
            cell.configure(with: entry.place, isSelected: false, distanceText: distanceText)
            return cell
        }

        return UITableViewCell()
    }
}

// MARK: - UITableViewDelegate
extension FullScreenMapViewController {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView == placesListTableView, indexPath.row < distanceSortedPlaces.count else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        // Same path as tapping a pin's info button — the delegate presents the
        // place detail on top of this map
        delegate?.mapViewController(self, didSelectPlace: distanceSortedPlaces[indexPath.row].place)
    }
}

// MARK: - CreateCircleDelegate
extension FullScreenMapViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        // "+" chip flow paused on circle creation: CreateCircle dismisses
        // itself right after this callback, so wait for the sheet to clear
        // before presenting the add screen
        if pendingAddPlaceAfterCircleCreation {
            pendingAddPlaceAfterCircleCreation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.presentAddPlace(circleId: circle.id)
            }
            return
        }

        // POI-originated circle creation is handled by MapPOIAddCoordinator
    }
}

// MARK: - MapPOIAddCoordinatorDelegate

extension FullScreenMapViewController: MapPOIAddCoordinatorDelegate {
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, existingPlaceNamed name: String, at coordinate: CLLocationCoordinate2D) -> Place? {
        findExistingPlace(name: name, coordinate: coordinate)
    }

    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, didChooseExistingPlace place: Place) {
        delegate?.mapViewController(self, didSelectPlace: place)
        dismiss(animated: true)
    }
}

// MARK: - HorizontalUserListViewDelegate (modal avatar row)

extension FullScreenMapViewController: HorizontalUserListViewDelegate {
    func didSelectUser(_ user: User, connectionId: String) {
        // Filter keys in connectionPlaces are the connection's otherUserId —
        // resolve through the connections list so the ids line up
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let targetId = connections.first(where: {
            IDNormalizer.isSameUser($0.otherUserId(currentUserId: currentUserId), user.id)
        })?.otherUserId(currentUserId: currentUserId) ?? user.id

        // Same behavior as the home row: tapping the already-selected avatar
        // opens the profile; otherwise switch the filter to that connection
        if let selected = selectedConnectionId, selected != HomePlaceFilter.myPlacesOnlyId,
           IDNormalizer.isSameUser(selected, targetId) {
            presentProfile(for: user)
        } else {
            selectedConnectionUser = user
            selectConnection(targetId)
        }
    }

    func didLongPressUser(_ user: User, connectionId: String) {
        presentProfile(for: user)
    }
}

// MARK: - UISearchBarDelegate (modal pin search)
extension FullScreenMapViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        setSearchFilter(searchText) // debounced inside; never moves the camera
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - MapFilterMenuBuilderDelegate

extension FullScreenMapViewController: MapFilterMenuBuilderDelegate {
    func menuBuilderState(_ builder: MapFilterMenuBuilder) -> MapFilterMenuBuilder.State {
        var state = MapFilterMenuBuilder.State()
        state.selectedConnectionId = selectedConnectionId
        state.selectedImportOrigin = selectedImportOrigin
        state.selectedChipGroup = selectedChipGroup
        state.selectedChipRegionId = selectedChipRegionId
        state.chipRegionGroups = chipRegionGroups
        state.chipOrigin = chipOrigin
        state.places = places
        state.connections = connections
        state.facetBase = applyOriginFilter(connectionScopedPlaces())
        return state
    }

    func menuBuilder(_ builder: MapFilterMenuBuilder, perform action: MapFilterMenuAction) {
        switch action {
        case .selectConnection(let id, let user):
            selectConnectionFromHeader(id: id, user: user)

        case .selectMyPlaces:
            selectedImportOrigin = nil
            selectConnectionFromHeader(id: HomePlaceFilter.myPlacesOnlyId, user: nil)

        case .selectImportOrigin(let origin):
            selectedImportOrigin = origin
            if selectedConnectionId == HomePlaceFilter.myPlacesOnlyId {
                chipFiltersChanged()
            } else {
                selectConnectionFromHeader(id: HomePlaceFilter.myPlacesOnlyId, user: nil)
                // Embedded: the scope change round-trips through the
                // home controller; re-run the chip pipeline so the
                // origin cut applies to whatever it hands back
                chipFiltersChanged()
            }

        case .selectChipGroup(let group):
            selectedChipGroup = group
            chipFiltersChanged()

        case .selectRegion(let id):
            selectedChipRegionId = id
            // Only picking a specific region deliberately moves the camera
            chipFiltersChanged(zoomToRegion: id != nil)
        }
    }
}
