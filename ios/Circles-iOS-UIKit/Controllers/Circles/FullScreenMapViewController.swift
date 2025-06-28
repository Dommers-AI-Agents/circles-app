import UIKit
import GoogleMaps
import GooglePlaces

class FullScreenMapViewController: UIViewController {
    
    // MARK: - Properties
    private let places: [Place]
    private let initialCamera: GMSCameraPosition
    private var markerPlaceMap: [GMSMarker: Place] = [:]
    private var selectedCategory: PlaceCategory?
    private var filteredPlaces: [Place] = []
    private var isDropdownOpen = false
    private var dropdownHeightConstraint: NSLayoutConstraint?
    
    // MARK: - UI Elements
    private let mapView: GMSMapView = {
        let mapView = GMSMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        
        // Enable map controls
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.tiltGestures = true
        mapView.settings.rotateGestures = true
        
        // Enable my location if permission granted
        mapView.isMyLocationEnabled = true
        
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
    
    // MARK: - Init
    init(places: [Place], initialCamera: GMSCameraPosition, selectedCategory: PlaceCategory? = nil) {
        self.places = places
        self.initialCamera = initialCamera
        self.selectedCategory = selectedCategory
        self.filteredPlaces = places
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
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
        
        // Add places count label
        view.addSubview(placesCountLabel)
        placesCountLabel.text = "\(places.count) places"
        
        // Add category filter button
        view.addSubview(categoryFilterButton)
        categoryFilterButton.addTarget(self, action: #selector(categoryFilterButtonTapped), for: .touchUpInside)
        
        // Add dropdown container
        view.addSubview(dropdownContainer)
        dropdownContainer.addSubview(categoryTableView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
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
            placesCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
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
        
        // Create height constraint for dropdown
        dropdownHeightConstraint = dropdownContainer.heightAnchor.constraint(equalToConstant: 0)
        dropdownHeightConstraint?.isActive = true
        
        // Add padding to label
        placesCountLabel.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    }
    
    private func setupMap() {
        mapView.delegate = self
        mapView.camera = initialCamera
    }
    
    private func setupTableView() {
        categoryTableView.delegate = self
        categoryTableView.dataSource = self
        categoryTableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
    }
    
    // MARK: - Map Annotations
    private func addAnnotationsToMap() {
        // Clear existing markers
        mapView.clear()
        markerPlaceMap.removeAll()
        
        var bounds = GMSCoordinateBounds()
        var hasValidLocation = false
        
        // Add markers for each place
        for place in filteredPlaces {
            guard let location = place.location?.clLocation else { continue }
            
            let marker = GMSMarker()
            marker.position = location.coordinate
            marker.title = place.name
            marker.snippet = place.displayCategory
            marker.map = mapView
            
            // Store the place reference
            markerPlaceMap[marker] = place
            
            // Use custom marker view
            marker.iconView = createMarkerView(for: place)
            
            // Update bounds
            bounds = bounds.includingCoordinate(location.coordinate)
            hasValidLocation = true
        }
        
        // Adjust camera to show all markers
        if hasValidLocation && filteredPlaces.count > 1 {
            let update = GMSCameraUpdate.fit(bounds, withPadding: 100.0)
            mapView.animate(with: update)
        }
    }
    
    private func createMarkerView(for place: Place) -> UIView {
        // Create container view
        let markerView = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        
        // Add shadow
        markerView.layer.shadowColor = UIColor.black.cgColor
        markerView.layer.shadowOffset = CGSize(width: 1, height: 1)
        markerView.layer.shadowOpacity = 0.3
        markerView.layer.shadowRadius = 2
        
        // Create white background circle
        let backgroundView = UIView(frame: markerView.bounds)
        backgroundView.backgroundColor = .white
        backgroundView.layer.cornerRadius = 18
        markerView.addSubview(backgroundView)
        
        // Create colored inner circle
        let coloredView = UIView(frame: CGRect(x: 3, y: 3, width: 30, height: 30))
        coloredView.backgroundColor = categoryColor(for: place.category)
        coloredView.layer.cornerRadius = 15
        markerView.addSubview(coloredView)
        
        // Add category icon
        let iconImageView = UIImageView(frame: CGRect(x: 8, y: 8, width: 20, height: 20))
        iconImageView.image = UIImage(systemName: categoryIcon(for: place.category))
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        markerView.addSubview(iconImageView)
        
        return markerView
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
            return UIColor(hex: "#3182CE") // Blue
        case .work:
            return UIColor(hex: "#38A169") // Green
        case .other:
            return UIColor(hex: "#718096") // Gray
        }
    }
    
    private func categoryIcon(for category: PlaceCategory) -> String {
        switch category {
        case .restaurant:
            return "fork.knife"
        case .cafe:
            return "cup.and.saucer"
        case .bar:
            return "wineglass"
        case .hotel:
            return "bed.double"
        case .retail:
            return "bag"
        case .service:
            return "wrench.and.screwdriver"
        case .attraction:
            return "star"
        case .entertainment:
            return "ticket"
        case .healthcare:
            return "cross.case"
        case .fitness:
            return "figure.run"
        case .education:
            return "book"
        case .outdoor:
            return "tree"
        case .transport:
            return "car"
        case .finance:
            return "dollarsign.circle"
        case .home:
            return "house"
        case .work:
            return "building.2"
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
    
    private func toggleDropdown() {
        isDropdownOpen.toggle()
        
        if isDropdownOpen {
            showDropdown()
        } else {
            hideDropdown()
        }
    }
    
    private func showDropdown() {
        // Calculate dropdown height based on number of categories + 1 for "All Categories"
        let numberOfRows = PlaceCategory.allCases.count + 1
        let maxHeight: CGFloat = 300 // Maximum height before scrolling
        let calculatedHeight = CGFloat(numberOfRows) * 44
        let dropdownHeight = min(calculatedHeight, maxHeight)
        
        dropdownContainer.isHidden = false
        dropdownHeightConstraint?.constant = dropdownHeight
        
        // Animate dropdown appearance
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.dropdownContainer.alpha = 1
            self.view.layoutIfNeeded()
            
            // Rotate arrow
            self.categoryFilterButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        // Add tap gesture to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)
    }
    
    private func hideDropdown() {
        UIView.animate(withDuration: 0.2, animations: {
            self.dropdownContainer.alpha = 0
            self.dropdownHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
            
            // Rotate arrow back
            self.categoryFilterButton.imageView?.transform = .identity
        }) { _ in
            self.dropdownContainer.isHidden = true
        }
        
        // Remove tap gesture
        mapView.gestureRecognizers?.forEach { gesture in
            if gesture is UITapGestureRecognizer {
                mapView.removeGestureRecognizer(gesture)
            }
        }
    }
    
    @objc private func handleTapOutside(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        
        // Check if tap is outside dropdown and button
        if !dropdownContainer.frame.contains(location) && !categoryFilterButton.frame.contains(location) {
            hideDropdown()
        }
    }
    
    private func applyFilter() {
        // Filter places based on selected category
        if let category = selectedCategory {
            filteredPlaces = places.filter { $0.category == category }
        } else {
            filteredPlaces = places
        }
        
        // Update places count label
        placesCountLabel.text = "\(filteredPlaces.count) places"
        
        // Update map annotations
        addAnnotationsToMap()
    }
    
    private func updateFilterButtonTitle() {
        if let category = selectedCategory {
            categoryFilterButton.setTitle(category.displayName, for: .normal)
        } else {
            categoryFilterButton.setTitle("All Categories", for: .normal)
        }
    }
    
    // MARK: - Place Actions
    private func showPlaceActionSheet(for place: Place) {
        let actionSheet = UIAlertController(title: place.name, message: place.address, preferredStyle: .actionSheet)
        
        // View Details
        actionSheet.addAction(UIAlertAction(title: "View Details", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                // The presenting view controller should handle navigation to place details
                NotificationCenter.default.post(
                    name: Notification.Name("ShowPlaceDetails"),
                    object: nil,
                    userInfo: ["place": place]
                )
            }
        })
        
        // Get Directions
        if place.location != nil {
            actionSheet.addAction(UIAlertAction(title: "Get Directions", style: .default) { _ in
                self.openDirections(for: place)
            })
        }
        
        // Cancel
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(actionSheet, animated: true)
    }
    
    private func openDirections(for place: Place) {
        guard let location = place.location?.clLocation else { return }
        
        let coordinate = location.coordinate
        
        // Try Google Maps first
        let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving")
        
        if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to Apple Maps
            let appleMapsURL = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")
            if let url = appleMapsURL {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - GMSMapViewDelegate
extension FullScreenMapViewController: GMSMapViewDelegate {
    func mapView(_ mapView: GMSMapView, didTapInfoWindowOf marker: GMSMarker) {
        guard let place = markerPlaceMap[marker] else { return }
        showPlaceActionSheet(for: place)
    }
    
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        // Center the map on the marker
        mapView.animate(toLocation: marker.position)
        
        // Return false to display the info window
        return false
    }
    
    func mapView(_ mapView: GMSMapView, markerInfoWindow marker: GMSMarker) -> UIView? {
        guard let place = markerPlaceMap[marker] else { return nil }
        
        // Create custom info window
        let infoWindow = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 80))
        infoWindow.backgroundColor = .white
        infoWindow.layer.cornerRadius = 8
        infoWindow.layer.masksToBounds = true
        
        // Add shadow
        infoWindow.layer.shadowColor = UIColor.black.cgColor
        infoWindow.layer.shadowOffset = CGSize(width: 0, height: 2)
        infoWindow.layer.shadowOpacity = 0.2
        infoWindow.layer.shadowRadius = 4
        infoWindow.layer.masksToBounds = false
        
        // Name label
        let nameLabel = UILabel(frame: CGRect(x: 12, y: 8, width: 226, height: 20))
        nameLabel.text = place.name
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .black
        infoWindow.addSubview(nameLabel)
        
        // Category label
        let categoryLabel = UILabel(frame: CGRect(x: 12, y: 30, width: 226, height: 16))
        categoryLabel.text = place.displayCategory
        categoryLabel.font = UIFont.systemFont(ofSize: 13)
        categoryLabel.textColor = .darkGray
        infoWindow.addSubview(categoryLabel)
        
        // Rating if available
        if let rating = place.rating {
            let ratingLabel = UILabel(frame: CGRect(x: 12, y: 48, width: 100, height: 16))
            ratingLabel.text = String(repeating: "★", count: Int(rating.rounded())) + " \(rating)"
            ratingLabel.font = UIFont.systemFont(ofSize: 13)
            ratingLabel.textColor = UIColor(hex: "#F6E05E")
            infoWindow.addSubview(ratingLabel)
        }
        
        // Tap hint label
        let hintLabel = UILabel(frame: CGRect(x: 150, y: 48, width: 88, height: 16))
        hintLabel.text = "Tap for options"
        hintLabel.font = UIFont.systemFont(ofSize: 11)
        hintLabel.textColor = .systemBlue
        hintLabel.textAlignment = .right
        infoWindow.addSubview(hintLabel)
        
        return infoWindow
    }
    
    func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
        // Create an alert to ask if user wants to add this place
        let alert = UIAlertController(
            title: "Add \(name)?",
            message: "Would you like to add this place to your circle?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                // Notify the presenting controller to add the POI
                NotificationCenter.default.post(
                    name: Notification.Name("AddPOIToCircle"),
                    object: nil,
                    userInfo: ["placeID": placeID, "name": name, "location": location]
                )
            }
        })
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension FullScreenMapViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlaceCategory.allCases.count + 1 // +1 for "All Categories"
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        
        // Configure cell appearance
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cell.selectionStyle = .none
        
        if indexPath.row == 0 {
            // All Categories option
            cell.textLabel?.text = "All Categories"
            if selectedCategory == nil {
                cell.textLabel?.text = "✓ All Categories"
                cell.textLabel?.textColor = UIColor(hex: "#4299E1") // Blue accent
            }
        } else {
            // Specific category
            let category = PlaceCategory.allCases[indexPath.row - 1]
            cell.textLabel?.text = category.displayName
            
            if category == selectedCategory {
                cell.textLabel?.text = "✓ \(category.displayName)"
                cell.textLabel?.textColor = UIColor(hex: "#4299E1") // Blue accent
            }
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension FullScreenMapViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            // All Categories selected
            selectedCategory = nil
        } else {
            // Specific category selected
            selectedCategory = PlaceCategory.allCases[indexPath.row - 1]
        }
        
        // Update UI
        updateFilterButtonTitle()
        applyFilter()
        tableView.reloadData()
        
        // Hide dropdown after selection
        hideDropdown()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}
