import UIKit
import MapKit
import CoreLocation

class CheckInViewController: BaseViewController {
    
    // MARK: - Properties
    private var myPlaces: [Place] = []
    private var nearbyPlaces: [Place] = []   // network places nearby (not mine), distance-sorted
    private let nearbySearch = NearbyPlaceSearch()  // shared POI search (also used by moments)
    private var searchResults: [MKLocalSearchCompletion] = []
    private var filteredPlaces: [Place] = []
    private var selectedPlace: Place?
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    // Step tracking
    private var currentStep = 1
    private var selectedIndexPath: IndexPath?
    
    // MARK: - Configuration
    override var showsLoadingIndicator: Bool { true }
    private var customEmptyStateMessage: String = "No places found"
    override var emptyStateMessage: String? { customEmptyStateMessage }
    override var loadsDataOnViewDidLoad: Bool { false } // We'll load manually after view appears
    
    // MARK: - UI Elements
    private let stepIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let stepLabel: UILabel = {
        let label = UILabel()
        label.text = "Step 1 of 3: Choose Place"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.progressTintColor = Constants.Colors.primary
        progress.trackTintColor = Constants.Colors.lightGray
        progress.setProgress(0.33, animated: false)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()
    
    // Place selection UI
    private let placeSelectionSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["My Places", "Nearby"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search places..."
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let placesTableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.background
        return table
    }()
    
    // Step 2 UI Elements (hidden initially)
    private let detailsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let selectedPlaceView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let selectedPlaceNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let selectedPlaceAddressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.text = "How long will you be there?"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let durationSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["30 min", "1 hour", "2 hours", "Until I leave"])
        control.selectedSegmentIndex = 1
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let messageTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "Add a message (optional)"
        field.borderStyle = .none  // Remove default border for custom styling
        field.font = UIFont.systemFont(ofSize: 16)
        field.backgroundColor = Constants.Colors.secondaryBackground
        field.layer.cornerRadius = 12
        field.layer.borderWidth = 1
        field.layer.borderColor = Constants.Colors.separator.cgColor
        
        // Add padding
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: field.frame.height))
        field.leftView = paddingView
        field.leftViewMode = .always
        let rightPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: field.frame.height))
        field.rightView = rightPaddingView
        field.rightViewMode = .always
        
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()
    
    private let activityFeedContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let activityFeedSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    private let activityFeedLabel: UILabel = {
        let label = UILabel()
        label.text = "Show in activity feed"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var nextButton = UIButton.primaryButton(title: "Next")
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationServices()
        setupSearchCompleter()
        // Setup keyboard handling for tap-to-dismiss
        setupKeyboardHandling(dismissOnTap: true)
        // Don't load data here - wait for viewDidAppear
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Load data after view is fully presented
        if !hasLoadedData {
            // If we're on Nearby tab and don't have location, request it first
            if placeSelectionSegmentedControl.selectedSegmentIndex == 1 && currentLocation == nil {
                switch locationManager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    showLoadingState()
                    locationManager.requestLocation()
                case .notDetermined:
                    locationManager.requestWhenInUseAuthorization()
                default:
                    loadData()
                }
            } else {
                loadData()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Clear any pending API requests for check-in places
        APIService.shared.clearPendingRequestsForEndpoint("places/my-places")
        
        // Remove keyboard handling observers
        removeKeyboardHandling()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Final cleanup when view is fully dismissed
        APIService.shared.clearPendingRequestsForEndpoint("places/my-places")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Check In"
        view.backgroundColor = Constants.Colors.background
        
        // Add cancel button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        
        // Add subviews
        view.addSubview(stepIndicatorView)
        stepIndicatorView.addSubview(stepLabel)
        stepIndicatorView.addSubview(progressView)
        
        view.addSubview(placeSelectionSegmentedControl)
        view.addSubview(searchBar)
        view.addSubview(placesTableView)
        
        // Step 2 views
        view.addSubview(detailsContainerView)
        detailsContainerView.addSubview(selectedPlaceView)
        selectedPlaceView.addSubview(selectedPlaceNameLabel)
        selectedPlaceView.addSubview(selectedPlaceAddressLabel)
        detailsContainerView.addSubview(durationLabel)
        detailsContainerView.addSubview(durationSegmentedControl)
        detailsContainerView.addSubview(messageTextField)
        detailsContainerView.addSubview(activityFeedContainer)
        activityFeedContainer.addSubview(activityFeedSwitch)
        activityFeedContainer.addSubview(activityFeedLabel)
        
        view.addSubview(nextButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Step indicator
            stepIndicatorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stepIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stepIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stepIndicatorView.heightAnchor.constraint(equalToConstant: 80),
            
            stepLabel.topAnchor.constraint(equalTo: stepIndicatorView.topAnchor, constant: 16),
            stepLabel.leadingAnchor.constraint(equalTo: stepIndicatorView.leadingAnchor, constant: 16),
            
            progressView.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: stepIndicatorView.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: stepIndicatorView.trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            // Place selection
            placeSelectionSegmentedControl.topAnchor.constraint(equalTo: stepIndicatorView.bottomAnchor, constant: 16),
            placeSelectionSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            placeSelectionSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            searchBar.topAnchor.constraint(equalTo: placeSelectionSegmentedControl.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            
            placesTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            placesTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placesTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placesTableView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16),
            
            // Details container (Step 2)
            detailsContainerView.topAnchor.constraint(equalTo: stepIndicatorView.bottomAnchor, constant: 16),
            detailsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            detailsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            detailsContainerView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16),
            
            selectedPlaceView.topAnchor.constraint(equalTo: detailsContainerView.topAnchor),
            selectedPlaceView.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor),
            selectedPlaceView.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor),
            selectedPlaceView.heightAnchor.constraint(equalToConstant: 80),
            
            selectedPlaceNameLabel.topAnchor.constraint(equalTo: selectedPlaceView.topAnchor, constant: 12),
            selectedPlaceNameLabel.leadingAnchor.constraint(equalTo: selectedPlaceView.leadingAnchor, constant: 16),
            selectedPlaceNameLabel.trailingAnchor.constraint(equalTo: selectedPlaceView.trailingAnchor, constant: -16),
            
            selectedPlaceAddressLabel.topAnchor.constraint(equalTo: selectedPlaceNameLabel.bottomAnchor, constant: 4),
            selectedPlaceAddressLabel.leadingAnchor.constraint(equalTo: selectedPlaceView.leadingAnchor, constant: 16),
            selectedPlaceAddressLabel.trailingAnchor.constraint(equalTo: selectedPlaceView.trailingAnchor, constant: -16),
            
            durationLabel.topAnchor.constraint(equalTo: selectedPlaceView.bottomAnchor, constant: 24),
            durationLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor),
            
            durationSegmentedControl.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 12),
            durationSegmentedControl.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor),
            durationSegmentedControl.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor),
            
            messageTextField.topAnchor.constraint(equalTo: durationSegmentedControl.bottomAnchor, constant: 24),
            messageTextField.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor),
            messageTextField.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor),
            messageTextField.heightAnchor.constraint(equalToConstant: 50),
            
            activityFeedContainer.topAnchor.constraint(equalTo: messageTextField.bottomAnchor, constant: 24),
            activityFeedContainer.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor),
            activityFeedContainer.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor),
            activityFeedContainer.heightAnchor.constraint(equalToConstant: 44),
            
            activityFeedSwitch.centerYAnchor.constraint(equalTo: activityFeedContainer.centerYAnchor),
            activityFeedSwitch.leadingAnchor.constraint(equalTo: activityFeedContainer.leadingAnchor),
            
            activityFeedLabel.centerYAnchor.constraint(equalTo: activityFeedContainer.centerYAnchor),
            activityFeedLabel.leadingAnchor.constraint(equalTo: activityFeedSwitch.trailingAnchor, constant: 12),
            
            // Next button
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Setup table view
        placesTableView.delegate = self
        placesTableView.dataSource = self
        // Don't register the cell - we'll create it with subtitle style in cellForRowAt
        
        // Setup delegates
        searchBar.delegate = self
        placeSelectionSegmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        
        // Initially disable next button
        nextButton.isEnabled = false
        nextButton.alpha = 0.6
    }
    
    // MARK: - Location Services
    private func setupLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Check current authorization status
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, request location
            locationManager.requestLocation()
        case .notDetermined:
            // Request authorization
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Handle denied case if user is on Nearby tab
            if placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
                showError("Location access is required to find nearby places. Please enable it in Settings.")
            }
        @unknown default:
            break
        }
    }
    
    private func setupSearchCompleter() {
        nearbySearch.delegate = self

        // Bias suggestions toward the user's area if we have a location
        if let location = currentLocation {
            nearbySearch.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,  // 5km radius
                longitudinalMeters: 5000
            )
        }
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        // Clear any pending requests before loading new data
        APIService.shared.clearPendingRequestsForEndpoint("places/my-places")
        
        if placeSelectionSegmentedControl.selectedSegmentIndex == 0 {
            // Load My Places
            loadMyPlaces()
        } else {
            // Nearby: populate with network places by distance (same source as
            // the moment place picker). Typing still runs the POI search.
            loadNearbyPlaces()
        }
        completion?()
    }

    /// Nearby = all network places near the user (not the user's own),
    /// distance-sorted. Shared with the moment picker via
    /// PlaceService.getNearbyPlaces so both tabs behave identically.
    private func loadNearbyPlaces() {
        guard let location = currentLocation else {
            // Location not resolved yet; didUpdateLocations will retry.
            placesTableView.reloadData()
            hideLoadingState()
            return
        }
        showLoadingState()
        PlaceService.shared.getNearbyPlaces(near: location) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoadingState()
                switch result {
                case .success(let places):
                    self.nearbyPlaces = places
                    if self.placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
                        self.placesTableView.reloadData()
                        if places.isEmpty {
                            self.customEmptyStateMessage = "No nearby places in your network yet. Search to find a place."
                            self.showEmptyState()
                        }
                    }
                case .failure:
                    self.nearbyPlaces = []
                    if self.placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
                        self.placesTableView.reloadData()
                    }
                }
            }
        }
    }
    
    private func loadMyPlaces() {
        // Show built-in loading indicator
        showLoadingState()
        
        PlaceService.shared.getMyPlacesForCheckIn { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Hide loading indicator
                self.hideLoadingState()
                
                switch result {
                case .success(let places):
                    // Sort places by proximity if we have location
                    let sortedPlaces: [Place]
                    if let currentLocation = self.currentLocation {
                        sortedPlaces = places.sorted { place1, place2 in
                            // Calculate distances
                            let distance1 = self.calculateDistanceToPlace(place1, from: currentLocation)
                            let distance2 = self.calculateDistanceToPlace(place2, from: currentLocation)
                            
                            // Sort by distance (nearest first)
                            if let d1 = distance1, let d2 = distance2 {
                                return d1 < d2
                            } else if distance1 != nil {
                                return true // Place with distance comes first
                            } else if distance2 != nil {
                                return false
                            } else {
                                // Neither has distance, sort alphabetically
                                return place1.name < place2.name
                            }
                        }
                    } else {
                        // No location, sort alphabetically
                        sortedPlaces = places.sorted { $0.name < $1.name }
                    }
                    
                    // One row per VENUE: the same place saved into two circles
                    // (legitimate) or duplicate saves must not list twice in a
                    // check-in picker — you check into the venue, not the save.
                    // Keeps the first occurrence (nearest, thanks to the sort).
                    var seenVenues = Set<String>()
                    let dedupedPlaces = sortedPlaces.filter { place in
                        let key: String
                        if let globalId = place.globalPlaceId, !globalId.isEmpty {
                            key = "gp:\(globalId)"
                        } else if let googleId = place.googlePlaceId, !googleId.isEmpty {
                            key = "g:\(googleId)"
                        } else {
                            // Name + ~500m coordinate bucket
                            let coords = place.location?.coordinates ?? []
                            let lat = coords.count == 2 ? Int(coords[1] * 200) : 0
                            let lng = coords.count == 2 ? Int(coords[0] * 200) : 0
                            key = "n:\(place.name.lowercased())|\(lat),\(lng)"
                        }
                        return seenVenues.insert(key).inserted
                    }

                    self.myPlaces = dedupedPlaces
                    self.filteredPlaces = dedupedPlaces
                    self.placesTableView.reloadData()
                    
                    if places.isEmpty {
                        self.customEmptyStateMessage = "No places found. Add places to your circles first."
                        self.showEmptyState()
                    }
                    
                case .failure(let error):
                    // Update data first
                    self.myPlaces = []
                    self.filteredPlaces = []
                    self.placesTableView.reloadData()
                    
                    // Set custom empty state message
                    self.customEmptyStateMessage = "Unable to load places. Please try again."
                    self.showEmptyState()
                    
                    // Show error
                    self.showError(error)
                }
            }
        }
    }
    
    private func calculateDistanceToPlace(_ place: Place, from location: CLLocation) -> CLLocationDistance? {
        // Check if place has coordinates
        if let lat = place.latitude, let lng = place.longitude {
            let placeLocation = CLLocation(latitude: lat, longitude: lng)
            return location.distance(from: placeLocation)
        }
        return nil
    }
    
    // Removed loadNearbyPlaces and fallbackToNaturalLanguageSearch - now using MKLocalSearchCompleter
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func segmentChanged() {
        // Clear search and selection
        searchBar.text = ""
        searchResults = []
        selectedIndexPath = nil
        selectedPlace = nil
        nextButton.isEnabled = false
        nextButton.alpha = 0.6
        
        // Hide any existing empty state
        hideEmptyState()
        
        if placeSelectionSegmentedControl.selectedSegmentIndex == 0 {
            // Switching to My Places
            searchBar.placeholder = "Search places..."
            loadMyPlaces()
        } else {
            // Switching to Nearby
            searchBar.placeholder = "Search for nearby places..."
            filteredPlaces = []
            myPlaces = []

            // Check location authorization; populate the nearby list once we
            // have a fix (didUpdateLocations retries if it's still resolving).
            if currentLocation == nil {
                switch locationManager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    locationManager.requestLocation()
                case .notDetermined:
                    locationManager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    showError("Location access is required to find nearby places.")
                @unknown default:
                    break
                }
            } else {
                loadNearbyPlaces()
            }
        }

        placesTableView.reloadData()
    }
    
    @objc private func nextButtonTapped() {
        if currentStep == 1 {
            // Move to step 2
            moveToStep2()
        } else if currentStep == 2 {
            // Move to step 3 (recipient selection)
            moveToStep3()
        }
    }
    
    private func moveToStep2() {
        currentStep = 2
        stepLabel.text = "Step 2 of 3: Set Details"
        progressView.setProgress(0.67, animated: true)
        
        // Update selected place info
        if let place = selectedPlace {
            selectedPlaceNameLabel.text = place.name
            selectedPlaceAddressLabel.text = place.address
        }
        
        // Hide step 1 views
        placeSelectionSegmentedControl.isHidden = true
        searchBar.isHidden = true
        placesTableView.isHidden = true
        
        // Show step 2 views
        detailsContainerView.isHidden = false
        
        // Update button
        nextButton.setTitle("Next →", for: .normal)
    }
    
    private func moveToStep3() {
        // Create recipient selection view controller
        let recipientVC = CheckInRecipientSelectionViewController()
        recipientVC.delegate = self
        
        // Pass check-in details
        var checkInData: [String: Any] = [
            "message": messageTextField.text ?? "",
            "showInActivityFeed": activityFeedSwitch.isOn
        ]
        
        // Add duration
        let durationOptions = ["30", "60", "120", "until_leave"]
        checkInData["duration"] = durationOptions[durationSegmentedControl.selectedSegmentIndex]
        
        // Add place info. A resolved POI that isn't already saved comes back
        // with an empty circleId — the backend creates it from the name/address/
        // coordinates below. An existing saved place is referenced by id.
        if let place = selectedPlace {
            let isNewPlace = place.circleId?.isEmpty ?? true
            checkInData["placeName"] = place.name
            checkInData["placeAddress"] = place.address
            checkInData["placeCategory"] = place.category.rawValue
            if let location = place.location?.clLocation {
                checkInData["latitude"] = location.coordinate.latitude
                checkInData["longitude"] = location.coordinate.longitude
            }
            if !isNewPlace {
                checkInData["placeId"] = place.id
                if let circleId = place.circleId {
                    checkInData["circleId"] = circleId
                }
            }
        }
        
        recipientVC.checkInData = checkInData
        navigationController?.pushViewController(recipientVC, animated: true)
    }
    
    // MARK: - Search
    private func filterPlaces(with searchText: String) {
        if searchText.isEmpty {
            filteredPlaces = myPlaces
        } else {
            filteredPlaces = myPlaces.filter { place in
                place.name.localizedCaseInsensitiveContains(searchText) ||
                place.address.localizedCaseInsensitiveContains(searchText)
            }
        }
        placesTableView.reloadData()
    }
    
    private func calculateDistanceForSearchResult(_ result: MKLocalSearchCompletion, from location: CLLocation) -> CLLocationDistance? {
        // This is an approximation since MKLocalSearchCompletion doesn't have coordinates
        // In practice, you'd need to perform a MKLocalSearch to get the actual location
        return nil
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        // Resolve via the shared POI search (same code path as the moment
        // picker). It matches an existing saved place when possible, otherwise
        // returns a new place with an empty circleId. Result arrives in the
        // NearbyPlaceSearchDelegate callbacks below.
        nearbySearch.resolve(result, near: currentLocation, existingPlaces: myPlaces)
    }
}

// MARK: - NearbyPlaceSearchDelegate (shared POI search)
extension CheckInViewController: NearbyPlaceSearchDelegate {
    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didUpdate completions: [MKLocalSearchCompletion]) {
        searchResults = completions
        Logger.debug("📍 CheckIn: POI search found \(completions.count) results")
        placesTableView.reloadData()
    }

    func nearbyPlaceSearchWillResolve(_ search: NearbyPlaceSearch) {
        showLoadingState()
    }

    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didResolve place: Place) {
        hideLoadingState()
        selectedPlace = place
        nextButton.isEnabled = true
        nextButton.alpha = 1.0
    }

    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didFailWith error: Error) {
        hideLoadingState()
        showError("Could not get place details: \(error.localizedDescription)")
    }
}

// MARK: - UITableViewDataSource
extension CheckInViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // If we have search results, show those regardless of tab
        if !searchResults.isEmpty {
            return searchResults.count
        }
        
        // Otherwise show the loaded list for the active tab
        if placeSelectionSegmentedControl.selectedSegmentIndex == 0 {
            return filteredPlaces.count
        } else {
            // Nearby: network places by distance (until the user searches)
            return nearbyPlaces.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "PlaceCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
        
        // If we have search results, show those
        if !searchResults.isEmpty {
            let result = searchResults[indexPath.row]
            cell.textLabel?.text = result.title
            
            // Show distance if we have location
            if let location = currentLocation,
               let distance = calculateDistanceForSearchResult(result, from: location) {
                let formatter = MKDistanceFormatter()
                formatter.unitStyle = .abbreviated
                let distanceString = formatter.string(fromDistance: distance)
                cell.detailTextLabel?.text = "\(result.subtitle) • \(distanceString)"
            } else {
                cell.detailTextLabel?.text = result.subtitle
            }
        }
        // Otherwise show the loaded place for the active tab
        else {
            let isMyPlaces = placeSelectionSegmentedControl.selectedSegmentIndex == 0
            let place = isMyPlaces ? filteredPlaces[indexPath.row] : nearbyPlaces[indexPath.row]
            cell.textLabel?.text = place.name

            // Build detail text with distance, circle name, and address
            var detailComponents: [String] = []

            // Add distance if available
            if let location = currentLocation,
               let distance = calculateDistanceToPlace(place, from: location) {
                let formatter = MKDistanceFormatter()
                formatter.unitStyle = .abbreviated
                let distanceString = formatter.string(fromDistance: distance)
                detailComponents.append(distanceString)
            }

            // Add circle name for My Places (not meaningful for others' places)
            if isMyPlaces, let circleName = place.circleName {
                detailComponents.append(circleName)
            }

            // Add address
            if !place.address.isEmpty {
                detailComponents.append(place.address)
            }

            cell.detailTextLabel?.text = detailComponents.joined(separator: " • ")
        }
        
        // Show checkmark for selected cell
        if indexPath == selectedIndexPath {
            cell.accessoryType = .checkmark
            cell.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        } else {
            cell.accessoryType = .none
            cell.backgroundColor = .clear
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension CheckInViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Update selection
        let previousIndexPath = selectedIndexPath
        selectedIndexPath = indexPath
        
        // Handle search result selection
        if !searchResults.isEmpty {
            let result = searchResults[indexPath.row]
            selectSearchResult(result)
        }
        // Handle a place from the active tab (My Places or Nearby)
        else {
            let isMyPlaces = placeSelectionSegmentedControl.selectedSegmentIndex == 0
            selectedPlace = isMyPlaces ? filteredPlaces[indexPath.row] : nearbyPlaces[indexPath.row]

            // Enable next button
            nextButton.isEnabled = true
            nextButton.alpha = 1.0
        }
        
        // Update cells to show/hide checkmarks
        var indexPathsToReload = [indexPath]
        if let previous = previousIndexPath {
            indexPathsToReload.append(previous)
        }
        tableView.reloadRows(at: indexPathsToReload, with: .automatic)
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - UISearchBarDelegate
extension CheckInViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            // Clear search results and show original data
            searchResults = []
            if placeSelectionSegmentedControl.selectedSegmentIndex == 0 {
                filteredPlaces = myPlaces
            }
            placesTableView.reloadData()
        } else {
            // POI search via the shared completer (same code as the moment picker)
            nearbySearch.updateQuery(searchText)
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - CLLocationManagerDelegate
extension CheckInViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        Logger.debug("📍 CheckIn: Received location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        Logger.debug("📍 CheckIn: Location accuracy: \(location.horizontalAccuracy)m")
        
        // Bias POI suggestions toward the user's area
        nearbySearch.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5000,  // 5km radius
            longitudinalMeters: 5000
        )
        
        // If on Nearby tab, populate the distance-sorted network list now that
        // we have a location fix (only if not already loaded).
        if placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
            searchBar.placeholder = "Search for nearby places..."
            if nearbyPlaces.isEmpty {
                loadNearbyPlaces()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
            showError("Unable to get your location. Please check location permissions.")
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Request location immediately when authorized
            manager.requestLocation()
            
            // If we're on the Nearby tab, update the search placeholder
            if placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
                searchBar.placeholder = "Search for nearby places..."
            }
        case .denied, .restricted:
            if placeSelectionSegmentedControl.selectedSegmentIndex == 1 {
                showError("Location access is required to find nearby places. Please enable it in Settings.")
                customEmptyStateMessage = "Location access required. Please enable in Settings."
                showEmptyState()
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}


// MARK: - CheckInRecipientSelectionDelegate
extension CheckInViewController: CheckInRecipientSelectionDelegate {
    func didCompleteCheckIn() {
        // Dismiss the entire check-in flow (including the navigation controller)
        navigationController?.dismiss(animated: true) ?? dismiss(animated: true)
    }
}