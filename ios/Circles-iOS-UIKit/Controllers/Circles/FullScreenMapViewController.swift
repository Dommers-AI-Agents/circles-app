import UIKit
import MapKit
import CoreLocation

protocol FullScreenMapViewControllerDelegate: AnyObject {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place)
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion)
}

// Default no-op so existing conformers don't need to handle region changes
extension FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion) {}
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
    private var connections: [Connection] = []
    private var connectionPlaces: [String: [Place]] = [:] // connectionId -> places
    private let locationManager = CLLocationManager()
    private var pendingPOIAnnotation: Any? // MKMapFeatureAnnotation for iOS 16+
    private var pendingPOINotes: String? // Temporary storage for notes when creating new circle
    private var currentCirclePicker: CirclePickerSliderView? // Reference to current circle picker
    private var isAdjustingRegion = false // Prevent concurrent region adjustments
    private var hasInitiallyZoomed = false // Track if we've done the initial zoom
    private var hasExplicitInitialRegion = false // Caller provided a region to open at
    private var viewportFetchTimer: Timer? // Debounce for viewport (region-change) notifications
    
    weak var delegate: FullScreenMapViewControllerDelegate?
    var viewMode: MapViewMode = .circle
    var isPresentedModally: Bool = false
    var showFilters: Bool = true // Control whether to show category/connection filters
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

    private let overlayChipStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

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
    func setConnectionFilterContext(_ connectionId: String?) {
        selectedConnectionId = connectionId
    }

    func updatePlaces(_ newPlaces: [Place], adjustRegion: Bool = true) {
        // Don't update if we're going from empty to empty (still loading)
        if self.places.isEmpty && newPlaces.isEmpty {
            // Keep showing "Loading..." - don't update
            return
        }

        self.places = newPlaces
        updateAvailableCategories()
        // Apply existing filters to the new places
        applyFilter(adjustRegion: adjustRegion)
        // adjustMapRegion is already called in addAnnotationsToMap, no need to call it again

        // Show place count when places are loaded
        showPlaceCount()
    }
    
    func hidePlaceCount() {
        placesCountLabel.isHidden = true
    }
    
    func showPlaceCount() {
        placesCountLabel.isHidden = false
    }
    
    func updatePlacesWithConnections(_ userPlaces: [Place], connections: [Connection], connectionPlaces: [String: [Place]]) {
        // Debug logging
        print("🔍 FullScreenMap: updatePlacesWithConnections called")
        print("🔍 Connections count: \(connections.count)")
        for (index, connection) in connections.enumerated() {
            print("  \(index): \(connection.connectedUser?.displayName ?? "Unknown") - ID: \(connection.connectedUserId)")
        }
        print("🔍 Connection places map keys: \(connectionPlaces.keys.sorted())")
        
        // Combine all places
        var allPlaces = userPlaces
        for (userId, places) in connectionPlaces {
            print("  User \(userId) has \(places.count) places")
            allPlaces.append(contentsOf: places)
        }
        
        self.places = allPlaces
        // Sort connections alphabetically by display name for consistent ordering
        self.connections = connections.sorted { 
            ($0.connectedUser?.displayName ?? "").localizedCaseInsensitiveCompare($1.connectedUser?.displayName ?? "") == .orderedAscending
        }
        self.connectionPlaces = connectionPlaces
        
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
        setupUI()
        setupMap()
        setupTableView()
        updateAvailableCategories()
        applyFilter()
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
            overlayChipStack.addArrangedSubview(menuChipButton)
            if viewMode == .allPlaces {
                overlayChipStack.addArrangedSubview(myPlacesChipButton)
            }
            overlayChipStack.addArrangedSubview(listChipButton)

            // List added before the chips so the chips stay tappable above it
            view.addSubview(placesListTableView)
            view.addSubview(overlayChipStack)
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
        
        // Add close button constraints only if presented modally
        if isPresentedModally {
            constraints.append(contentsOf: [
                closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 44),
                closeButton.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        // Overlay chip + list constraints, only if presented modally with filters
        if isPresentedModally && showFilters {
            NSLayoutConstraint.activate([
                overlayChipStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                overlayChipStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                overlayChipStack.heightAnchor.constraint(equalToConstant: 36),
                menuChipButton.widthAnchor.constraint(equalToConstant: 36),
                listChipButton.widthAnchor.constraint(equalToConstant: 36),

                // Places list fills the map area below the chips
                placesListTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
                placesListTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                placesListTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                placesListTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            if viewMode == .allPlaces {
                myPlacesChipButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
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
        print("🗺️ Map delegate set. View mode: \(viewMode)")
        
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
        print("🗺️ [SmoothMap] Starting smooth annotation update...")
        
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
        
        print("🗺️ [SmoothMap] Differential update:")
        print("   Current: \(currentAnnotations.count) annotations")
        print("   To add: \(placesToAdd.count) places")
        print("   To remove: \(annotationsToRemove.count) annotations")
        
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
        }
        
        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("🗺️ [SmoothMap] Update completed in \(String(format: "%.3f", loadTime))s")
    }
    
    private func addAnnotationsBatched(_ places: [Place], adjustRegion: Bool = true) {
        let batchSize = 15 // Optimal batch size for smooth animation
        let batches = places.chunked(into: batchSize)

        print("🗺️ [SmoothMap] Adding \(places.count) annotations in \(batches.count) batches")

        var batchIndex = 0
        var addedCount = 0

        func addNextBatch() {
            guard batchIndex < batches.count else {
                // All batches processed - adjust map region
                print("🗺️ [SmoothMap] All batches loaded (\(addedCount) annotations)")
                if adjustRegion {
                    DispatchQueue.main.async { [weak self] in
                        self?.adjustMapRegion()
                    }
                }
                return
            }
            
            let batch = batches[batchIndex]
            let batchAnnotations = batch.compactMap { place -> PlaceAnnotation? in
                guard place.location?.clLocation != nil else {
                    print("⚠️ Skipping place without location: '\(place.name)'")
                    return nil
                }
                return PlaceAnnotation(place: place)
            }
            
            // Add batch to map with smooth animation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Store place references
                for annotation in batchAnnotations {
                    if let place = batch.first(where: { $0.id == annotation.place.id }) {
                        self.annotationPlaceMap[ObjectIdentifier(annotation)] = place
                    }
                }
                
                // Add to map - MapKit will animate automatically
                self.mapView.addAnnotations(batchAnnotations)
                addedCount += batchAnnotations.count
                
                print("🗺️ [SmoothMap] Batch \(batchIndex + 1)/\(batches.count): +\(batchAnnotations.count) annotations")
                
                batchIndex += 1
                
                // Schedule next batch with small delay for smooth visual progression
                if batchIndex < batches.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        addNextBatch()
                    }
                } else {
                    // Final batch - adjust region
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addNextBatch() // This will trigger adjustMapRegion
                    }
                }
            }
        }
        
        // Start batch processing
        addNextBatch()
    }
    
    // MARK: - Helper Extensions
    
    func adjustMapRegion() {
        // Honor an explicitly provided opening region (e.g. expanding the
        // embedded map) — cleared when the user changes a filter in here
        guard !hasExplicitInitialRegion else {
            print("📍 adjustMapRegion: Skipping - honoring explicit initial region")
            return
        }

        // Prevent concurrent adjustments
        guard !isAdjustingRegion else {
            print("📍 adjustMapRegion: Skipping - already adjusting")
            return
        }
        isAdjustingRegion = true
        
        print("📍 adjustMapRegion called:")
        print("  - selectedConnectionId: \(selectedConnectionId ?? "nil")")
        print("  - selectedCategory: \(selectedCategory?.displayName ?? "nil")")
        print("  - filteredPlaces.count: \(filteredPlaces.count)")
        print("  - hasInitiallyZoomed: \(hasInitiallyZoomed)")
        
        // If a specific connection is selected, always zoom to show their places
        let shouldZoomToFilteredPlaces = (selectedConnectionId != nil && selectedConnectionId != "my_places_only") || 
                                        selectedCategory != nil
        
        print("  - shouldZoomToFilteredPlaces: \(shouldZoomToFilteredPlaces)")
        
        if shouldZoomToFilteredPlaces && filteredPlaces.count > 0 {
            // Keep the current camera when the new selection already has places
            // on screen — tapping through connections shouldn't change the zoom
            // level unless the selected connection has nothing in view.
            if hasInitiallyZoomed {
                let visibleRect = mapView.visibleMapRect
                let hasPlacesInView = filteredPlaces.contains { place in
                    guard let location = place.location?.clLocation else { return false }
                    return visibleRect.contains(MKMapPoint(location.coordinate))
                }
                if hasPlacesInView {
                    print("  - Keeping current region: selection has places in view")
                    isAdjustingRegion = false
                    return
                }
            }

            // Zoom to show all filtered places
            var coordinates: [CLLocationCoordinate2D] = []
            for place in filteredPlaces {
                if let location = place.location?.clLocation {
                    coordinates.append(location.coordinate)
                }
            }
            
            print("  - Coordinates for zoom: \(coordinates.count)")
            
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
                
                // Add padding to the span, clamped to MapKit's valid limits so a
                // connection with places spread across the world still frames all
                // of them instead of setRegion silently rejecting the region
                let latDelta = min(max((maxLat - minLat) * 1.3, 0.01), 180)
                let lonDelta = min(max((maxLon - minLon) * 1.3, 0.01), 360)
                
                let span = MKCoordinateSpan(
                    latitudeDelta: latDelta,
                    longitudeDelta: lonDelta
                )
                
                print("  - Setting region to center: \(center), span: \(span)")
                
                let region = MKCoordinateRegion(center: center, span: span)
                mapView.setRegion(region, animated: true)
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

                print("  - Default region: \(focusPlaces.count) focus places (\(ownPlaces.count) own), radius \(Int(radius))m")

                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: radius * 2,
                    longitudinalMeters: radius * 2
                )
                mapView.setRegion(region, animated: !hasInitiallyZoomed)
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
                    hasInitiallyZoomed = true
                }
            }
        }
        
        // Reset the flag after a delay to allow the animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAdjustingRegion = false
        }
    }
    
    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Notify the delegate (debounced) so it can load places for the new viewport.
        // Fires for programmatic zooms too — that's how the initial viewport load happens.
        guard viewMode == .allPlaces else { return }

        viewportFetchTimer?.invalidate()
        viewportFetchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.mapViewController(self, regionDidChangeTo: self.mapView.region)
        }
    }

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
        }

        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        let timestamp = Date().timeIntervalSince1970
        print("🔵 [DEBUG-\(timestamp)] Info button tapped!")
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { 
            print("❌ [DEBUG-\(timestamp)] Failed to cast annotation to PlaceAnnotation")
            return 
        }
        
        print("✅ [DEBUG-\(timestamp)] Place: \(placeAnnotation.place.name)")
        print("📱 [DEBUG-\(timestamp)] Delegate exists: \(delegate != nil)")
        print("🗺️ [DEBUG-\(timestamp)] View mode: \(viewMode)")
        print("📍 [DEBUG-\(timestamp)] isPresentedModally: \(isPresentedModally)")
        
        // Notify delegate
        if let delegate = delegate {
            print("🎯 [DEBUG-\(timestamp)] Calling delegate.mapViewController for place: \(placeAnnotation.place.name)")
            delegate.mapViewController(self, didSelectPlace: placeAnnotation.place)
            print("🎯 [DEBUG-\(timestamp)] Delegate call completed")
        } else {
            print("⚠️ [DEBUG-\(timestamp)] No delegate set!")
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
            print("📍 Selected place annotation: \(placeAnnotation.place.name)")
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

        // Connection filter submenu (allPlaces mode only)
        if viewMode == .allPlaces {
            var connectionActions: [UIAction] = [
                UIAction(title: "All Connections", state: selectedConnectionId == nil ? .on : .off) { [weak self] _ in
                    self?.selectConnection(nil)
                },
                UIAction(title: "My Places Only", state: selectedConnectionId == "my_places_only" ? .on : .off) { [weak self] _ in
                    self?.selectConnection("my_places_only")
                }
            ]
            for connection in connections {
                let otherUserId = connection.otherUserId(currentUserId: currentUserId)
                connectionActions.append(
                    UIAction(
                        title: connection.connectedUser?.displayName ?? "Unknown",
                        state: selectedConnectionId == otherUserId ? .on : .off
                    ) { [weak self] _ in
                        self?.selectConnection(otherUserId)
                    }
                )
            }

            let connectionSubtitle: String
            if let connectionId = selectedConnectionId {
                if connectionId == "my_places_only" {
                    connectionSubtitle = "My Places Only"
                } else {
                    connectionSubtitle = connections
                        .first(where: { $0.otherUserId(currentUserId: currentUserId) == connectionId })?
                        .connectedUser?.displayName ?? "Connection"
                }
            } else {
                connectionSubtitle = "All Connections"
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

        // View Profile: the filtered connection's profile, or the user's own
        if viewMode == .allPlaces {
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
        let profileVC = ProfileViewController()
        // Without a configured user, ProfileViewController shows the current user's own profile
        if let connectionId = selectedConnectionId, connectionId != "my_places_only" {
            let currentUserId = AuthService.shared.getUserId() ?? ""
            if let user = connections.first(where: { $0.otherUserId(currentUserId: currentUserId) == connectionId })?.connectedUser {
                profileVC.configureWith(user: user)
            }
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
        placesCountLabel.isHidden = isShowingPlacesList || filteredPlaces.isEmpty
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
        print("🔍 FullScreenMap: selectConnection called with: \(connectionId ?? "nil")")
        selectedConnectionId = connectionId
        updateMyPlacesChipAppearance()
        // A filter change is explicit user intent — allow zooming to results
        hasExplicitInitialRegion = false
        applyFilter()
    }
    
    private func applyFilter(adjustRegion: Bool = true) {
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        print("🔍 FullScreenMap: applyFilter called")
        print("  selectedConnectionId: \(selectedConnectionId ?? "nil")")
        print("  viewMode: \(viewMode)")
        print("  Total places: \(places.count)")
        
        // Start with all places or connection-specific places
        var placesToFilter = places
        
        // Apply connection filter for allPlaces mode
        if viewMode == .allPlaces {
            if let connectionId = selectedConnectionId {
                if connectionId == "my_places_only" {
                    // Filter to show only user's places
                    placesToFilter = places.filter { $0.addedBy == currentUserId }
                    print("  Filtered to user's places: \(placesToFilter.count)")
                } else if let connPlaces = connectionPlaces[connectionId] {
                    // Use connection-specific places
                    placesToFilter = connPlaces
                    print("  Using connection places for \(connectionId): \(placesToFilter.count) places")
                } else {
                    print("  WARNING: No places found for connectionId: \(connectionId)")
                    print("  Available connectionPlaces keys: \(connectionPlaces.keys.sorted())")
                }
                // If nil (All Connections), use all places
            }
        }
        
        // Update available categories based on connection-filtered places
        updateAvailableCategories(from: placesToFilter)
        
        // Apply category filter
        filteredPlaces = placesToFilter.filtered(by: selectedCategory)
        print("  Final filtered places: \(filteredPlaces.count)")
        
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
        let totalPlaces = filteredPlaces.count
        let placesWithLocation = filteredPlaces.filter { $0.location?.clLocation != nil }.count
        let placesWithoutLocation = totalPlaces - placesWithLocation
        
        // Don't show "0 places" during initial loading
        if totalPlaces == 0 && placesCountLabel.text == "Loading..." {
            // Keep showing Loading...
            return
        }
        
        // Just show the count number in the circular badge
        placesCountLabel.text = "\(totalPlaces)"
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

