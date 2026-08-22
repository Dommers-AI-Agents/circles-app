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
}

// Default no-ops so existing conformers don't need to handle every event
extension FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion) {}
    func mapViewController(_ controller: FullScreenMapViewController, didChangeConnectionFilter connectionId: String?) {}
    func mapViewControllerDidChangeChipFilters(_ controller: FullScreenMapViewController) {}
}

enum MapViewMode {
    case circle
    case allPlaces
}


class FullScreenMapViewController: UIViewController, MKMapViewDelegate, UITableViewDelegate {
    
    // MARK: - Properties
    private var places: [Place]
    private var initialRegion: MKCoordinateRegion
    private var annotationPlaceMap: [ObjectIdentifier: Place] = [:]
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
    private var pendingPOIAnnotation: Any? // MKMapFeatureAnnotation for iOS 16+
    private var pendingPOINotes: String? // Temporary storage for notes when creating new circle
    private var pendingAddPlaceAfterCircleCreation = false // "+" chip flow paused on circle creation
    private var awaitingPlaceAddedFromMap = false // An add-place flow launched from this map is in flight
    private var currentCirclePicker: CirclePickerSliderView? // Reference to current circle picker
    private var isAdjustingRegion = false // Prevent concurrent region adjustments
    private var hasInitiallyZoomed = false // Track if we've done the initial zoom
    private var hasExplicitInitialRegion = false // Caller provided a region to open at
    private var viewportFetchTimer: Timer? // Debounce for viewport (region-change) notifications

    // MARK: - Google-style pin decluttering (full pins vs. dots)
    // Every place renders at its true location; the places nearest the user
    // (or map center) hold full category pins until pins would overlap, and
    // the rest render as small category-colored dots that promote to full
    // pins on zoom-in. No numbered cluster bubbles, ever.
    private var promotedPlaceIds = Set<String>()
    private var pinTierRecomputeTimer: Timer?
    private let maxFullPins = 45
    
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

    /// Read access for the presenter, so expansion can copy the live state.
    var currentChipGroup: PlaceCategoryGroup { selectedChipGroup }
    var currentChipRegionId: String? { selectedChipRegionId }

    /// Returns the chip filters to their load state (All Categories · All
    /// Places) — the Home tab's reset uses this so a re-tap really does put
    /// the whole map header back to "Me · All Categories · All Places".
    func resetChipFilters() {
        guard showsFilterChips else { return }
        guard selectedChipGroup != .all || selectedChipRegionId != nil else { return }
        selectedChipGroup = .all
        selectedChipRegionId = nil
        refreshFilterChips()
        applyFilter(adjustRegion: false)
    }

    /// The place set scoped to the current connection filter — the shared base
    /// for applyFilter AND the facet counts in the dropdown menus. Only the
    /// MODAL scopes for itself; the embedded child receives places already
    /// filtered by the home controller, and re-filtering them by addedBy drops
    /// places saved under a connection's legacy account id (circle owner and
    /// place adder can be different ids for the same person).
    private func connectionScopedPlaces() -> [Place] {
        guard viewMode == .allPlaces, isPresentedModally else { return places }

        let currentUserIdForScope = AuthService.shared.getUserId() ?? ""
        guard let connectionId = selectedConnectionId else {
            // "Everyone" (nil) — yourself + accepted connections + everyone you
            // follow. Union of the pre-bucketed connection lists and an addedBy
            // sweep (covers viewport-fetched places that were never bucketed).
            var authorIds = Set(connections.map { $0.otherUserId(currentUserId: currentUserIdForScope) })
            authorIds.formUnion(NetworkManager.shared.followingUsers.map { $0.id })
            authorIds.insert(currentUserIdForScope)
            authorIds = authorIds.filter { !$0.isEmpty }
            var scoped = authorIds.flatMap { connectionPlaces[$0] ?? [] }
            let scopedIds = Set(scoped.map { $0.id })
            scoped += places.filter { place in
                !scopedIds.contains(place.id) &&
                authorIds.contains { IDNormalizer.isSameUser(place.addedBy, $0) }
            }
            return scoped
        }

        if connectionId == "my_places_only" {
            let currentUserId = AuthService.shared.getUserId() ?? ""
            return places.filter { IDNormalizer.isSameUser($0.addedBy, currentUserId) }
        }
        if connectionId == "my_connections_only" {
            // Accepted connections only (the narrower cut of the default
            // "Following" view): union of every connection's bucket plus an
            // addedBy sweep for viewport places that were never bucketed
            let currentUserId = AuthService.shared.getUserId() ?? ""
            let connectedIds = connections.map { $0.otherUserId(currentUserId: currentUserId) }
            var scoped = connectedIds.flatMap { connectionPlaces[$0] ?? [] }
            let scopedIds = Set(scoped.map { $0.id })
            scoped += places.filter { place in
                !scopedIds.contains(place.id) &&
                connectedIds.contains { IDNormalizer.isSameUser(place.addedBy, $0) }
            }
            return scoped
        }
        // Union of the pre-bucketed list (covers circle-owner semantics) and an
        // added-by match over the CURRENT places (covers viewport-fetched
        // places that were never bucketed, and missing buckets). Never fall
        // through to showing everyone's places.
        var connectionScoped = connectionPlaces[connectionId] ?? []
        let bucketedIds = Set(connectionScoped.map { $0.id })
        connectionScoped += places.filter {
            !bucketedIds.contains($0.id) && IDNormalizer.isSameUser($0.addedBy, connectionId)
        }
        return connectionScoped
    }

    /// Applies the current chip selections (category group + region) to any
    /// place list. Public so the embedding home page can run its OWN list
    /// through the exact same filter the pins use — the chips live in this
    /// controller, and a list that ignores them contradicts the map beside it.
    func applyChipFilters(_ list: [Place]) -> [Place] {
        var result = applyOriginFilter(list)
        if selectedChipGroup != .all {
            result = result.filter { selectedChipGroup.matches($0.category.rawValue) }
        }
        if let regionId = selectedChipRegionId,
           let region = chipRegionGroups.first(where: { $0.id == regionId }) {
            result = result.filter { region.contains($0) }
        }
        return result
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
        guard let origin = selectedImportOrigin else { return list }
        return list.filter { origin == "in_app" ? $0.importSource == nil : $0.importSource == origin }
    }

    /// Display name for an origin row: the source itself ("FavCircles",
    /// "Google Places") — the menu marks these as sub-rows of My Places, so
    /// the label doesn't restate it.
    private static func originTitle(_ origin: String) -> String {
        switch origin {
        case "in_app": return "FavCircles"
        case "google_maps": return "Google Places"
        case "mapstr": return "Mapstr"
        case "swarm": return "Swarm"
        default: return origin.capitalized
        }
    }

    /// Zooms to enclose exactly the filtered places (tap NJ → the camera frames
    /// New Jersey). Computed from the places themselves rather than the
    /// annotations, so it doesn't race the batched pin updates. Extra top
    /// padding keeps pins clear of the overlaid chip bars.
    private func zoomToFilteredPlaces(animated: Bool = true) {
        let coordinates = filteredPlaces.compactMap { $0.location?.clLocation?.coordinate }
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let only = coordinates.first {
            mapView.setRegion(MKCoordinateRegion(
                center: only, latitudinalMeters: 2_000, longitudinalMeters: 2_000
            ), animated: animated)
            return
        }

        var union = MKMapRect.null
        for coordinate in coordinates {
            union = union.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
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
            self.withConnectionAvatarsWarmed {
                done(self.connectionMenuElements())
            }
        }])
        categoryFilterButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.categoryMenuElements() ?? [])
        }])
        placeFilterButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.placeMenuElements() ?? [])
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
        case "my_connections_only": connectionTitle = "My Connections"
        case "my_places_only":
            if let origin = selectedImportOrigin {
                connectionTitle = "My Places › \(Self.originTitle(origin))"
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

    /// Everyone / My Connections / My Places, then each person in the home
    /// connections row's order — the same ranking, so the list reads identically
    /// everywhere. Each person shows their avatar, so it scans by face not name.
    private func connectionMenuElements() -> [UIMenuElement] {
        // "My Places" wears YOUR face — same circular treatment as everyone
        // below it, so the row reads as you rather than a generic glyph.
        let myAvatar: UIImage?
        if let me = AuthService.shared.currentUser {
            myAvatar = menuAvatar(for: me)
        } else {
            myAvatar = UIImage(systemName: "person.crop.circle.fill")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }

        // "Everyone" gets a two-tone palette symbol — one figure in the
        // brand color, one in a warm accent — so it reads as "everyone", not
        // another flat glyph. Rasterized to pixels: withRenderingMode after
        // applyingSymbolConfiguration silently DROPS the palette, and menus
        // re-tint template images — baking the bitmap sidesteps both.
        let followingIcon: UIImage? = {
            guard let symbol = UIImage(
                systemName: "person.2.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                    .applying(UIImage.SymbolConfiguration(paletteColors: [Constants.Colors.primary, .systemOrange]))
            ) else { return nil }
            return UIGraphicsImageRenderer(size: symbol.size).image { _ in
                symbol.draw(at: .zero)
            }.withRenderingMode(.alwaysOriginal)
        }()

        // "Everyone" (nil) leads the list — the default scope: you + your
        // accepted connections + everyone you follow.
        var actions: [UIAction] = [
            UIAction(title: "Everyone",
                     image: followingIcon,
                     state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                self?.selectConnectionFromHeader(id: nil, user: nil)
            }
        ]

        // "My Connections" = accepted connections only (the narrower cut).
        let myConnectionsIcon = UIImage(
            systemName: "person.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        )?.withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        actions.append(
            UIAction(title: "My Connections",
                     image: myConnectionsIcon,
                     state: selectedConnectionId == "my_connections_only" ? .on : .off) { [weak self] _ in
                self?.selectConnectionFromHeader(id: "my_connections_only", user: nil)
            }
        )

        // "My Places" wears YOUR face — same circular treatment as everyone
        // below it, so the row reads as you rather than a generic glyph.
        actions.append(
            UIAction(title: "My Places",
                     image: myAvatar,
                     state: selectedConnectionId == "my_places_only" && selectedImportOrigin == nil ? .on : .off) { [weak self] _ in
                self?.selectedImportOrigin = nil
                self?.selectConnectionFromHeader(id: "my_places_only", user: nil)
            }
        )

        // Origin sub-rows under My Places — only for users whose own places
        // include imports. Splits your pins into in-app adds vs each import
        // source ("was this from Google or added on FavCircles?").
        let currentUserIdForOrigins = AuthService.shared.getUserId() ?? ""
        let mySources = Set(places
            .filter { IDNormalizer.isSameUser($0.addedBy, currentUserIdForOrigins) }
            .compactMap { $0.importSource })
        if !mySources.isEmpty {
            var origins = ["in_app"] + mySources.sorted()
            // Keep the active selection pickable even if its places vanished
            if let active = selectedImportOrigin, !origins.contains(active) { origins.append(active) }
            for origin in origins {
                let icon = UIImage(systemName: origin == "in_app" ? "plus.app.fill" : "square.and.arrow.down.fill")?
                    .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
                actions.append(UIAction(
                    title: "›  \(Self.originTitle(origin))",
                    image: icon,
                    state: selectedConnectionId == "my_places_only" && selectedImportOrigin == origin ? .on : .off
                ) { [weak self] _ in
                    guard let self = self else { return }
                    self.selectedImportOrigin = origin
                    if self.selectedConnectionId == "my_places_only" {
                        self.chipFiltersChanged()
                    } else {
                        self.selectConnectionFromHeader(id: "my_places_only", user: nil)
                        // Embedded: the scope change round-trips through the
                        // home controller; re-run the chip pipeline so the
                        // origin cut applies to whatever it hands back
                        self.chipFiltersChanged()
                    }
                })
            }
        }

        // Person rows: ranked connections first (same order as the home row),
        // then everyone else you follow — the map can scope to any of them.
        let currentUserId = AuthService.shared.getUserId() ?? ""
        var listedIds = Set<String>()
        for connection in HorizontalUserListView.rankedConnections(connections) {
            guard let user = connection.connectedUser else { continue }
            let otherId = connection.otherUserId(currentUserId: currentUserId)
            listedIds.insert(otherId)
            actions.append(UIAction(title: user.displayName,
                                    image: menuAvatar(for: user),
                                    state: selectedConnectionId == otherId ? .on : .off) { [weak self] _ in
                self?.selectConnectionFromHeader(id: otherId, user: user)
            })
        }
        for user in NetworkManager.shared.followingUsers {
            guard !user.id.isEmpty,
                  !listedIds.contains(user.id),
                  !IDNormalizer.isSameUser(user.id, currentUserId) else { continue }
            listedIds.insert(user.id)
            actions.append(UIAction(title: user.displayName,
                                    image: menuAvatar(for: user),
                                    state: selectedConnectionId == user.id ? .on : .off) { [weak self] _ in
                self?.selectConnectionFromHeader(id: user.id, user: user)
            })
        }
        return actions
    }

    /// Circular avatar for a menu row, from the image cache. On a cache miss,
    /// returns a placeholder and prefetches so the NEXT open of this menu (it's
    /// rebuilt fresh every time via UIDeferredMenuElement) shows the photo.
    /// Downloads every menu avatar that isn't already cached, then calls
    /// `completion` (on main). Capped so a dead network can't hold the menu
    /// hostage — anything still missing falls back to the placeholder.
    private func withConnectionAvatarsWarmed(timeout: TimeInterval = 0.6, _ completion: @escaping () -> Void) {
        // The people list includes everyone followed — make sure that roster
        // is loaded before the menu builds (first open of the session)
        if NetworkManager.shared.followingUsers.isEmpty {
            NetworkManager.shared.loadFollowingUsers { [weak self] in
                self?.warmAvatars(timeout: timeout, completion)
            }
        } else {
            warmAvatars(timeout: timeout, completion)
        }
    }

    private func warmAvatars(timeout: TimeInterval, _ completion: @escaping () -> Void) {
        var users = connections.compactMap { $0.connectedUser }
        users.append(contentsOf: NetworkManager.shared.followingUsers)
        if let me = AuthService.shared.currentUser { users.append(me) }

        let pending: [(id: String, url: String)] = users.compactMap { user in
            guard let url = user.profilePicture, !url.isEmpty,
                  ImageService.shared.cachedImage(forKey: "profile_\(user.id)_\(url.hashValue)") == nil
            else { return nil }
            return (user.id, url)
        }
        guard !pending.isEmpty else { completion(); return }

        let group = DispatchGroup()
        pending.forEach { item in
            group.enter()
            ImageService.shared.loadProfileImage(for: item.id, from: item.url) { _ in group.leave() }
        }
        var finished = false
        let finish = { if !finished { finished = true; completion() } }
        group.notify(queue: .main) { finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish() }
    }

    private func menuAvatar(for user: User) -> UIImage? {
        // No photo → a colored, filled avatar (never the flat grey glyph). The
        // hue is derived from the user id so a person keeps one color across
        // launches and the list reads as a row of distinct faces.
        let placeholder = Self.coloredAvatarPlaceholder(for: user)
        guard let urlString = user.profilePicture, !urlString.isEmpty else { return placeholder }

        let cacheKey = "profile_\(user.id)_\(urlString.hashValue)"
        if let cached = ImageService.shared.cachedImage(forKey: cacheKey) {
            return Self.circularMenuImage(cached)
        }
        // Warm the cache for the next open; menus can't be mutated in place.
        ImageService.shared.loadProfileImage(for: user.id, from: urlString) { _ in }
        return placeholder
    }

    /// A colored, filled person glyph for menu rows without a profile photo.
    /// Hue is picked deterministically from the user id so the same person keeps
    /// one color across launches (String.hashValue is per-process seeded, so we
    /// sum unicode scalars instead of hashing).
    static func coloredAvatarPlaceholder(for user: User) -> UIImage? {
        let palette: [UIColor] = [
            Constants.Colors.primary, .systemOrange, .systemPink, .systemPurple,
            .systemTeal, .systemGreen, .systemIndigo, .systemRed
        ]
        let seed = user.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let color = palette[seed % palette.count]
        return UIImage(
            systemName: "person.crop.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// Aspect-fill crops an image into a small circle for use as a menu icon.
    static func circularMenuImage(_ image: UIImage, diameter: CGFloat = 26) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(diameter / max(image.size.width, 1), diameter / max(image.size.height, 1))
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: CGRect(x: (diameter - width) / 2, y: (diameter - height) / 2, width: width, height: height))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func categoryMenuElements() -> [UIMenuElement] {
        // Faceted: the options come from the set filtered by the OTHER active
        // filters (connection + region), so "Dan · Rhode Island" offers only
        // the categories Dan actually has in Rhode Island.
        var facetBase = applyOriginFilter(connectionScopedPlaces())
        if let regionId = selectedChipRegionId,
           let region = chipRegionGroups.first(where: { $0.id == regionId }) {
            facetBase = facetBase.filter { region.contains($0) }
        }
        var groups = PlaceCategoryGroup.present(in: facetBase.map { $0.category.rawValue })
        // Never hide the active selection, even at zero — you need the row to
        // un-pick it.
        if selectedChipGroup != .all && !groups.contains(selectedChipGroup) {
            groups.append(selectedChipGroup)
        }
        return groups.map { group in
            UIAction(title: group == .all ? "All Categories" : group.title,
                     image: categoryMenuIcon(for: group),
                     state: selectedChipGroup == group ? .on : .off) { [weak self] _ in
                self?.selectedChipGroup = group
                self?.chipFiltersChanged()
            }
        }
    }

    /// One path for every chip change: refresh the header, re-filter, re-zoom,
    /// and tell the delegate — the home page keeps its own list in lockstep.
    private func chipFiltersChanged() {
        updateFilterHeaderTitles()
        applyFilter(adjustRegion: false)
        zoomToFilteredPlaces()
        delegate?.mapViewControllerDidChangeChipFilters(self)
    }

    /// Menu icon matching the map pins' color coding: each group shows its
    /// category's glyph in its pin color, so the dropdown reads like a legend.
    private func categoryMenuIcon(for group: PlaceCategoryGroup) -> UIImage? {
        if group == .all {
            return UIImage(systemName: "square.grid.2x2")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        let raw = group.categories.contains("other")
            ? "other"
            : (group.categories.sorted().first ?? "other")
        let category = PlaceCategory(rawValue: raw) ?? .other
        return UIImage(systemName: category.systemIconName)?
            .withTintColor(category.color, renderingMode: .alwaysOriginal)
    }

    /// All Places, Near me (when a fix landed), then states most-places-first.
    private func placeMenuElements() -> [UIMenuElement] {
        // Faceted: regions and their counts come from the set filtered by the
        // OTHER active filters (connection + category), so "Dan · Hotels"
        // shows "Rhode Island (2)" and no Arizona row at all. Selecting a
        // region still stores the id, which applyFilter resolves against the
        // full chipRegionGroups (same ids — same grouper).
        var facetBase = applyOriginFilter(connectionScopedPlaces())
        if selectedChipGroup != .all {
            facetBase = facetBase.filter { selectedChipGroup.matches($0.category.rawValue) }
        }
        var facetGroups = RegionGrouper.groups(for: facetBase, origin: chipOrigin)
        // Never hide the active selection, even at zero — you need the row to
        // un-pick it.
        if let selectedId = selectedChipRegionId,
           !facetGroups.contains(where: { $0.id == selectedId }),
           let full = chipRegionGroups.first(where: { $0.id == selectedId }) {
            facetGroups.append(RegionGroup(
                id: full.id, title: full.title, count: 0,
                placeIds: [], centroid: full.centroid
            ))
        }

        var actions: [UIAction] = [
            UIAction(title: "All Places",
                     image: Self.emojiImage("🌎"),
                     state: selectedChipRegionId == nil ? .on : .off) { [weak self] _ in
                self?.selectedChipRegionId = nil
                self?.chipFiltersChanged()
            }
        ]
        for group in facetGroups {
            actions.append(UIAction(title: "\(group.title) (\(group.count))",
                                    image: regionMenuImage(for: group),
                                    state: selectedChipRegionId == group.id ? .on : .off) { [weak self] _ in
                self?.selectedChipRegionId = group.id
                self?.chipFiltersChanged()
            })
        }
        return actions
    }

    /// Row image for a region: the bundled state flag for US states, the emoji
    /// flag for countries, a location glyph for "Near me". States without a
    /// flag asset (e.g. DC) simply show no image.
    private func regionMenuImage(for group: RegionGroup) -> UIImage? {
        if group.id == "near-me" {
            return UIImage(systemName: "location.fill")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        if group.id == "other-countries" {
            return UIImage(systemName: "globe")?
                .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        }
        if group.id.hasPrefix("state:") {
            let code = String(group.id.dropFirst("state:".count)).lowercased()
            // Every code RegionGrouper can emit has a bundled flag (50 states +
            // DC/PR/VI/GU), so states appearing for the first time — a user's
            // first Montana place — get their flag with no code change. The US
            // flag is the safety net if an asset is ever missing, so a state
            // row never shows imageless next to flagged siblings.
            if let flag = UIImage(named: "flag-us-\(code)") {
                return flag.withRenderingMode(.alwaysOriginal)
            }
            return Self.emojiFlagImage(countryCode: "US")
        }
        if group.id.hasPrefix("country:") {
            // Rendered from the ISO2 code at runtime — any country that ever
            // appears gets its emoji flag with no bundled asset.
            let code = String(group.id.dropFirst("country:".count))
            return Self.emojiFlagImage(countryCode: code)
        }
        return nil
    }

    /// Renders a country's emoji flag (🇨🇦) into a menu-sized image.
    static func emojiFlagImage(countryCode: String) -> UIImage? {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            guard let indicator = UnicodeScalar(base + scalar.value) else { return nil }
            flag.append(String(indicator))
        }
        return emojiImage(flag)
    }

    /// Renders any emoji (🌎, 🇨🇦) into a menu-sized image — full color, unlike
    /// tinted SF Symbols.
    static func emojiImage(_ emoji: String, fontSize: CGFloat = 20) -> UIImage? {
        let attributed = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
        let size = attributed.size()
        guard size.width > 0 else { return nil }
        return UIGraphicsImageRenderer(size: size).image { _ in
            attributed.draw(at: .zero)
        }.withRenderingMode(.alwaysOriginal)
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
        if id != "my_places_only" { selectedImportOrigin = nil }
        updateFilterHeaderTitles()
    }

    /// Supplies the Connection dropdown's roster when embedded (the modal path
    /// already receives connections with its places).
    func setAvailableConnections(_ list: [Connection]) {
        connections = list
        updateFilterHeaderTitles()
        // Start avatar downloads now, long before the dropdown can be opened —
        // by first tap the cache is warm and the menu shows faces immediately.
        withConnectionAvatarsWarmed {}
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
              selectedConnectionId != nil, selectedConnectionId != "my_places_only" else {
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
        if connectionId == nil || connectionId == "my_places_only" || connectionId == "my_connections_only" {
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
            applyFilter()
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
        withConnectionAvatarsWarmed {}
        
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
            }

            // Legacy avatar row only in hamburger mode — the Connection
            // dropdown covers switching in header mode.
            if !showsFilterChips && viewMode == .allPlaces && showsConnectionFilter {
                let row = HorizontalUserListView(frame: .zero, initialConnections: connections)
                row.translatesAutoresizingMaskIntoConstraints = false
                row.backgroundColor = .clear
                row.delegate = self
                if let selected = selectedConnectionId, selected != "my_places_only" {
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
            placesCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ]
        
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
                // Places list fills the map area below whichever header is up
                placesListTableView.topAnchor.constraint(
                    equalTo: showsFilterChips ? filterChipsContainer.bottomAnchor : view.safeAreaLayoutGuide.topAnchor,
                    constant: showsFilterChips ? 8 : 60
                ),
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
        // Use smooth differential update instead of clearing everything
        updateMapAnnotationsSmooth(adjustRegion: adjustRegion)
    }

    // MARK: - Smooth Map Loading Implementation

    private func updateMapAnnotationsSmooth(adjustRegion: Bool = true) {
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.debug("🗺️ [SmoothMap] Starting smooth annotation update...")
        
        // Get places that should be on the map
        let placesWithLocation = filteredPlaces.filter { $0.location?.clLocation != nil }
        let newPlaceIds = Set(placesWithLocation.map { $0.id })
        
        // Get current annotations and their place IDs
        let currentAnnotations = mapView.annotations.compactMap { $0 as? PlaceAnnotation }
        let currentPlaceIds = Set(currentAnnotations.compactMap { annotationPlaceMap[ObjectIdentifier($0)]?.id })
        
        // Calculate differences
        let placesToAdd = placesWithLocation.filter { !currentPlaceIds.contains($0.id) }
        let annotationsToRemove = currentAnnotations.filter { 
            guard let place = annotationPlaceMap[ObjectIdentifier($0)] else { return true }
            return !newPlaceIds.contains(place.id)
        }
        
        Logger.debug("🗺️ [SmoothMap] Differential update:")
        Logger.debug("   Current: \(currentAnnotations.count) annotations")
        Logger.debug("   To add: \(placesToAdd.count) places")
        Logger.debug("   To remove: \(annotationsToRemove.count) annotations")
        
        // Remove obsolete annotations smoothly
        if !annotationsToRemove.isEmpty {
            // Clean up annotation mapping
            for annotation in annotationsToRemove {
                annotationPlaceMap.removeValue(forKey: ObjectIdentifier(annotation))
            }
            
            // Remove with animation
            mapView.removeAnnotations(annotationsToRemove)
        }
        
        // Add new annotations in batches for smooth loading
        if !placesToAdd.isEmpty {
            addAnnotationsBatched(placesToAdd, adjustRegion: adjustRegion)
        } else if adjustRegion {
            // If no new places to add, just adjust region
            adjustMapRegion()
        } else if !annotationsToRemove.isEmpty {
            // Removal-only update (e.g. narrower filter): freed space may let
            // remaining dots promote to full pins
            schedulePinTierRecompute()
        }
        
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        Logger.debug("🗺️ [SmoothMap] Update completed in \(String(format: "%.3f", loadTime))s")
    }
    
    private func addAnnotationsBatched(_ places: [Place], adjustRegion: Bool = true) {
        // Add all annotations in one pass. The previous 15-at-a-time staggering
        // (0.05s between batches + a 0.1s tail) delayed the camera by up to
        // ~0.75s on a filter change — the map felt slow to settle. MapKit
        // handles a bulk add fine, and the zoom can happen immediately after.
        let annotations = places.compactMap { place -> PlaceAnnotation? in
            guard place.location?.clLocation != nil else { return nil }
            let annotation = PlaceAnnotation(place: place)
            annotationPlaceMap[ObjectIdentifier(annotation)] = place
            return annotation
        }

        mapView.addAnnotations(annotations)
        Logger.debug("🗺️ [SmoothMap] Added \(annotations.count) annotations in one pass")

        schedulePinTierRecompute()

        if adjustRegion {
            adjustMapRegion()
        }
    }

    // MARK: - Pin Tiering (full pins near the user, dots elsewhere)

    /// Debounced recompute — region changes and annotation churn both land here.
    func schedulePinTierRecompute(delay: TimeInterval = 0.25) {
        pinTierRecomputeTimer?.invalidate()
        pinTierRecomputeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.recomputePinTiers()
        }
    }

    /// Decide which places get full category pins vs. small dots.
    ///
    /// Greedy pass in priority order (distance from the user's location when
    /// it's on screen, else from the map center): a place keeps its full pin
    /// if the pin's screen rect doesn't collide with an already-accepted pin,
    /// up to `maxFullPins`. Everything else renders as a dot at its true
    /// coordinate. Zooming in frees space, so dots promote automatically on
    /// the next region-change recompute.
    private func recomputePinTiers() {
        let placeAnnotations = mapView.annotations.compactMap { $0 as? PlaceAnnotation }
        guard !placeAnnotations.isEmpty else {
            promotedPlaceIds.removeAll()
            return
        }

        // Anchor: pins should bloom around YOU when you're on screen
        let anchor: CLLocationCoordinate2D
        if let userCoord = mapView.userLocation.location?.coordinate,
           mapView.visibleMapRect.contains(MKMapPoint(userCoord)) {
            anchor = userCoord
        } else {
            anchor = mapView.centerCoordinate
        }
        let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)

        let byDistance = placeAnnotations
            .map { annotation -> (PlaceAnnotation, CLLocationDistance) in
                let c = annotation.coordinate
                let distance = anchorLocation.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                return (annotation, distance)
            }
            .sorted { $0.1 < $1.1 }

        // Approximate on-screen footprint of a full MKMarkerAnnotationView
        // (marker balloon is bottom-anchored at the coordinate)
        let pinSize = CGSize(width: 34, height: 42)
        let visibleBounds = mapView.bounds.insetBy(dx: -40, dy: -50)
        var acceptedRects: [CGRect] = []
        var newPromoted = Set<String>()

        // The selected annotation keeps its full pin no matter what —
        // demoting it would yank the callout out from under the user
        let selectedIds = Set(mapView.selectedAnnotations.compactMap { ($0 as? PlaceAnnotation)?.place.id })

        for (annotation, _) in byDistance {
            if newPromoted.count >= maxFullPins { break }
            let point = mapView.convert(annotation.coordinate, toPointTo: mapView)
            guard visibleBounds.contains(point) else { continue }
            let rect = CGRect(
                x: point.x - pinSize.width / 2,
                y: point.y - pinSize.height,
                width: pinSize.width,
                height: pinSize.height
            )
            if acceptedRects.contains(where: { $0.intersects(rect) }) { continue }
            acceptedRects.append(rect)
            newPromoted.insert(annotation.place.id)
        }
        newPromoted.formUnion(selectedIds)

        guard newPromoted != promotedPlaceIds else { return }
        let changedIds = newPromoted.symmetricDifference(promotedPlaceIds)
        promotedPlaceIds = newPromoted

        // Changed annotations must re-dequeue for their new tier; remove+add
        // is the reliable way to force that. Skip the selected annotation so
        // its open callout survives.
        let changed = placeAnnotations.filter {
            changedIds.contains($0.place.id) && !selectedIds.contains($0.place.id)
        }
        if !changed.isEmpty {
            mapView.removeAnnotations(changed)
            mapView.addAnnotations(changed)
        }
        Logger.debug("🗺️ [PinTiers] \(newPromoted.count) full pins, \(placeAnnotations.count - newPromoted.count) dots (\(changed.count) retiered)")
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
                                        (selectedConnectionId != nil && selectedConnectionId != "my_places_only") ||
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

            if !coordinates.isEmpty {
                // Calculate center and span to show all filtered places
                let minLat = coordinates.map { $0.latitude }.min() ?? 0
                let maxLat = coordinates.map { $0.latitude }.max() ?? 0
                let minLon = coordinates.map { $0.longitude }.min() ?? 0
                let maxLon = coordinates.map { $0.longitude }.max() ?? 0

                let center = CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                )

                // Add padding to the span, clamped to MapKit's valid limits so
                // setRegion never silently rejects the region
                let latDelta = min(max((maxLat - minLat) * 1.3, 0.01), 180)
                let lonDelta = min(max((maxLon - minLon) * 1.3, 0.01), 360)
                
                let span = MKCoordinateSpan(
                    latitudeDelta: latDelta,
                    longitudeDelta: lonDelta
                )
                
                Logger.debug("  - Setting region to center: \(center), span: \(span)")
                
                let region = MKCoordinateRegion(center: center, span: span)
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
                let minRadius: CLLocationDistance = 3_218.7   // 2 miles
                let maxRadius: CLLocationDistance = 40_233.6  // 25 miles

                let distances = focusPlaces
                    .compactMap { place -> CLLocationDistance? in
                        guard let placeLocation = place.location?.clLocation else { return nil }
                        return userLocation.distance(from: placeLocation)
                    }
                    .sorted()

                var radius = maxRadius
                if !distances.isEmpty {
                    let withinMax = distances.filter { $0 <= maxRadius }.count
                    if withinMax >= 3 {
                        // Enough favorites nearby: fit the closest 10 (or all nearby ones)
                        let targetIndex = min(9, withinMax - 1)
                        radius = min(max(distances[targetIndex] * 1.2, minRadius), maxRadius)
                    } else {
                        // Favorites are far away: zoom out just enough to show the nearest few
                        let targetIndex = min(2, distances.count - 1)
                        radius = max(distances[targetIndex] * 1.2, minRadius)
                    }
                }

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
                
                if !coordinates.isEmpty {
                    // Calculate center and span to show all places
                    let minLat = coordinates.map { $0.latitude }.min() ?? 0
                    let maxLat = coordinates.map { $0.latitude }.max() ?? 0
                    let minLon = coordinates.map { $0.longitude }.min() ?? 0
                    let maxLon = coordinates.map { $0.longitude }.max() ?? 0
                    
                    let center = CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLon + maxLon) / 2
                    )
                    
                    let span = MKCoordinateSpan(
                        latitudeDelta: (maxLat - minLat) * 1.3,
                        longitudeDelta: (maxLon - minLon) * 1.3
                    )
                    
                    let region = MKCoordinateRegion(center: center, span: span)
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
        if !promotedPlaceIds.contains(placeAnnotation.place.id) {
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
                handlePOISelection(featureAnnotation)
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
    private func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Get POI details
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let poiSubtitle = featureAnnotation.subtitle ?? ""
        let coordinate = featureAnnotation.coordinate
        
        // Check if this place already exists in the current places
        let isAlreadySaved = checkIfPOIAlreadyExists(name: poiName, coordinate: coordinate)
        
        // Show custom action sheet with options
        let alertController = UIAlertController(
            title: poiName,
            message: isAlreadySaved ? "\(poiSubtitle)\n\n✓ Already saved" : poiSubtitle,
            preferredStyle: .actionSheet
        )
        
        if !isAlreadySaved {
            // Add to Circle action only if not already saved
            let addToCircleAction = UIAlertAction(title: "Add to Circle", style: .default) { [weak self] _ in
                self?.showCirclePickerForPOI(featureAnnotation)
            }
            alertController.addAction(addToCircleAction)
        } else {
            // Show which circles contain this place
            let viewDetailsAction = UIAlertAction(title: "View Details", style: .default) { [weak self] _ in
                if let existingPlace = self?.findExistingPlace(name: poiName, coordinate: coordinate) {
                    self?.delegate?.mapViewController(self!, didSelectPlace: existingPlace)
                    self?.dismiss(animated: true)
                }
            }
            alertController.addAction(viewDetailsAction)
        }
        
        // Cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
        }
        alertController.addAction(cancelAction)
        
        // For iPad
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = mapView
            let point = mapView.convert(coordinate, toPointTo: mapView)
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    @available(iOS 16.0, *)
    private func showCirclePickerForPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // First, load user's circles
        let loadingAlert = UIAlertController(title: "Loading", message: "Fetching your circles...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circles):
                        self?.presentCirclePicker(for: featureAnnotation, circles: circles)
                    case .failure(let error):
                        self?.showError("Failed to load circles: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func presentCirclePicker(for featureAnnotation: MKMapFeatureAnnotation, circles: [Circle]) {
        // Store the POI annotation for later use
        pendingPOIAnnotation = featureAnnotation
        
        // Sort circles alphabetically for easy finding
        let sortedCircles = circles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // Create and configure the vertical slider picker
        let circlePicker = CirclePickerSliderView()
        circlePicker.delegate = self
        circlePicker.configure(with: sortedCircles)
        
        // Store reference to dismiss later
        currentCirclePicker = circlePicker
        
        // Show the picker
        if let window = view.window {
            circlePicker.show(in: window)
        }
    }
    
    @available(iOS 16.0, *)
    private func addPOIToCircle(_ featureAnnotation: MKMapFeatureAnnotation, circle: Circle, notes: String? = nil) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Convert POI to Place
        AppleMapsService.shared.convertPOIToPlace(
            from: featureAnnotation,
            circleId: circle.id,
            notes: notes
        ) { [weak self] result in
            switch result {
            case .success(let place):
                // Add place to circle using PlaceService
                PlaceService.shared.addPlaceFromPOI(
                    name: place.name,
                    address: place.address,
                    location: place.location,
                    category: place.category,
                    website: place.website,
                    phone: place.phone,
                    description: place.description,
                    circleId: circle.id,
                    notes: place.notes,
                    googlePlaceId: place.googlePlaceId
                ) { addResult in
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            switch addResult {
                            case .success:
                                self?.showSuccess("Added to \(circle.name)")
                                self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
                                // Refresh map to show new place
                                self?.loadPlacesForCurrentView()
                            case .failure(let error):
                                self?.showError("Failed to add place: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showError("Failed to get place details: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func createNewCircleForPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Navigate to create circle view controller
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        
        // Store the POI annotation to add after circle creation
        self.pendingPOIAnnotation = featureAnnotation
        
        let navController = UINavigationController(rootViewController: createCircleVC)
        present(navController, animated: true)
    }
    
    private func showSuccess(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    
    // MARK: - Helper Methods for POI Duplicate Detection
    
    private func checkIfPOIAlreadyExists(name: String, coordinate: CLLocationCoordinate2D) -> Bool {
        // Check all places (including filtered and unfiltered)
        let allPlacesToCheck = viewMode == .allPlaces ? places : filteredPlaces
        
        // Check by name and proximity (within ~100 meters)
        for place in allPlacesToCheck {
            guard let placeLocation = place.location?.clLocation else { continue }
            
            // Check name similarity (case insensitive)
            let nameMatch = place.name.lowercased() == name.lowercased() ||
                           place.name.lowercased().contains(name.lowercased()) ||
                           name.lowercased().contains(place.name.lowercased())
            
            // Check location proximity (100 meters)
            let distance = placeLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let locationMatch = distance < 100 // 100 meters
            
            if nameMatch && locationMatch {
                return true
            }
        }
        
        return false
    }
    
    private func findExistingPlace(name: String, coordinate: CLLocationCoordinate2D) -> Place? {
        // Find the exact place that matches
        let allPlacesToCheck = viewMode == .allPlaces ? places : filteredPlaces
        
        for place in allPlacesToCheck {
            guard let placeLocation = place.location?.clLocation else { continue }
            
            let nameMatch = place.name.lowercased() == name.lowercased() ||
                           place.name.lowercased().contains(name.lowercased()) ||
                           name.lowercased().contains(place.name.lowercased())
            
            let distance = placeLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let locationMatch = distance < 100 // 100 meters
            
            if nameMatch && locationMatch {
                return place
            }
        }
        
        return nil
    }
    
    private func loadPlacesForCurrentView() {
        // Reload places based on current view mode
        if viewMode == .circle {
            addAnnotationsToMap()
        } else {
            // In allPlaces mode, reload from connections
            // This would need to be implemented based on your data source
        }
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
                UIAction(title: "My Connections", state: selectedConnectionId == "my_connections_only" ? .on : .off) { [weak self] _ in
                    self?.selectConnection("my_connections_only")
                },
                UIAction(title: "My Places Only", state: selectedConnectionId == "my_places_only" ? .on : .off) { [weak self] _ in
                    self?.selectConnection("my_places_only")
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
                if connectionId == "my_places_only" {
                    connectionSubtitle = "My Places Only"
                } else if connectionId == "my_connections_only" {
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
            if let connectionId = selectedConnectionId, connectionId != "my_places_only",
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
        if let connectionId = selectedConnectionId, connectionId != "my_places_only" {
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
        selectConnection(selectedConnectionId == "my_places_only" ? nil : "my_places_only")
    }

    private func updateMyPlacesChipAppearance() {
        guard isPresentedModally && showFilters && viewMode == .allPlaces else { return }
        let isActive = selectedConnectionId == "my_places_only"
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

        placesListTableView.isHidden = !isShowingPlacesList
        updatePlacesCount()
        userListView?.isHidden = isShowingPlacesList
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
        let sortedCircles = circles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let circlePickerVC = CirclePickerViewController(circles: sortedCircles)
        circlePickerVC.onCircleSelected = { [weak self] circle in
            self?.presentAddPlace(circleId: circle.id, circles: sortedCircles)
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

        distanceSortedPlaces = filteredPlaces.map { place in
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
        if connectionId == nil || connectionId == "my_places_only" || connectionId == "my_connections_only" {
            selectedConnectionUser = nil
        }
        // The origin sub-filter only makes sense under My Places
        if connectionId != "my_places_only" { selectedImportOrigin = nil }
        updateConnectionAvatarChip()
        updateMyPlacesChipAppearance()
        // The dropdown header narrates this selection too — every path that
        // changes the connection (Me chip, hamburger, dropdown) lands here,
        // so this one call keeps the label honest for all of them.
        updateFilterHeaderTitles()
        // Keep the avatar row's highlight ring in sync (also covers changes
        // made through the hamburger menu)
        userListView?.selectedUserId = (connectionId == nil || connectionId == "my_places_only" || connectionId == "my_connections_only") ? nil : connectionId
        // Let the presenter mirror the selection so it survives dismissal
        delegate?.mapViewController(self, didChangeConnectionFilter: connectionId)
        // A filter change is explicit user intent — allow zooming to results
        hasExplicitInitialRegion = false
        applyFilter()
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

        // If we have a pending POI annotation, navigate to AddPlaceViewController
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                // Dismiss the circle picker if it exists
                currentCirclePicker?.dismiss()
                currentCirclePicker = nil
                
                // Find the parent navigation controller
                if let navController = self.navigationController ?? self.presentingViewController as? UINavigationController ?? self.parent?.navigationController {
                    let addPlaceVC = AddPlaceViewController(circleId: circle.id)
                    navController.pushViewController(addPlaceVC, animated: true)
                    
                    // Configure with POI data after a brief delay to ensure view is loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addPlaceVC.configureWithPOI(pendingPOI)
                    }
                    
                    // Clear the pending POI
                    pendingPOIAnnotation = nil
                    pendingPOINotes = nil
                }
            }
        }
    }
}

// MARK: - CirclePickerSliderViewDelegate
extension FullScreenMapViewController: CirclePickerSliderViewDelegate {
    func circlePickerDidSelectCircle(_ circle: Circle, notes: String?) {
        // Navigate to AddPlaceViewController with the selected POI
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                // Dismiss the circle picker first
                currentCirclePicker?.dismiss()
                currentCirclePicker = nil
                
                // Find the parent navigation controller
                if let navController = self.navigationController ?? self.presentingViewController as? UINavigationController ?? self.parent?.navigationController {
                    let addPlaceVC = AddPlaceViewController(circleId: circle.id)
                    navController.pushViewController(addPlaceVC, animated: true)
                    
                    // Configure with POI data after a brief delay to ensure view is loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addPlaceVC.configureWithPOI(pendingPOI)
                    }
                    
                    // Clear the pending POI
                    pendingPOIAnnotation = nil
                    pendingPOINotes = nil
                }
            }
        }
    }
    
    func circlePickerDidSelectCreateNew(notes: String?) {
        // Create a new circle for the POI
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                // Store notes temporarily to use after circle creation
                pendingPOINotes = notes
                createNewCircleForPOI(pendingPOI)
            }
        }
    }
    
    func circlePickerDidCancel() {
        // Clear the circle picker reference
        currentCirclePicker = nil
        
        // Deselect the annotation
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                mapView.deselectAnnotation(pendingPOI, animated: true)
                pendingPOIAnnotation = nil
            }
        }
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
        if let selected = selectedConnectionId, selected != "my_places_only",
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
