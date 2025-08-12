import UIKit
import CoreLocation

class DiscoveryListViewController: BaseViewController {
    
    // MARK: - Properties
    private var discoveryUsers: [User] = []
    private var currentDiscoveryType: MyNetworkViewController.NetworkTab = .discover
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    // MARK: - UI Elements
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
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        switch currentDiscoveryType {
        case .nearby:
            if CLLocationManager.authorizationStatus() == .denied ||
               CLLocationManager.authorizationStatus() == .restricted {
                return "Enable location services to find users near you\n\nGo to Settings > Privacy > Location Services"
            } else if currentLocation == nil {
                return "Getting your location...\n\nMake sure location services are enabled"
            } else {
                return "No users found nearby\n\nShowing popular users instead"
            }
        case .popular:
            return "No popular users found\n\nCheck back later as more people join"
        case .mutual:
            return "No mutual connections yet\n\nConnect with others to discover mutual connections"
        case .discover:
            return "No users to discover\n\nCheck back later"
        default:
            return "No users found"
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupLocationManager()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        view.addSubview(tableView)
        view.addSubview(locationPermissionView)
        
        locationPermissionView.addSubview(locationPermissionLabel)
        locationPermissionView.addSubview(enableLocationButton)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            locationPermissionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            locationPermissionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            locationPermissionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            locationPermissionView.heightAnchor.constraint(equalToConstant: 80),
            
            locationPermissionLabel.topAnchor.constraint(equalTo: locationPermissionView.topAnchor, constant: 16),
            locationPermissionLabel.leadingAnchor.constraint(equalTo: locationPermissionView.leadingAnchor, constant: 16),
            locationPermissionLabel.trailingAnchor.constraint(equalTo: locationPermissionView.trailingAnchor, constant: -16),
            
            enableLocationButton.topAnchor.constraint(equalTo: locationPermissionLabel.bottomAnchor, constant: 8),
            enableLocationButton.centerXAnchor.constraint(equalTo: locationPermissionView.centerXAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DiscoverUserCell.self, forCellReuseIdentifier: "DiscoverUserCell")
        
        // Pull to refresh is handled by BaseViewController
        tableView.refreshControl = refreshControl
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    // MARK: - Public Methods
    func setDiscoveryType(_ type: MyNetworkViewController.NetworkTab) {
        currentDiscoveryType = type
        
        // Check if we need location permission for nearby
        if type == .nearby {
            checkLocationPermission()
        } else {
            locationPermissionView.isHidden = true
        }
        
        loadData()
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        let discoveryType: String
        switch currentDiscoveryType {
        case .discover:
            discoveryType = "all"
        case .popular:
            discoveryType = "popular"
        case .nearby:
            discoveryType = "nearby"
        case .mutual:
            discoveryType = "friendsOfFriends"
        default:
            completion?()
            return
        }
        
        var endpoint = "users/contacts/discover?type=\(discoveryType)"
        
        // Add location for nearby searches
        if (currentDiscoveryType == .nearby || currentDiscoveryType == .discover), 
           let location = currentLocation {
            endpoint += "&lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)"
            updateUserLocation(location)
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<DiscoveryUsersResponse, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                completion?()
                
                switch result {
                case .success(let response):
                    self.discoveryUsers = response.users
                    self.tableView.reloadData()
                    
                    if self.discoveryUsers.isEmpty {
                        self.showEmptyState(message: self.emptyStateMessage)
                    } else {
                        self.hideEmptyState()
                    }
                    
                case .failure(let error):
                    Logger.error("Failed to load discovery users: \(error)")
                    self.showError(error)
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
    
    private func followUser(_ user: User, at indexPath: IndexPath) {
        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success:
                    // Update the user's following status
                    if indexPath.row < self?.discoveryUsers.count ?? 0 {
                        var updatedUser = self?.discoveryUsers[indexPath.row]
                        updatedUser = updatedUser?.copy(isFollowing: true)
                        if let updatedUser = updatedUser {
                            self?.discoveryUsers[indexPath.row] = updatedUser
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
                NotificationCenter.default.post(name: .connectionRequestSent, object: nil)
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension DiscoveryListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveryUsers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DiscoverUserCell", for: indexPath) as! DiscoverUserCell
        let user = discoveryUsers[indexPath.row]
        
        // Map the discovery type for the cell
        let cellDiscoveryType: DiscoverUserCell.DiscoveryType
        switch currentDiscoveryType {
        case .discover:
            cellDiscoveryType = .all
        case .popular:
            cellDiscoveryType = .popular
        case .nearby:
            cellDiscoveryType = .nearby
        case .mutual:
            cellDiscoveryType = .friendsOfFriends
        default:
            cellDiscoveryType = .all
        }
        
        cell.configure(with: user, discoveryType: cellDiscoveryType)
        cell.delegate = self
        cell.indexPath = indexPath
        return cell
    }
}

// MARK: - UITableViewDelegate
extension DiscoveryListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let user = discoveryUsers[indexPath.row]
        
        // Navigate to user profile
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 88
    }
}

// MARK: - CLLocationManagerDelegate
extension DiscoveryListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        
        // Reload if we're on nearby tab
        if currentDiscoveryType == .nearby || currentDiscoveryType == .discover {
            loadData()
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
extension DiscoveryListViewController: DiscoverUserCellDelegate {
    func discoverUserCellDidTapFollow(_ cell: DiscoverUserCell) {
        guard let indexPath = cell.indexPath else { return }
        let user = discoveryUsers[indexPath.row]
        followUser(user, at: indexPath)
    }
}

// MARK: - Response Models
// Response models are defined in Models/NetworkResponses.swift