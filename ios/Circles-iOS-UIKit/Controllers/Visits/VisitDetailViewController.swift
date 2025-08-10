import UIKit
import MapKit
import CoreLocation

class VisitDetailViewController: UIViewController {
    
    // MARK: - Properties
    private var visit: PlaceVisit
    var onVisitUpdated: (() -> Void)?
    private let locationManager = CLLocationManager()
    
    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let mapView: MKMapView = {
        let map = MKMapView()
        map.layer.cornerRadius = 12
        map.clipsToBounds = true
        
        // Enable map controls
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        
        // Show points of interest on the map
        map.showsPointsOfInterest = true
        map.showsBuildings = true
        
        // Enable POI selection (iOS 16+)
        if #available(iOS 16.0, *) {
            map.selectableMapFeatures = [.pointsOfInterest]
        }
        
        map.translatesAutoresizingMaskIntoConstraints = false
        return map
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let visitDetailsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let expandMapButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let zoomToMeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var addToCircleButton = UIButton.primaryButton(title: "Add to Circle")
    private lazy var dismissButton = UIButton.dangerButton(title: "Dismiss Visit")
    
    // MARK: - Init
    init(visit: PlaceVisit) {
        self.visit = visit
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        configureView()
        // Setup keyboard handling for notes text view
        setupKeyboardHandling(scrollView: scrollView, dismissOnTap: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Check location authorization status
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, start updating location
            locationManager.startUpdatingLocation()
        case .notDetermined:
            // Request permission
            locationManager.requestWhenInUseAuthorization()
        default:
            // Denied or restricted - keep default location
            break
        }
        
        // Automatically mark visit as reviewed when viewed
        if !visit.reviewed && !visit.dismissed {
            // Small delay to ensure user actually views the visit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.markAsReviewed()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Visit Details"
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(saveNotes)
        )
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(mapView)
        contentView.addSubview(expandMapButton)
        contentView.addSubview(zoomToMeButton)
        contentView.addSubview(placeNameLabel)
        contentView.addSubview(addressLabel)
        contentView.addSubview(visitDetailsLabel)
        contentView.addSubview(notesTextView)
        contentView.addSubview(addToCircleButton)
        contentView.addSubview(dismissButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            mapView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mapView.heightAnchor.constraint(equalToConstant: 200),
            
            // Expand button - top right of map
            expandMapButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 8),
            expandMapButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8),
            expandMapButton.widthAnchor.constraint(equalToConstant: 30),
            expandMapButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Zoom button - bottom right of map
            zoomToMeButton.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -8),
            zoomToMeButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8),
            zoomToMeButton.widthAnchor.constraint(equalToConstant: 30),
            zoomToMeButton.heightAnchor.constraint(equalToConstant: 30),
            
            placeNameLabel.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 20),
            placeNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            placeNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            addressLabel.topAnchor.constraint(equalTo: placeNameLabel.bottomAnchor, constant: 8),
            addressLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: placeNameLabel.trailingAnchor),
            
            visitDetailsLabel.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 16),
            visitDetailsLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            visitDetailsLabel.trailingAnchor.constraint(equalTo: placeNameLabel.trailingAnchor),
            
            notesTextView.topAnchor.constraint(equalTo: visitDetailsLabel.bottomAnchor, constant: 20),
            notesTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            notesTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            notesTextView.heightAnchor.constraint(equalToConstant: 120),
            
            addToCircleButton.topAnchor.constraint(equalTo: notesTextView.bottomAnchor, constant: 24),
            addToCircleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addToCircleButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            addToCircleButton.heightAnchor.constraint(equalToConstant: 50),
            
            dismissButton.topAnchor.constraint(equalTo: addToCircleButton.bottomAnchor, constant: 12),
            dismissButton.leadingAnchor.constraint(equalTo: addToCircleButton.leadingAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: addToCircleButton.trailingAnchor),
            dismissButton.heightAnchor.constraint(equalToConstant: 50),
            dismissButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        expandMapButton.addTarget(self, action: #selector(expandMapButtonTapped), for: .touchUpInside)
        zoomToMeButton.addTarget(self, action: #selector(zoomToMeButtonTapped), for: .touchUpInside)
        addToCircleButton.addTarget(self, action: #selector(addToCircleTapped), for: .touchUpInside)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        
        // Set up map delegate
        mapView.delegate = self
        
        // Set up location manager
        locationManager.delegate = self
        
        // Hide buttons if already processed
        if visit.reviewed || visit.dismissed {
            addToCircleButton.isHidden = true
            dismissButton.isHidden = true
        }
    }
    
    private func configureView() {
        placeNameLabel.text = visit.placeName
        addressLabel.text = visit.placeAddress
        notesTextView.text = visit.notes ?? ""
        
        // Format visit details
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        var details = "Visited on \(formatter.string(from: visit.visitedAt))"
        if visit.duration > 0 {
            details += "\nDuration: \(visit.duration) minutes"
        }
        if let category = visit.category {
            details += "\nCategory: \(category)"
        }
        
        // Add location accuracy info
        if let accuracy = visit.horizontalAccuracy {
            let accuracyDesc: String
            if accuracy < 10 {
                accuracyDesc = "Excellent (±\(Int(accuracy))m)"
            } else if accuracy < 25 {
                accuracyDesc = "Good (±\(Int(accuracy))m)"
            } else if accuracy < 50 {
                accuracyDesc = "Fair (±\(Int(accuracy))m)"
            } else {
                accuracyDesc = "Poor (±\(Int(accuracy))m)"
            }
            details += "\nLocation accuracy: \(accuracyDesc)"
        }
        
        // Add coordinates for reference
        details += "\nCoordinates: \(String(format: "%.6f, %.6f", visit.latitude, visit.longitude))"
        
        if visit.autoDetected {
            details += "\n🤖 Auto-detected visit"
        }
        
        visitDetailsLabel.text = details
        
        // Configure map
        let coordinate = CLLocationCoordinate2D(
            latitude: visit.latitude,
            longitude: visit.longitude
        )
        
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: false)
        
        // Add pin
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = visit.placeName
        mapView.addAnnotation(annotation)
    }
    
    // MARK: - Actions
    @objc private func saveNotes() {
        guard let notes = notesTextView.text,
              notes != visit.notes else {
            navigationController?.popViewController(animated: true)
            return
        }
        
        updateVisit(updates: ["notes": notes]) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func addToCircleTapped() {
        let circlePickerVC = VisitCirclePickerViewController()
        circlePickerVC.onCirclesSelected = { [weak self] circleIds in
            guard let self = self else { return }
            
            let loading = AlertPresenter.showLoading(from: self)
            
            APIService.shared.request(
                endpoint: "visits/bulk-add",
                method: .post,
                body: [
                    "visitIds": [self.visit.id],
                    "circleIds": circleIds
                ],
                requiresAuth: true
            ) { (result: Result<BulkAddResponse, APIError>) in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        switch result {
                        case .success:
                            self.showSuccess("Added to circles!")
                            self.onVisitUpdated?()
                            self.navigationController?.popViewController(animated: true)
                            
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
        
        let nav = UINavigationController(rootViewController: circlePickerVC)
        present(nav, animated: true)
    }
    
    @objc private func dismissTapped() {
        showConfirmation(
            title: "Dismiss Visit?",
            message: "This visit will be removed from your history.",
            confirmTitle: "Dismiss",
            isDestructive: true
        ) { [weak self] in
            self?.updateVisit(updates: ["dismissed": true]) {
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    private func updateVisit(updates: [String: Any], completion: (() -> Void)? = nil) {
        APIService.shared.request(
            endpoint: "visits/\(visit.id)",
            method: .put,
            body: updates,
            requiresAuth: true
        ) { [weak self] (result: Result<VisitResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.onVisitUpdated?()
                    completion?()
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func markAsReviewed() {
        visit.reviewed = true
        updateVisit(updates: ["reviewed": true])
    }
    
    @objc private func expandMapButtonTapped() {
        // Create a GeoLocation from visit coordinates
        let visitLocation = GeoLocation(
            type: "Point",
            coordinates: [visit.longitude, visit.latitude] // MongoDB format: [lng, lat]
        )
        
        // Map visit category to PlaceCategory enum
        let category: PlaceCategory = {
            if let visitCategory = visit.category?.lowercased() {
                return PlaceCategory(rawValue: visitCategory) ?? .other
            }
            return .other
        }()
        
        // Create a minimal Place object to show as a pin
        let visitPlace = Place(
            id: visit.id,
            name: visit.placeName,
            description: visit.notes,
            address: visit.placeAddress,
            location: visitLocation,
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: visit.photos.isEmpty ? nil : visit.photos,
            category: category,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: visit.notes,
            privateNotes: nil,
            publicNotes: visit.notes,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: [],
            likesCount: 0,
            commentsCount: 0,
            circleId: "", // Empty string as we don't have a circle
            addedBy: visit.userId,
            addedByUser: nil,
            privacy: .public, // Default to public for visit display
            createdAt: visit.visitedAt,
            updatedAt: visit.visitedAt,
            isNew: false
        )
        
        // Create a zoomed-in region centered on the visit
        let visitCoordinate = CLLocationCoordinate2D(
            latitude: visit.latitude,
            longitude: visit.longitude
        )
        let zoomedRegion = MKCoordinateRegion(
            center: visitCoordinate,
            latitudinalMeters: 1000, // 1km radius for better POI selection
            longitudinalMeters: 1000
        )
        
        // Pass the visit place to show as a pin
        let fullScreenMapVC = FullScreenMapViewController(
            places: [visitPlace],
            initialRegion: zoomedRegion,
            selectedCategory: nil,
            selectedConnectionId: nil
        )
        fullScreenMapVC.delegate = self
        fullScreenMapVC.isPresentedModally = true
        fullScreenMapVC.showFilters = false // Hide filters for place selection
        
        let navigationController = UINavigationController(rootViewController: fullScreenMapVC)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
    
    @objc private func zoomToMeButtonTapped() {
        guard let userLocation = locationManager.location else {
            // Request location permission if not available
            locationManager.requestWhenInUseAuthorization()
            return
        }
        
        let region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        mapView.setRegion(region, animated: true)
    }
}

// MARK: - MKMapViewDelegate
extension VisitDetailViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Handle POI selection for iOS 16+
        if #available(iOS 16.0, *) {
            if let featureAnnotation = view.annotation as? MKMapFeatureAnnotation {
                handlePOISelection(featureAnnotation)
                return
            }
        }
        
        // Deselect the annotation if it's not a POI
        if let annotation = view.annotation {
            mapView.deselectAnnotation(annotation, animated: true)
        }
    }
    
    @available(iOS 16.0, *)
    private func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let coordinate = featureAnnotation.coordinate
        
        // First, show options for what to do with this POI
        let alertController = UIAlertController(
            title: poiName,
            message: "What would you like to do with this place?",
            preferredStyle: .actionSheet
        )
        
        alertController.addAction(UIAlertAction(title: "Add to a Circle", style: .default) { [weak self] _ in
            // Navigate to circle picker to add this POI
            let circlePickerVC = VisitCirclePickerViewController()
            circlePickerVC.onCirclesSelected = { circleIds in
                guard let firstCircleId = circleIds.first else { return }
                
                // Navigate to AddPlaceViewController with the selected circle
                let addPlaceVC = AddPlaceViewController(circleId: firstCircleId)
                self?.navigationController?.pushViewController(addPlaceVC, animated: true)
                
                // Prefill the search with the POI name and coordinate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    addPlaceVC.prefillSearchWithPlace(name: poiName, coordinate: coordinate)
                }
            }
            
            let nav = UINavigationController(rootViewController: circlePickerVC)
            self?.present(nav, animated: true)
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Deselect the POI annotation
        mapView.deselectAnnotation(featureAnnotation, animated: true)
        
        present(alertController, animated: true)
    }
}

// MARK: - CLLocationManagerDelegate
extension VisitDetailViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension VisitDetailViewController: FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        // If a place is selected from the full screen map, navigate to place details
        controller.dismiss(animated: true) {
            let placeDetailVC = PlaceDetailViewController(place: place)
            self.navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}