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

    /// Which face of discovery this instance shows. `.discover` is the
    /// suggestion surface (people you don't follow yet); `.popular` is the
    /// scorecard — everyone ranked by collection size, including people you
    /// already follow, because watching people you know climb is the fun.
    enum Mode {
        case discover
        case popular
    }

    private let mode: Mode

    init(mode: Mode = .discover) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // The app is young, so the best first follows are people near you and
    // power users — their collections are the product's value made visible.
    // "Follows you" stays high because the other person already opted in;
    // engine suggestions round it out. (Power users graduated to their own
    // Popular tab — the leaderboard — so Discover stays pure suggestions.)
    private var sectionPlan: [(type: String, title: String, blurb: String?)] {
        switch mode {
        case .discover:
            return [
                ("nearby", "📍 Near you", "People exploring your area — their saved spots are your next stop."),
                ("followsYou", "👋 Follows you", "They're already following you — follow back with one tap."),
                // Backed by the suggestion engine, so these rows carry a real
                // reason — a venue you both saved, a shared taste, or who
                // already follows them.
                ("friendsOfFriends", "✨ Suggested for you", nil)
            ]
        case .popular:
            return [
                ("leaderboard", "🔥 Popular", "The biggest collections on FavCircles — everyone, ranked. Where do you land?")
            ]
        }
    }

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

    // Discover must never dead-end. When there's nobody left to suggest —
    // the "I've added everyone" case — the page's job shifts from browsing
    // people to bringing people, so the empty state becomes an invite CTA.
    private lazy var inviteEmptyView: UIView = {
        let container = UIView()
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "person.2.wave.2"))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Every place has a story"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center

        let message = UILabel()
        message.text = "You already know everyone here. Invite your friends to join Circles and share their favorite places."
        message.font = .systemFont(ofSize: 15)
        message.textColor = .secondaryLabel
        message.textAlignment = .center
        message.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, message, inviteButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),

            stack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            inviteButton.widthAnchor.constraint(equalToConstant: 180),
            inviteButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        return container
    }()

    private lazy var inviteButton: UIButton = {
        let button = UIButton.primaryButton(title: "Invite Friends")
        button.addTarget(self, action: #selector(inviteFriendsTapped), for: .touchUpInside)
        return button
    }()

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        guard searchQuery.isEmpty else { return "Nobody matching \"\(searchQuery)\"" }
        switch mode {
        case .discover:
            return "No suggestions right now\n\nInvite a friend, or add your zipcode in your profile so we can find people near you."
        case .popular:
            return "No rankings yet\n\nAdd places to claim the top spot!"
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        // Location only powers the "Near you" section, which is a Discover
        // concern — the Popular leaderboard needs no permission banner.
        if mode == .discover {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
            checkLocationPermission()
        }
    }

    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        view.addSubview(tableView)
        view.addSubview(locationPermissionView)
        locationPermissionView.addSubview(locationPermissionLabel)
        locationPermissionView.addSubview(enableLocationButton)

        view.addSubview(inviteEmptyView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            inviteEmptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            inviteEmptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            inviteEmptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

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

        for plan in sectionPlan {
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
            self.sections = sectionPlan.compactMap { plan in
                let users = (loaded[plan.type] ?? []).filter { alreadyShown.insert($0.id).inserted }
                guard !users.isEmpty else { return nil }
                return SuggestionSection(type: plan.type, title: plan.title, blurb: plan.blurb, users: users)
            }

            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }

    /// Empty Discover (nothing to suggest, no search running) becomes the
    /// invite CTA — "you know everyone; bring your friends" — instead of a
    /// dead-end message. Search misses and the Popular tab keep plain text.
    private func updateEmptyState() {
        let showInvite = visibleSections.isEmpty && searchQuery.isEmpty && mode == .discover
        inviteEmptyView.isHidden = !showInvite
        if showInvite {
            hideEmptyState()
        } else if visibleSections.isEmpty {
            showEmptyState(message: emptyStateMessage)
        } else {
            hideEmptyState()
        }
    }

    @objc private func inviteFriendsTapped() {
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = inviteButton
            popover.sourceRect = inviteButton.bounds
        }
        present(activityVC, animated: true)
    }

    /// Filters the loaded suggestions. These lists are small and already in
    /// memory, so this needs no extra request — and it means the search field
    /// above this segment is no longer inert.
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        tableView.reloadData()
        updateEmptyState()
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
        guard user.id != AuthService.shared.getUserId() else { return }
        setFollowing(true, forUserId: user.id)

        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let response) = result {
                    // First-ever follow of this person earns a dime
                    PiggyBankDepositView.play(credit: response.piggyBank)
                } else if case .failure(let error) = result {
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

        updateEmptyState()
    }
}

// MARK: - UITableViewDataSource

extension DiscoveryListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Bounds-guarded: visibleSections is recomputed per call and the
        // backing data mutates asynchronously (loads, dismissals, follows) —
        // a stale section index from UIKit must degrade to 0, not crash.
        guard section < visibleSections.count else { return 0 }
        return visibleSections[section].users.count
    }

    // Custom headers: a bold title with the section's pitch right under it.
    // The default grouped header (small gray caps, blurb exiled to a footer)
    // read like a settings screen, not a place to meet people.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < visibleSections.count else { return nil }
        let sectionData = visibleSections[section]

        let titleLabel = UILabel()
        titleLabel.text = sectionData.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = Constants.Colors.label

        let blurbLabel = UILabel()
        blurbLabel.text = sectionData.blurb
        blurbLabel.font = .systemFont(ofSize: 13)
        blurbLabel.textColor = Constants.Colors.secondaryLabel
        blurbLabel.numberOfLines = 0
        blurbLabel.isHidden = (sectionData.blurb == nil)

        let stack = UIStackView(arrangedSubviews: [titleLabel, blurbLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6)
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DiscoverUserCell", for: indexPath) as! DiscoverUserCell
        guard indexPath.section < visibleSections.count,
              indexPath.row < visibleSections[indexPath.section].users.count else { return cell }
        cell.configure(
            with: visibleSections[indexPath.section].users[indexPath.row],
            rank: mode == .popular ? indexPath.row + 1 : nil
        )
        cell.delegate = self
        cell.indexPath = indexPath
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DiscoveryListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < visibleSections.count,
              indexPath.row < visibleSections[indexPath.section].users.count else { return }
        let user = visibleSections[indexPath.section].users[indexPath.row]
        navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
    }

    // Cells size themselves — the card now stacks a tier chip, stats,
    // location, and a reason line, and clipping any of them defeats the point.
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 104 }
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

    func discoverUserCellDidTapShare(_ cell: DiscoverUserCell) {
        // Same share sheet as the nav-bar invite: profile link + pitch. The
        // self row in Most active is the moment someone feels good about their
        // collection — that's exactly when they'll show it to somebody.
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(activityVC, animated: true)
    }

    func discoverUserCellDidTapDismiss(_ cell: DiscoverUserCell) {
        guard let indexPath = cell.indexPath,
              indexPath.section < visibleSections.count,
              indexPath.row < visibleSections[indexPath.section].users.count else { return }
        dismiss(visibleSections[indexPath.section].users[indexPath.row])
    }
}
