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
    private var selectedCategory: PlaceCategory?
    private var filteredPlaces: [Place] = []
    private var isDropdownOpen = false
    private var dropdownHeightConstraint: NSLayoutConstraint?
    private var connectionDropdownHeightConstraint: NSLayoutConstraint?
    private var isConnectionDropdownOpen = false
    private var selectedConnectionId: String?
    private var connections: [Connection] = []
    private var connectionPlaces: [String: [Place]] = [:] // connectionId -> places
    private let locationManager = CLLocationManager()
    
    weak var delegate: FullScreenMapViewControllerDelegate?
    var viewMode: MapViewMode = .circle
    
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
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 16
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
    init(places: [Place] = [], initialRegion: MKCoordinateRegion? = nil, selectedCategory: PlaceCategory? = nil) {
        self.places = places
        self.selectedCategory = selectedCategory
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
        self.places = newPlaces
        self.filteredPlaces = newPlaces
        updatePlacesCount()
        addAnnotationsToMap()
    }
    
    func updatePlacesWithConnections(_ userPlaces: [Place], connections: [Connection], connectionPlaces: [String: [Place]]) {
        // Combine all places
        var allPlaces = userPlaces
        for (_, places) in connectionPlaces {
            allPlaces.append(contentsOf: places)
        }
        
        self.places = allPlaces
        self.connections = connections
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
        updateFilterButtonTitle()
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
        
        // Add close button
        view.addSubview(closeButton)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        // Hide close button if in allPlaces mode
        if viewMode == .allPlaces {
            closeButton.isHidden = true
        }
        
        // Add places count label
        view.addSubview(placesCountLabel)
        placesCountLabel.text = "\(places.count) places"
        
        // Only add category filter button if NOT in allPlaces mode (to avoid redundancy)
        if viewMode != .allPlaces {
            view.addSubview(categoryFilterButton)
            categoryFilterButton.addTarget(self, action: #selector(categoryFilterButtonTapped), for: .touchUpInside)
        }
        
        // Add dropdown containers
        if viewMode != .allPlaces {
            view.addSubview(dropdownContainer)
            dropdownContainer.addSubview(categoryTableView)
        }
        
        // Setup base constraints
        var constraints: [NSLayoutConstraint] = [
            // Map view - full screen
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Close button - top right
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Places count label - top left
            placesCountLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            placesCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            placesCountLabel.heightAnchor.constraint(equalToConstant: 32),
            placesCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ]
        
        // Add category table view constraints only if NOT in allPlaces mode
        if viewMode != .allPlaces {
            constraints.append(contentsOf: [
                // Category table view inside dropdown
                categoryTableView.topAnchor.constraint(equalTo: dropdownContainer.topAnchor),
                categoryTableView.leadingAnchor.constraint(equalTo: dropdownContainer.leadingAnchor),
                categoryTableView.trailingAnchor.constraint(equalTo: dropdownContainer.trailingAnchor),
                categoryTableView.bottomAnchor.constraint(equalTo: dropdownContainer.bottomAnchor)
            ])
            
            // Create height constraint for dropdown
            dropdownHeightConstraint = dropdownContainer.heightAnchor.constraint(equalToConstant: 0)
            dropdownHeightConstraint?.isActive = true
        }
        
        NSLayoutConstraint.activate(constraints)
        
        // Add category filter constraints if NOT in allPlaces mode
        if viewMode != .allPlaces {
            NSLayoutConstraint.activate([
                // Category filter button - center top
                categoryFilterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                categoryFilterButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                categoryFilterButton.heightAnchor.constraint(equalToConstant: 32),
                
                // Dropdown container
                dropdownContainer.centerXAnchor.constraint(equalTo: categoryFilterButton.centerXAnchor),
                dropdownContainer.topAnchor.constraint(equalTo: categoryFilterButton.bottomAnchor, constant: 8),
                dropdownContainer.widthAnchor.constraint(equalToConstant: 200)
            ])
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
        } else {
            mapView.setRegion(initialRegion, animated: false)
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
        
        // Add annotations for each place
        for place in filteredPlaces {
            guard let location = place.location?.clLocation else { continue }
            
            let annotation = PlaceAnnotation(place: place)
            mapView.addAnnotation(annotation)
            
            // Store the place reference using ObjectIdentifier
            annotationPlaceMap[ObjectIdentifier(annotation)] = place
            
            // Update map rect
            let point = MKMapPoint(location.coordinate)
            let rect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            mapRect = mapRect.union(rect)
        }
        
        // Adjust region to show all annotations
        if !mapRect.isNull && filteredPlaces.count > 1 {
            let padding = UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100)
            mapView.setVisibleMapRect(mapRect, edgePadding: padding, animated: true)
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
            
            // Add detail button
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
        }
        
        // Customize marker appearance based on category
        if let markerView = annotationView {
            markerView.markerTintColor = categoryColor(for: placeAnnotation.place.category)
            markerView.glyphImage = UIImage(systemName: categoryIcon(for: placeAnnotation.place.category))
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { return }
        
        // Notify delegate
        delegate?.mapViewController(self, didSelectPlace: placeAnnotation.place)
        
        // Dismiss if not in allPlaces mode
        if viewMode != .allPlaces {
            dismiss(animated: true)
        }
    }
    
    private func categoryColor(for category: PlaceCategory) -> UIColor {
        switch category {
        case .restaurant:
            return UIColor(hex: "#E53E3E") // Red
        case .cafe:
            return UIColor(hex: "#DD6B20") // Orange
        case .bar:
            return UIColor(hex: "#DD6B20") // Orange
        case .hotel:
            return UIColor(hex: "#3182CE") // Blue
        case .retail:
            return UIColor(hex: "#805AD5") // Purple
        case .service:
            return UIColor(hex: "#38A169") // Green
        case .attraction:
            return UIColor(hex: "#D69E2E") // Yellow
        case .entertainment:
            return UIColor(hex: "#D69E2E") // Yellow
        case .healthcare:
            return UIColor(hex: "#319795") // Teal
        case .fitness:
            return UIColor(hex: "#38A169") // Green
        case .education:
            return UIColor(hex: "#3182CE") // Blue
        case .outdoor:
            return UIColor(hex: "#38A169") // Green
        case .transport:
            return UIColor(hex: "#718096") // Gray
        case .finance:
            return UIColor(hex: "#805AD5") // Purple
        case .home:
            return UIColor(hex: "#4A5568") // Dark Gray
        case .work:
            return UIColor(hex: "#2D3748") // Darker Gray
        case .other:
            return UIColor(hex: "#718096") // Gray
        }
    }
    
    private func categoryIcon(for category: PlaceCategory) -> String {
        switch category {
        case .restaurant:
            return "fork.knife"
        case .cafe:
            return "cup.and.saucer.fill"
        case .bar:
            return "wineglass"
        case .hotel:
            return "bed.double.fill"
        case .retail:
            return "bag.fill"
        case .service:
            return "wrench.and.screwdriver.fill"
        case .attraction:
            return "star.fill"
        case .entertainment:
            return "ticket.fill"
        case .healthcare:
            return "cross.fill"
        case .fitness:
            return "figure.walk"
        case .education:
            return "graduationcap.fill"
        case .outdoor:
            return "leaf.fill"
        case .transport:
            return "car.fill"
        case .finance:
            return "banknote.fill"
        case .home:
            return "house.fill"
        case .work:
            return "briefcase.fill"
        case .other:
            return "mappin"
        }
    }
    
    // MARK: - Actions
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
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
    
    private func selectCategory(_ category: PlaceCategory?) {
        selectedCategory = category
        updateFilterButtonTitle()
        applyFilter()
        hideDropdown()
    }
    
    private func selectConnection(_ connectionId: String?) {
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
        if let connectionId = selectedConnectionId {
            if connectionId == "my_places_only" {
                connectionFilterButton.setTitle("My Places Only", for: .normal)
            } else if let connection = connections.first(where: { $0.id == connectionId }) {
                let userName = connection.connectedUser?.displayName ?? "Unknown"
                connectionFilterButton.setTitle(userName, for: .normal)
            }
        } else {
            connectionFilterButton.setTitle("All Connections", for: .normal)
        }
    }
    
    private func applyFilter() {
        var filtered = places
        
        // Apply connection filter first (only in allPlaces mode)
        if viewMode == .allPlaces, let connectionId = selectedConnectionId {
            if connectionId == "my_places_only" {
                // Show only user's own places
                let currentUserId = AuthService.shared.getUserId() ?? ""
                filtered = filtered.filter { $0.addedBy == currentUserId }
            } else {
                // Show only places from the selected connection
                filtered = connectionPlaces[connectionId] ?? []
            }
        }
        
        // Then apply category filter
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        filteredPlaces = filtered
        updatePlacesCount()
        addAnnotationsToMap()
    }
    
    private func updatePlacesCount() {
        placesCountLabel.text = "\(filteredPlaces.count) places"
    }
}

// MARK: - CLLocationManagerDelegate
extension FullScreenMapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Zoom to user location
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        mapView.setRegion(region, animated: true)
        
        // Stop updating location
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
            return PlaceCategory.allCases.count + 1 // +1 for "All Categories"
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
                let categories = PlaceCategory.allCases
                let category = categories[indexPath.row - 1]
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
                cell.textLabel?.textColor = selectedConnectionId == connection.id ? .systemBlue : .white
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
                let categories = PlaceCategory.allCases
                selectCategory(categories[indexPath.row - 1])
            }
        } else if tableView == connectionTableView {
            if indexPath.row == 0 {
                selectConnection(nil) // All connections
            } else if indexPath.row == 1 {
                selectConnection("my_places_only") // My places only
            } else {
                let connection = connections[indexPath.row - 2]
                selectConnection(connection.id)
            }
        }
    }
}

