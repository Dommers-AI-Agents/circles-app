import UIKit
import CoreLocation

/// Discover: people who aren't in your network yet.
///
/// This used to be four separate chips (Discover / Popular / Nearby / Mutual)
/// that all hit the same endpoint with a different sort, so finding anyone
/// meant guessing which of four lists they'd be in. It's now one list of
/// labelled sections, so every reason to follow someone is visible at once.
class DiscoveryListViewController: BaseViewController {

    /// A group of suggestions that share a reason.
    private struct SuggestionSection {
        let type: String          // the API's `type` query value
        let title: String
        let blurb: String?
        var users: [User]
    }

    // Ordered by conversion, then aspiration. "Follows you" is first because
    // the other person has already opted in — following back is one tap and
    // can't be rejected. "Most active" is second: a big collection is the
    // app's value made visible ("follow this person, inherit 200 places") and
    // the strongest motivator to grow a network.
    private static let sectionPlan: [(type: String, title: String, blurb: String?)] = [
        ("followsYou", "Follows you", "Following back is instant — no approval needed."),
        ("popular", "Most active", "The biggest collections on FavCircles — follow to see all their spots."),
        // Backed by the suggestion engine, so these rows carry a real reason —
        // a venue you both saved, a shared taste, or who already follows them.
        // Each row states its own reason, so they belong in one section rather
        // than split across tabs nobody would think to check.
        ("friendsOfFriends", "Suggested for you", nil),
        ("nearby", "Near you", nil)
    ]

    private var sections: [SuggestionSection] = []
    private var searchQuery: String = ""
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
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
        label.text = "Turn on location to find people near you"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var enableLocationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Turn On Location", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(enableLocationTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        searchQuery.isEmpty
            ? "No suggestions right now\n\nInvite a friend, or add your zipcode in your profile so we can find people near you."
            : "Nobody matching \"\(searchQuery)\""
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        checkLocationPermission()
    }

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
        tableView.refreshControl = refreshControl
    }

    // MARK: - Data

    /// Fetches every section in parallel. Four small concurrent requests beat
    /// making someone tap through four tabs to discover the same people.
    override func loadData(completion: (() -> Void)? = nil) {
        let group = DispatchGroup()
        var loaded: [String: [User]] = [:]
        let lock = NSLock()

        for plan in Self.sectionPlan {
            group.enter()
            var endpoint = "users/contacts/discover?type=\(plan.type)"
            if plan.type == "nearby", let location = currentLocation {
                endpoint += "&lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)"
            }

            APIService.shared.request(
                endpoint: endpoint,
                method: .get
            ) { (result: Result<DiscoveryUsersResponse, APIError>) in
                if case .success(let response) = result {
                    lock.lock()
                    loaded[plan.type] = response.users
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            completion?()

            // Someone should appear under their strongest reason only, so once
            // a person shows up in an earlier section later ones skip them.
            var alreadyShown = Set<String>()
            self.sections = Self.sectionPlan.compactMap { plan in
                let users = (loaded[plan.type] ?? []).filter { alreadyShown.insert($0.id).inserted }
                guard !users.isEmpty else { return nil }
                return SuggestionSection(type: plan.type, title: plan.title, blurb: plan.blurb, users: users)
            }

            self.tableView.reloadData()
            if self.visibleSections.isEmpty {
                self.showEmptyState(message: self.emptyStateMessage)
            } else {
                self.hideEmptyState()
            }
        }
    }

    /// Filters the loaded suggestions. These lists are small and already in
    /// memory, so this needs no extra request — and it means the search field
    /// above this segment is no longer inert.
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        tableView.reloadData()
    }

    private var visibleSections: [SuggestionSection] {
        guard !searchQuery.isEmpty else { return sections }
        let query = searchQuery.lowercased()
        return sections.compactMap { section in
            let matches = section.users.filter {
                $0.displayName.lowercased().contains(query)
                    || ($0.username?.lowercased().contains(query) ?? false)
            }
            guard !matches.isEmpty else { return nil }
            return SuggestionSection(type: section.type, title: section.title, blurb: section.blurb, users: matches)
        }
    }

    private func updateUserLocation(_ location: CLLocation) {
        APIService.shared.request(
            endpoint: "users/contacts/update-location",
            method: .post,
            body: ["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude]
        ) { (_: Result<SimpleAPIResponse, APIError>) in }
    }

    // MARK: - Actions

    @objc private func enableLocationTapped() {
        if CLLocationManager.authorizationStatus() == .denied {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func checkLocationPermission() {
        switch CLLocationManager.authorizationStatus() {
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

    private func follow(_ user: User) {
        setFollowing(true, forUserId: user.id)

        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    self.setFollowing(false, forUserId: user.id)
                    self.showError(error)
                }
                // Following no longer secretly fires a connection request as
                // well. Connect is offered on its own once you follow each
                // other, so a tap does exactly what its label says.
            }
        }
    }

    private func setFollowing(_ isFollowing: Bool, forUserId userId: String) {
        for sectionIndex in sections.indices {
            if let userIndex = sections[sectionIndex].users.firstIndex(where: { $0.id == userId }) {
                sections[sectionIndex].users[userIndex] =
                    sections[sectionIndex].users[userIndex].copy(isFollowing: isFollowing)
            }
        }
        tableView.reloadData()
    }

    /// Removes a suggestion for good. Without this the same faces come back
    /// every time, which reads as the list being broken.
    private func dismiss(_ user: User) {
        for sectionIndex in sections.indices {
            sections[sectionIndex].users.removeAll { $0.id == user.id }
        }
        sections.removeAll { $0.users.isEmpty }
        tableView.reloadData()

        APIService.shared.request(
            endpoint: "users/contacts/dismiss-suggestion",
            method: .post,
            body: ["userId": user.id]
        ) { (_: Result<SimpleAPIResponse, APIError>) in }

        if visibleSections.isEmpty {
            showEmptyState(message: emptyStateMessage)
        }
    }
}

// MARK: - UITableViewDataSource

extension DiscoveryListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleSections[section].users.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        visibleSections[section].title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        visibleSections[section].blurb
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DiscoverUserCell", for: indexPath) as! DiscoverUserCell
        cell.configure(with: visibleSections[indexPath.section].users[indexPath.row])
        cell.delegate = self
        cell.indexPath = indexPath
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DiscoveryListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = visibleSections[indexPath.section].users[indexPath.row]
        navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 88 }
}

// MARK: - CLLocationManagerDelegate

extension DiscoveryListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateUserLocation(location)
        loadData()
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
        guard let indexPath = cell.indexPath,
              indexPath.section < visibleSections.count,
              indexPath.row < visibleSections[indexPath.section].users.count else { return }
        follow(visibleSections[indexPath.section].users[indexPath.row])
    }

    func discoverUserCellDidTapDismiss(_ cell: DiscoverUserCell) {
        guard let indexPath = cell.indexPath,
              indexPath.section < visibleSections.count,
              indexPath.row < visibleSections[indexPath.section].users.count else { return }
        dismiss(visibleSections[indexPath.section].users[indexPath.row])
    }
}
