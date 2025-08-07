import UIKit
import MapKit
import CoreLocation

protocol FullScreenMapViewControllerDelegate: AnyObject {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place)
}

enum MapViewMode {
    case circle
    case allPlaces
}


class FullScreenMapViewController: UIViewController, MKMapViewDelegate {
    
    // MARK: - Properties
    private var places: [Place]
    private var initialRegion: MKCoordinateRegion
    private var annotationPlaceMap: [ObjectIdentifier: Place] = [:]
    private var selectedCategory: UnifiedCategory?
    private var filteredPlaces: [Place] = []
    private var availableCategories: [UnifiedCategory] = []
    private var isDropdownOpen = false
    private var dropdownHeightConstraint: NSLayoutConstraint?
    private var connectionDropdownHeightConstraint: NSLayoutConstraint?
    private var isConnectionDropdownOpen = false
    private var selectedConnectionId: String?
    private var connections: [Connection] = []
    private var connectionPlaces: [String: [Place]] = [:] // connectionId -> places
    private let locationManager = CLLocationManager()
    private var pendingPOIAnnotation: Any? // MKMapFeatureAnnotation for iOS 16+
    private var pendingPOINotes: String? // Temporary storage for notes when creating new circle
    private var currentCirclePicker: CirclePickerSliderView? // Reference to current circle picker
    private var isAdjustingRegion = false // Prevent concurrent region adjustments
    private var hasInitiallyZoomed = false // Track if we've done the initial zoom
    
    weak var delegate: FullScreenMapViewControllerDelegate?
    var viewMode: MapViewMode = .circle
    var isPresentedModally: Bool = false
    var showFilters: Bool = true // Control whether to show category/connection filters
    
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
    
    private let categoryFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Categories", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Add dropdown arrow
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let arrowImage = UIImage(systemName: "chevron.down", withConfiguration: config)
        button.setImage(arrowImage, for: .normal)
        button.tintColor = .white
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        
        return button
    }()
    
    private let connectionFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Connections", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Add dropdown arrow
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let arrowImage = UIImage(systemName: "chevron.down", withConfiguration: config)
        button.setImage(arrowImage, for: .normal)
        button.tintColor = .white
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        
        return button
    }()
    
    private let dropdownContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        return view
    }()
    
    private let categoryTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 44
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.layer.cornerRadius = 16
        tableView.clipsToBounds = true
        return tableView
    }()
    
    private let connectionDropdownContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        return view
    }()
    
    private let connectionTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 44
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.layer.cornerRadius = 16
        tableView.clipsToBounds = true
        return tableView
    }()
    
    // MARK: - Init
    init(places: [Place] = [], initialRegion: MKCoordinateRegion? = nil, selectedCategory: UnifiedCategory? = nil, selectedConnectionId: String? = nil) {
        self.places = places
        self.selectedCategory = selectedCategory
        self.selectedConnectionId = selectedConnectionId
        self.filteredPlaces = places
        
        // Calculate initial region
        if let region = initialRegion {
            self.initialRegion = region
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
    func updatePlaces(_ newPlaces: [Place]) {
        // Don't update if we're going from empty to empty (still loading)
        if self.places.isEmpty && newPlaces.isEmpty {
            // Keep showing "Loading..." - don't update
            return
        }
        
        self.places = newPlaces
        updateAvailableCategories()
        // Apply existing filters to the new places
        applyFilter()
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
        
        // Reload connection table if visible
        if viewMode == .allPlaces {
            connectionTableView.reloadData()
            updateConnectionFilterButtonTitle()
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
        updateFilterButtonTitle()
        updateConnectionFilterButtonTitle()
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
        
        // Add category filter button only if presented modally and filters are enabled
        if isPresentedModally && showFilters {
            view.addSubview(categoryFilterButton)
            categoryFilterButton.addTarget(self, action: #selector(categoryFilterButtonTapped), for: .touchUpInside)
            
            // Add dropdown containers
            view.addSubview(dropdownContainer)
            dropdownContainer.addSubview(categoryTableView)
            
            // Add connection filter for allPlaces mode
            if viewMode == .allPlaces {
                view.addSubview(connectionFilterButton)
                connectionFilterButton.addTarget(self, action: #selector(connectionFilterButtonTapped), for: .touchUpInside)
                
                view.addSubview(connectionDropdownContainer)
                connectionDropdownContainer.addSubview(connectionTableView)
            }
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
        
        // Add category filter constraints only if presented modally and filters are enabled
        if isPresentedModally && showFilters {
            if viewMode == .allPlaces {
                // When showing both filters, position them side by side
                NSLayoutConstraint.activate([
                    // Connection filter button - left side with spacing
                    connectionFilterButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -8),
                    connectionFilterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                    connectionFilterButton.heightAnchor.constraint(equalToConstant: 32),
                    connectionFilterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
                    
                    // Category filter button - right side with spacing
                    categoryFilterButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 8),
                    categoryFilterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                    categoryFilterButton.heightAnchor.constraint(equalToConstant: 32),
                    categoryFilterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
                    
                    // Connection dropdown container
                    connectionDropdownContainer.centerXAnchor.constraint(equalTo: connectionFilterButton.centerXAnchor),
                    connectionDropdownContainer.topAnchor.constraint(equalTo: connectionFilterButton.bottomAnchor, constant: 8),
                    connectionDropdownContainer.widthAnchor.constraint(equalToConstant: 200),
                    
                    // Connection table view inside dropdown
                    connectionTableView.topAnchor.constraint(equalTo: connectionDropdownContainer.topAnchor),
                    connectionTableView.leadingAnchor.constraint(equalTo: connectionDropdownContainer.leadingAnchor),
                    connectionTableView.trailingAnchor.constraint(equalTo: connectionDropdownContainer.trailingAnchor),
                    connectionTableView.bottomAnchor.constraint(equalTo: connectionDropdownContainer.bottomAnchor),
                    
                    // Category dropdown container
                    dropdownContainer.centerXAnchor.constraint(equalTo: categoryFilterButton.centerXAnchor),
                    dropdownContainer.topAnchor.constraint(equalTo: categoryFilterButton.bottomAnchor, constant: 8),
                    dropdownContainer.widthAnchor.constraint(equalToConstant: 200),
                    
                    // Category table view inside dropdown
                    categoryTableView.topAnchor.constraint(equalTo: dropdownContainer.topAnchor),
                    categoryTableView.leadingAnchor.constraint(equalTo: dropdownContainer.leadingAnchor),
                    categoryTableView.trailingAnchor.constraint(equalTo: dropdownContainer.trailingAnchor),
                    categoryTableView.bottomAnchor.constraint(equalTo: dropdownContainer.bottomAnchor)
                ])
                
                // Create height constraint for connection dropdown
                connectionDropdownHeightConstraint = connectionDropdownContainer.heightAnchor.constraint(equalToConstant: 0)
                connectionDropdownHeightConstraint?.isActive = true
            } else {
                // Circle mode - only category filter centered
                NSLayoutConstraint.activate([
                    // Category filter button - center top
                    categoryFilterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    categoryFilterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                    categoryFilterButton.heightAnchor.constraint(equalToConstant: 32),
                    
                    // Dropdown container
                    dropdownContainer.centerXAnchor.constraint(equalTo: categoryFilterButton.centerXAnchor),
                    dropdownContainer.topAnchor.constraint(equalTo: categoryFilterButton.bottomAnchor, constant: 8),
                    dropdownContainer.widthAnchor.constraint(equalToConstant: 200),
                    
                    // Category table view inside dropdown
                    categoryTableView.topAnchor.constraint(equalTo: dropdownContainer.topAnchor),
                    categoryTableView.leadingAnchor.constraint(equalTo: dropdownContainer.leadingAnchor),
                    categoryTableView.trailingAnchor.constraint(equalTo: dropdownContainer.trailingAnchor),
                    categoryTableView.bottomAnchor.constraint(equalTo: dropdownContainer.bottomAnchor)
                ])
            }
            
            // Create height constraint for dropdown
            dropdownHeightConstraint = dropdownContainer.heightAnchor.constraint(equalToConstant: 0)
            dropdownHeightConstraint?.isActive = true
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
        
        if let location = locationManager.location {
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
        categoryTableView.delegate = self
        categoryTableView.dataSource = self
        categoryTableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        
        if viewMode == .allPlaces {
            connectionTableView.delegate = self
            connectionTableView.dataSource = self
            connectionTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ConnectionCell")
        }
    }
    
    // MARK: - Map Annotations
    private func addAnnotationsToMap() {
        // Clear existing annotations
        mapView.removeAnnotations(mapView.annotations)
        annotationPlaceMap.removeAll()
        
        var mapRect = MKMapRect.null
        var placesWithLocation = 0
        var placesWithoutLocation = 0
        
        // Add annotations for each place
        for place in filteredPlaces {
            guard let location = place.location?.clLocation else { 
                placesWithoutLocation += 1
                print("⚠️ Skipping place without location: '\(place.name)' (id: \(place.id))")
                continue 
            }
            
            placesWithLocation += 1
            let annotation = PlaceAnnotation(place: place)
            mapView.addAnnotation(annotation)
            
            // Store the place reference using ObjectIdentifier
            annotationPlaceMap[ObjectIdentifier(annotation)] = place
            
            // Update map rect
            let point = MKMapPoint(location.coordinate)
            let rect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            mapRect = mapRect.union(rect)
        }
        
        // Log summary
        print("📍 Map Update Summary:")
        print("   Total filtered places: \(filteredPlaces.count)")
        print("   Places with location: \(placesWithLocation)")
        print("   Places without location: \(placesWithoutLocation)")
        
        // Adjust region based on user location and places
        adjustMapRegion()
    }
    
    private func adjustMapRegion() {
        // Prevent concurrent adjustments
        guard !isAdjustingRegion else { return }
        isAdjustingRegion = true
        
        // Get user location
        let userLocation = locationManager.location ?? mapView.userLocation.location
        
        if let userLocation = userLocation {
            // Start with 25 mile radius (40233.6 meters)
            let initialRadius: CLLocationDistance = 40233.6
            
            // Count places within initial radius
            let placesWithinRadius = filteredPlaces.filter { place in
                guard let placeLocation = place.location?.clLocation else { return false }
                return userLocation.distance(from: placeLocation) <= initialRadius
            }
            
            if placesWithinRadius.count >= 10 || filteredPlaces.count <= 10 {
                // Show 25 mile radius or all places if less than 10 total
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: initialRadius * 2,
                    longitudinalMeters: initialRadius * 2
                )
                mapView.setRegion(region, animated: !hasInitiallyZoomed)
                hasInitiallyZoomed = true
            } else {
                // Expand radius to show at least 10 closest places
                let sortedPlaces = filteredPlaces
                    .compactMap { place -> (place: Place, distance: CLLocationDistance)? in
                        guard let placeLocation = place.location?.clLocation else { return nil }
                        return (place, userLocation.distance(from: placeLocation))
                    }
                    .sorted { $0.distance < $1.distance }
                
                // Get the 10th closest place (or last if less than 10)
                let targetIndex = min(9, sortedPlaces.count - 1)
                if targetIndex >= 0 {
                    let requiredRadius = sortedPlaces[targetIndex].distance * 1.2 // Add 20% padding
                    
                    let region = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        latitudinalMeters: requiredRadius * 2,
                        longitudinalMeters: requiredRadius * 2
                    )
                    mapView.setRegion(region, animated: !hasInitiallyZoomed)
                    hasInitiallyZoomed = true
                }
            }
        } else if filteredPlaces.count > 0 {
            // No user location - show all places
            var coordinates: [CLLocationCoordinate2D] = []
            for place in filteredPlaces {
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
        
        // Reset the flag after a delay to allow the animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAdjustingRegion = false
        }
    }
    
    // MARK: - MKMapViewDelegate
    
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
            detailButton.tag = 999 // Tag to identify it
            detailButton.addTarget(self, action: #selector(detailButtonTapped(_:)), for: .touchUpInside)
            annotationView?.rightCalloutAccessoryView = detailButton
            
            // Ensure the annotation view is interactive
            annotationView?.isEnabled = true
            annotationView?.isUserInteractionEnabled = true
        } else {
            annotationView?.annotation = annotation
            // Ensure button is still there and interactive
            if let button = annotationView?.rightCalloutAccessoryView as? UIButton, button.tag != 999 {
                let detailButton = UIButton(type: .detailDisclosure)
                detailButton.tag = 999
                detailButton.addTarget(self, action: #selector(detailButtonTapped(_:)), for: .touchUpInside)
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
        print("🔵 Info button tapped!")
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { 
            print("❌ Failed to cast annotation to PlaceAnnotation")
            return 
        }
        
        print("✅ Place: \(placeAnnotation.place.name)")
        print("📱 Delegate exists: \(delegate != nil)")
        
        // Notify delegate
        if let delegate = delegate {
            print("🎯 Calling delegate.mapViewController")
            delegate.mapViewController(self, didSelectPlace: placeAnnotation.place)
        } else {
            print("⚠️ No delegate set!")
        }
        
        // Dismiss if not in allPlaces mode
        if viewMode != .allPlaces {
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
    
    @objc private func detailButtonTapped(_ sender: UIButton) {
        print("🔵 Detail button tapped via target-action!")
        
        // Find the annotation view that contains this button
        var view: UIView? = sender
        while view != nil && !(view is MKAnnotationView) {
            view = view?.superview
        }
        
        guard let annotationView = view as? MKAnnotationView,
              let placeAnnotation = annotationView.annotation as? PlaceAnnotation else {
            print("❌ Could not find annotation view or place annotation")
            return
        }
        
        print("✅ Place: \(placeAnnotation.place.name)")
        print("📱 Delegate exists: \(delegate != nil)")
        
        // Notify delegate
        if let delegate = delegate {
            print("🎯 Calling delegate.mapViewController")
            delegate.mapViewController(self, didSelectPlace: placeAnnotation.place)
        } else {
            print("⚠️ No delegate set!")
        }
        
        // Dismiss if not in allPlaces mode
        if viewMode != .allPlaces {
            dismiss(animated: true)
        }
    }
    
    @objc private func categoryFilterButtonTapped() {
        toggleDropdown()
    }
    
    @objc private func connectionFilterButtonTapped() {
        toggleConnectionDropdown()
    }
    
    private func toggleDropdown() {
        isDropdownOpen.toggle()
        
        // Close connection dropdown if open
        if isDropdownOpen && isConnectionDropdownOpen {
            isConnectionDropdownOpen = false
            hideConnectionDropdown()
        }
        
        if isDropdownOpen {
            showDropdown()
        } else {
            hideDropdown()
        }
    }
    
    private func toggleConnectionDropdown() {
        isConnectionDropdownOpen.toggle()
        
        // Close category dropdown if open
        if isConnectionDropdownOpen && isDropdownOpen {
            isDropdownOpen = false
            hideDropdown()
        }
        
        if isConnectionDropdownOpen {
            showConnectionDropdown()
        } else {
            hideConnectionDropdown()
        }
    }
    
    private func showDropdown() {
        // Calculate dropdown height based on number of categories
        let categories = PlaceCategory.allCases
        let dropdownHeight = min(CGFloat(categories.count + 1) * 44, 300) // +1 for "All Categories"
        
        dropdownHeightConstraint?.constant = dropdownHeight
        dropdownContainer.isHidden = false
        
        UIView.animate(withDuration: 0.3) {
            self.dropdownContainer.alpha = 1
            self.view.layoutIfNeeded()
        }
        
        // Rotate arrow
        UIView.animate(withDuration: 0.3) {
            self.categoryFilterButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
    }
    
    private func hideDropdown() {
        UIView.animate(withDuration: 0.3, animations: {
            self.dropdownContainer.alpha = 0
            self.dropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.dropdownContainer.isHidden = true
        }
        
        // Rotate arrow back
        UIView.animate(withDuration: 0.3) {
            self.categoryFilterButton.imageView?.transform = .identity
        }
    }
    
    private func showConnectionDropdown() {
        // Calculate dropdown height based on number of connections
        let dropdownHeight = min(CGFloat(connections.count + 2) * 44, 300) // +2 for "All Connections" and "My Places Only"
        
        connectionDropdownHeightConstraint?.constant = dropdownHeight
        connectionDropdownContainer.isHidden = false
        
        UIView.animate(withDuration: 0.3) {
            self.connectionDropdownContainer.alpha = 1
            self.view.layoutIfNeeded()
        }
        
        // Rotate arrow
        UIView.animate(withDuration: 0.3) {
            self.connectionFilterButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
    }
    
    private func hideConnectionDropdown() {
        UIView.animate(withDuration: 0.3, animations: {
            self.connectionDropdownContainer.alpha = 0
            self.connectionDropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.connectionDropdownContainer.isHidden = true
        }
        
        // Rotate arrow back
        UIView.animate(withDuration: 0.3) {
            self.connectionFilterButton.imageView?.transform = .identity
        }
    }
    
    private func selectCategory(_ category: UnifiedCategory?) {
        selectedCategory = category
        updateFilterButtonTitle()
        applyFilter()
        hideDropdown()
    }
    
    private func selectConnection(_ connectionId: String?) {
        print("🔍 FullScreenMap: selectConnection called with: \(connectionId ?? "nil")")
        selectedConnectionId = connectionId
        updateConnectionFilterButtonTitle()
        applyFilter()
        hideConnectionDropdown()
    }
    
    private func updateFilterButtonTitle() {
        if let category = selectedCategory {
            categoryFilterButton.setTitle(category.displayName, for: .normal)
        } else {
            categoryFilterButton.setTitle("All Categories", for: .normal)
        }
    }
    
    private func updateConnectionFilterButtonTitle() {
        print("🔍 FullScreenMap: updateConnectionFilterButtonTitle called")
        print("  selectedConnectionId: \(selectedConnectionId ?? "nil")")
        
        if let connectionId = selectedConnectionId {
            if connectionId == "my_places_only" {
                connectionFilterButton.setTitle("My Places Only", for: .normal)
            } else {
                // Find the connection where the other user's ID matches
                let currentUserId = AuthService.shared.getUserId() ?? ""
                if let connection = connections.first(where: { conn in
                    conn.otherUserId(currentUserId: currentUserId) == connectionId
                }) {
                    let userName = connection.connectedUser?.displayName ?? "Unknown"
                    print("  Found connection: \(userName) for ID: \(connectionId)")
                    connectionFilterButton.setTitle(userName, for: .normal)
                } else {
                    print("  WARNING: No connection found for ID: \(connectionId)")
                    print("  Available connections:")
                    for conn in connections {
                        let otherUserId = conn.otherUserId(currentUserId: currentUserId)
                        print("    - \(conn.connectedUser?.displayName ?? "Unknown") (otherUserId: \(otherUserId))")
                    }
                    connectionFilterButton.setTitle("Unknown", for: .normal)
                }
            }
        } else {
            connectionFilterButton.setTitle("All Connections", for: .normal)
        }
    }
    
    private func applyFilter() {
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
        
        // Apply category filter
        filteredPlaces = placesToFilter.filtered(by: selectedCategory)
        print("  Final filtered places: \(filteredPlaces.count)")
        
        updatePlacesCount()
        addAnnotationsToMap()
    }
    
    private func updateAvailableCategories() {
        // Use centralized utility to get unique categories
        availableCategories = PlaceCategory.uniqueCategories(from: places)
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
        if tableView == categoryTableView {
            return availableCategories.count + 1 // +1 for "All Categories"
        } else if tableView == connectionTableView {
            return connections.count + 2 // +2 for "All Connections" and "My Places Only"
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == categoryTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
            
            if indexPath.row == 0 {
                cell.textLabel?.text = "All Categories"
                cell.textLabel?.textColor = selectedCategory == nil ? .systemBlue : .white
            } else {
                let category = availableCategories[indexPath.row - 1]
                cell.textLabel?.text = category.displayName
                cell.textLabel?.textColor = selectedCategory == category ? .systemBlue : .white
            }
            
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            
            return cell
        } else if tableView == connectionTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ConnectionCell", for: indexPath)
            
            if indexPath.row == 0 {
                cell.textLabel?.text = "All Connections"
                cell.textLabel?.textColor = selectedConnectionId == nil ? .systemBlue : .white
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "My Places Only"
                cell.textLabel?.textColor = selectedConnectionId == "my_places_only" ? .systemBlue : .white
            } else {
                let connection = connections[indexPath.row - 2]
                let userName = connection.connectedUser?.displayName ?? "Unknown"
                cell.textLabel?.text = userName
                // Compare with the other user's ID
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let otherUserId = connection.otherUserId(currentUserId: currentUserId)
                cell.textLabel?.textColor = selectedConnectionId == otherUserId ? .systemBlue : .white
            }
            
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            
            return cell
        }
        
        return UITableViewCell()
    }
}

// MARK: - UITableViewDelegate
extension FullScreenMapViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == categoryTableView {
            if indexPath.row == 0 {
                selectCategory(nil)
            } else {
                selectCategory(availableCategories[indexPath.row - 1])
            }
        } else if tableView == connectionTableView {
            if indexPath.row == 0 {
                selectConnection(nil) // All connections
            } else if indexPath.row == 1 {
                selectConnection("my_places_only") // My places only
            } else {
                let connection = connections[indexPath.row - 2]
                // Use the other user's ID (not the current user's ID)
                let currentUserId = AuthService.shared.getUserId() ?? ""
                let otherUserId = connection.otherUserId(currentUserId: currentUserId)
                selectConnection(otherUserId)
            }
        }
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

