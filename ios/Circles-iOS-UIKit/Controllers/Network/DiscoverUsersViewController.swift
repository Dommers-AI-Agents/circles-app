import UIKit
import CoreLocation

class DiscoverUsersViewController: BaseViewController {
    
    // MARK: - Properties
    private var discoveryUsers: [User] = []
    private var searchResults: [User] = []
    private var isSearching = false
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var selectedDiscoveryType: DiscoveryType = .all
    
    enum DiscoveryType: String, CaseIterable {
        case all = "All"
        case popular = "Popular"
        case nearby = "Nearby"
        case friendsOfFriends = "Mutual Friends"
        
        var icon: UIImage? {
            switch self {
            case .all: return UIImage(systemName: "person.3.fill")
            case .popular: return UIImage(systemName: "star.fill")
            case .nearby: return UIImage(systemName: "location.fill")
            case .friendsOfFriends: return UIImage(systemName: "person.2.fill")
            }
        }
    }
    
    // MARK: - UI Elements
    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.searchBar.delegate = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Search by name, username, or email"
        controller.searchBar.searchBarStyle = .minimal
        return controller
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let items = DiscoveryType.allCases.map { $0.rawValue }
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let locationPermissionView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let locationPermissionLabel: UILabel = {
        let label = UILabel()
        label.text = "Enable location to discover nearby users"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var enableLocationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Enable Location", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(enableLocationTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupLocationManager()
        loadDiscoveryUsers()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Discover People"
        view.backgroundColor = Constants.Colors.background
        
        // Setup search
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        
        // Add close button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        // Setup views
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(locationPermissionView)
        
        locationPermissionView.addSubview(locationPermissionLabel)
        locationPermissionView.addSubview(enableLocationButton)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            locationPermissionView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            locationPermissionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            locationPermissionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            locationPermissionView.heightAnchor.constraint(equalToConstant: 80),
            
            locationPermissionLabel.topAnchor.constraint(equalTo: locationPermissionView.topAnchor, constant: 16),
            locationPermissionLabel.leadingAnchor.constraint(equalTo: locationPermissionView.leadingAnchor, constant: 16),
            locationPermissionLabel.trailingAnchor.constraint(equalTo: locationPermissionView.trailingAnchor, constant: -16),
            
            enableLocationButton.topAnchor.constraint(equalTo: locationPermissionLabel.bottomAnchor, constant: 8),
            enableLocationButton.centerXAnchor.constraint(equalTo: locationPermissionView.centerXAnchor)
        ])
        
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DiscoverUserCell.self, forCellReuseIdentifier: "DiscoverUserCell")
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        if isSearching {
            // Don't reload discovery users while searching
            completion?()
            return
        }
        
        loadDiscoveryUsers(completion: completion)
    }
    
    private func loadDiscoveryUsers(completion: (() -> Void)? = nil) {
        var endpoint = "users/contacts/discover?type=\(selectedDiscoveryType == .friendsOfFriends ? "friendsOfFriends" : selectedDiscoveryType.rawValue.lowercased())"
        
        // Add location for nearby searches
        if selectedDiscoveryType == .nearby || selectedDiscoveryType == .all {
            if let location = currentLocation {
                endpoint += "&lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)"
                
                // Update location on backend
                updateUserLocation(location)
            }
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<DiscoveryUsersResponse, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.tableView.refreshControl?.endRefreshing()
                completion?()
                
                switch result {
                case .success(let response):
                    self.discoveryUsers = response.users
                    self.tableView.reloadData()
                    self.updateEmptyState()
                    
                case .failure(let error):
                    Logger.error("Failed to load discovery users: \(error)")
                    self.showError(error)
                }
            }
        }
    }
    
    private func searchUsers(query: String) {
        guard query.count >= 2 else {
            searchResults = []
            tableView.reloadData()
            return
        }
        
        let endpoint = "users/contacts/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<SearchUsersResponse, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.searchResults = response.users
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    Logger.error("Search failed: \(error)")
                }
            }
        }
    }
    
    private func updateUserLocation(_ location: CLLocation) {
        let body: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
        
        APIService.shared.request(
            endpoint: "users/contacts/update-location",
            method: .post,
            body: body
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            // Silent update, no need to handle response
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func segmentChanged() {
        selectedDiscoveryType = DiscoveryType.allCases[segmentedControl.selectedSegmentIndex]
        
        // Check if we need location permission for nearby
        if selectedDiscoveryType == .nearby {
            checkLocationPermission()
        } else {
            locationPermissionView.isHidden = true
        }
        
        loadDiscoveryUsers()
    }
    
    @objc override func refreshData() {
        loadDiscoveryUsers()
    }
    
    @objc private func enableLocationTapped() {
        if CLLocationManager.authorizationStatus() == .denied {
            // Open settings
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        } else {
            // Request permission
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    private func checkLocationPermission() {
        let status = CLLocationManager.authorizationStatus()
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationPermissionView.isHidden = true
            locationManager.requestLocation()
        case .notDetermined:
            locationPermissionView.isHidden = false
        case .denied, .restricted:
            locationPermissionView.isHidden = false
            enableLocationButton.setTitle("Open Settings", for: .normal)
        @unknown default:
            break
        }
    }
    
    private func updateEmptyState() {
        if isSearching && searchResults.isEmpty {
            showEmptyState(message: "No users found")
        } else if !isSearching && discoveryUsers.isEmpty {
            let message: String
            switch selectedDiscoveryType {
            case .nearby:
                if CLLocationManager.authorizationStatus() == .denied || 
                   CLLocationManager.authorizationStatus() == .restricted {
                    message = "Enable location services to find users near you\n\nGo to Settings > Privacy > Location Services"
                } else if currentLocation == nil {
                    message = "Getting your location...\n\nMake sure location services are enabled"
                } else {
                    message = "No users found nearby\n\nShowing popular users instead"
                }
            case .popular:
                message = "No popular users found\n\nCheck back later as more people join"
            case .friendsOfFriends:
                // Check if user has connections
                message = "Build your network first!\n\nConnect with people to discover their connections"
            case .all:
                message = "No users to discover\n\nCheck back later"
            }
            showEmptyState(message: message)
        } else {
            hideEmptyState()
        }
    }
    
    private func followUser(_ user: User, at indexPath: IndexPath) {
        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update the user's following status
                    if self?.isSearching == true {
                        if indexPath.row < self?.searchResults.count ?? 0 {
                            var updatedUser = self?.searchResults[indexPath.row]
                            updatedUser = updatedUser?.copy(isFollowing: true)
                            if let updatedUser = updatedUser {
                                self?.searchResults[indexPath.row] = updatedUser
                            }
                        }
                    } else {
                        if indexPath.row < self?.discoveryUsers.count ?? 0 {
                            var updatedUser = self?.discoveryUsers[indexPath.row]
                            updatedUser = updatedUser?.copy(isFollowing: true)
                            if let updatedUser = updatedUser {
                                self?.discoveryUsers[indexPath.row] = updatedUser
                            }
                        }
                    }
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                    
                    // Send connection request
                    self?.sendConnectionRequest(to: user)
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func sendConnectionRequest(to user: User) {
        NetworkManager.shared.sendConnectionRequest(to: user.id) { error in
            if error == nil {
                // Connection request sent successfully
                NotificationCenter.default.post(name: .connectionRequestSent, object: nil)
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension DiscoverUsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? searchResults.count : discoveryUsers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DiscoverUserCell", for: indexPath) as! DiscoverUserCell
        let user = isSearching ? searchResults[indexPath.row] : discoveryUsers[indexPath.row]
        
        // Map DiscoverUsersViewController.DiscoveryType to DiscoverUserCell.DiscoveryType
        let cellDiscoveryType: DiscoverUserCell.DiscoveryType
        switch selectedDiscoveryType {
        case .all:
            cellDiscoveryType = .all
        case .popular:
            cellDiscoveryType = .popular
        case .nearby:
            cellDiscoveryType = .nearby
        case .friendsOfFriends:
            cellDiscoveryType = .friendsOfFriends
        }
        
        cell.configure(with: user, discoveryType: cellDiscoveryType)
        cell.delegate = self
        cell.indexPath = indexPath
        return cell
    }
}

// MARK: - UITableViewDelegate
extension DiscoverUsersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let user = isSearching ? searchResults[indexPath.row] : discoveryUsers[indexPath.row]
        
        // Navigate to user profile
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 88
    }
}

// MARK: - UISearchResultsUpdating
extension DiscoverUsersViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        
        if searchText.isEmpty {
            isSearching = false
            searchResults = []
            tableView.reloadData()
            updateEmptyState()
        } else {
            isSearching = true
            searchUsers(query: searchText)
        }
    }
}

// MARK: - UISearchBarDelegate
extension DiscoverUsersViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        searchResults = []
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - CLLocationManagerDelegate
extension DiscoverUsersViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        
        // Reload if we're on nearby tab
        if selectedDiscoveryType == .nearby || selectedDiscoveryType == .all {
            loadDiscoveryUsers()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.error("Location error: \(error)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationPermission()
    }
}

// MARK: - DiscoverUserCellDelegate
extension DiscoverUsersViewController: DiscoverUserCellDelegate {
    func discoverUserCellDidTapFollow(_ cell: DiscoverUserCell) {
        guard let indexPath = cell.indexPath else { return }
        let user = isSearching ? searchResults[indexPath.row] : discoveryUsers[indexPath.row]
        followUser(user, at: indexPath)
    }
}

// MARK: - Response Models
// DiscoveryUsersResponse and SearchUsersResponse are now in Models/NetworkResponses.swift

// MARK: - Notification Names
extension Notification.Name {
    static let connectionRequestSent = Notification.Name("connectionRequestSent")
}