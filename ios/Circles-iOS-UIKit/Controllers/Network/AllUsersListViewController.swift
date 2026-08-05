import UIKit


class AllUsersListViewController: UIViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        table.isHidden = true // Start hidden to prevent flash of empty content
        return table
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "person.2.slash")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Users Found"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emptySubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Start building your network by inviting people to connect with you."
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private lazy var discoverUsersButton: UIButton = {
        let button = UIButton.primaryButton(title: "Discover Users")
        button.addTarget(self, action: #selector(discoverUsersTapped), for: .touchUpInside)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties

    /// What this list shows. `.people` is the network you have (connections +
    /// following); `.requests` is the in/out connection requests, which live on
    /// their own tab so they don't crowd the people you're already close to.
    enum ListMode { case people, requests }
    var listMode: ListMode = .people

    /// Sub-scope within `.people`: Connections | Following. Two different
    /// relationships deserve two lists, not one long scroll — Following also
    /// hosts the follow-back section, since those people are one tap away
    /// from joining it.
    private enum PeopleScope: Int { case connections = 0, following = 1 }
    private var peopleScope: PeopleScope = .connections

    private lazy var scopeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Connections", "Following"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.isHidden = true // shown for .people mode in setupView
        return control
    }()

    /// ⓘ beside the Connections | Following tabs — the two relationships are
    /// different in a way the labels alone don't explain.
    private lazy var scopeInfoButton: UIButton = {
        let button = UIButton.iconButton(systemName: "info.circle", pointSize: 16)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = "What are Connections and Following?"
        button.addTarget(self, action: #selector(scopeInfoTapped), for: .touchUpInside)
        button.isHidden = true // shown alongside scopeControl in setupView
        return button
    }()

    @objc private func scopeInfoTapped() {
        AlertPresenter.showInfo(
            title: "Connections vs Following",
            message: """
            Following — you see their public places and activity in your feed. \
            One-way and instant; they don't need to approve.

            Connections — you both agreed to connect. Unlocks their \
            network-only circles, messaging, and place suggestions.

            You can follow someone and also be connected — those people \
            appear in both lists.
            """,
            from: self
        )
    }

    @objc private func scopeChanged() {
        peopleScope = PeopleScope(rawValue: scopeControl.selectedSegmentIndex) ?? .connections
        tableView.reloadData()
        if visibleSectionsAreEmpty && !isSearchActive {
            showNoConnectionsState()
        } else {
            hideEmptyState()
        }
    }

    private var allUsers: [User] = []
    private var connectedUsers: [User] = []
    private var pendingIncomingUsers: [User] = []
    private var pendingOutgoingUsers: [User] = []
    /// Everyone you follow — connections included; a person can sit in both
    /// tabs, because Follow and Connect are independent relationships.
    private var followingUsers: [User] = []
    /// People who follow you that you haven't followed back — the follow-back
    /// list. The warmest leads on the page: they already opted in.
    private var followsYouUsers: [User] = []
    /// Only populated while searching: people outside your network entirely.
    private var nonConnectedUsers: [User] = []
    private var filteredConnectedUsers: [User] = []
    private var filteredPendingIncomingUsers: [User] = []
    private var filteredPendingOutgoingUsers: [User] = []
    private var filteredFollowingUsers: [User] = []
    private var filteredFollowsYouUsers: [User] = []
    private var filteredNonConnectedUsers: [User] = []
    
    private let cellIdentifier = "UserCell"
    private var searchQuery: String = ""

    // Incoming requests are no longer collapsible at all — the tab badge
    // announces them, so they have to be visible the moment you arrive.
    // Only "Sent" still collapses, since it is status rather than a task.
    // Visible by default: a sent request is something you are waiting on, not
    // something to hide. Still collapsible for people with long lists.
    private var isPendingOutgoingExpanded = true
    private var isSearchActive: Bool { !searchQuery.isEmpty }

    private var isLoadingData = false
    private var hasLoadedInitialData = false
    private static var hasEverLoadedConnections = false
    private var minimumLoadingTimer: Timer?
    
    // MARK: - Helper Methods
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Lifecycle
    override func loadView() {
        super.loadView()
        
        // Set initial loading state before any views are added
        if !hasLoadedInitialData {
            isLoadingData = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        setupTableView()
        setupEmptyState()
        
        // Show loading state if needed
        if !hasLoadedInitialData {
            showLoadingState()
        }

        installExplainerCardIfNeeded()
        loadPeople()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // If we haven't loaded initial data yet, ensure proper loading state
        if !hasLoadedInitialData {
            tableView.isHidden = true
            emptyStateView.isHidden = true
            loadingIndicator.startAnimating()
            // Don't load again - viewDidLoad already started the load
            return
        }
        
        // Only refresh if we're not currently loading
        if !isLoadingData {
            loadPeople()
        }
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(scopeControl)
        view.addSubview(scopeInfoButton)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(loadingIndicator)

        // The Connections | Following sub-scope only exists on the People tab;
        // the Requests tab keeps its single list.
        let tableTop: NSLayoutConstraint
        if listMode == .people {
            scopeControl.isHidden = false
            scopeInfoButton.isHidden = false
            NSLayoutConstraint.activate([
                scopeControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
                scopeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                scopeControl.trailingAnchor.constraint(equalTo: scopeInfoButton.leadingAnchor, constant: -8),

                scopeInfoButton.centerYAnchor.constraint(equalTo: scopeControl.centerYAnchor),
                scopeInfoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                scopeInfoButton.widthAnchor.constraint(equalToConstant: 28),
                scopeInfoButton.heightAnchor.constraint(equalToConstant: 28)
            ])
            tableTop = tableView.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 8)
        } else {
            tableTop = tableView.topAnchor.constraint(equalTo: view.topAnchor)
        }

        NSLayoutConstraint.activate([
            tableTop,
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Start with loading state to prevent flash of empty content
        if !hasLoadedInitialData {
            // Table and empty state are already hidden from initialization
            loadingIndicator.startAnimating()
        }
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AllUsersCell.self, forCellReuseIdentifier: cellIdentifier)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshUsers), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyTitleLabel)
        emptyStateView.addSubview(emptySubtitleLabel)
        emptyStateView.addSubview(discoverUsersButton)
        
        NSLayoutConstraint.activate([
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 80),
            emptyImageView.heightAnchor.constraint(equalToConstant: 80),
            
            emptyTitleLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 24),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptySubtitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptySubtitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            discoverUsersButton.topAnchor.constraint(equalTo: emptySubtitleLabel.bottomAnchor, constant: 24),
            discoverUsersButton.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            discoverUsersButton.widthAnchor.constraint(equalToConstant: 200),
            discoverUsersButton.heightAnchor.constraint(equalToConstant: 44),
            discoverUsersButton.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading

    /// Loads the people who are actually in your network.
    ///
    /// This used to call `searchUsers(query: "")`, which returns the *entire*
    /// users collection — so opening the tab read every account in the database
    /// and buried your own connections in the middle of a directory of
    /// strangers. Now it reads two bounded lists: your connections and the
    /// people you follow. Strangers appear only when you search for them.
    /// True only while a loadPeople request group is actually in flight.
    /// Deliberately separate from isLoadingData, which loadView pre-sets as a
    /// show-the-spinner flag before any request exists — guarding on that made
    /// the first load return before it began.
    private var isPeopleRequestInFlight = false

    func loadPeople() {
        // Re-entrancy guard. The parent tab calls this directly on segment
        // switches and tab re-taps, so two runs could overlap — and the second
        // run's /following fetch would die in APIService's 0.5s duplicate
        // window, then overwrite good data with an empty list at notify time.
        guard !isPeopleRequestInFlight else { return }
        isPeopleRequestInFlight = true
        if !hasLoadedInitialData {
            showLoadingState()
        }
        isLoadingData = true

        let group = DispatchGroup()
        var connectionUsers: [User] = []
        var followingUsers: [User] = []
        var followerUsers: [User] = []
        var loadError: Error?

        group.enter()
        NetworkManager.shared.fetchConnectionUsers { result in
            switch result {
            case .success(let users): connectionUsers = users
            case .failure(let error): loadError = error
            }
            group.leave()
        }

        // On failure these fall back to what's already on screen — an error is
        // not information about who you follow, and must never blank a list
        // that loaded fine a moment ago.
        group.enter()
        UserService.shared.getFollowing { [weak self] result in
            switch result {
            case .success(let users):
                followingUsers = users
            case .failure(let error):
                Logger.debug("Following list failed, keeping previous: \(error)")
                followingUsers = self?.allUsers.filter { ($0.isFollowing ?? false) } ?? []
            }
            group.leave()
        }

        group.enter()
        UserService.shared.getFollowers { [weak self] result in
            switch result {
            case .success(let users):
                followerUsers = users
            case .failure(let error):
                Logger.debug("Followers list failed, keeping previous: \(error)")
                followerUsers = self?.allUsers.filter { ($0.followsYou ?? false) } ?? []
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isPeopleRequestInFlight = false
            self.tableView.refreshControl?.endRefreshing()
            self.isLoadingData = false
            self.hasLoadedInitialData = true
            self.hideLoadingState()

            if connectionUsers.isEmpty, followingUsers.isEmpty, followerUsers.isEmpty, let error = loadError {
                Logger.debug("Failed to load network: \(error)")
                self.showEmptyState()
                return
            }

            // Connections win on conflict: their payload carries connectionId
            // and status, which the following list doesn't always have.
            // Followers merge lowest — by definition every one of them follows
            // the caller, so stamp followsYou before richer payloads overwrite.
            // Follow flags must survive the connection overwrite: a connection
            // you follow still belongs in the Following tab.
            var merged: [String: User] = [:]
            for user in followerUsers { merged[user.id] = user.copy(followsYou: true) }
            for user in followingUsers {
                let followsYou = merged[user.id]?.followsYou ?? user.followsYou
                merged[user.id] = user.copy(isFollowing: true, followsYou: followsYou)
            }
            for user in connectionUsers {
                let prior = merged[user.id]
                merged[user.id] = user.copy(
                    isFollowing: (user.isFollowing ?? false) || (prior?.isFollowing ?? false),
                    followsYou: (user.followsYou ?? false) || (prior?.followsYou ?? false)
                )
            }

            self.allUsers = Array(merged.values)
            self.sortAndFilterUsers()
            self.tableView.reloadData()

            if self.visibleSectionsAreEmpty {
                self.showNoConnectionsState()
            } else {
                self.hideEmptyState()
            }
        }
    }

    /// Kept so existing callers (and the parent tab) keep compiling.
    func loadAllUsers() { loadPeople() }

    private var visibleSectionsAreEmpty: Bool {
        switch listMode {
        case .requests:
            return pendingIncomingUsers.isEmpty && pendingOutgoingUsers.isEmpty
        case .people:
            switch peopleScope {
            case .connections: return connectedUsers.isEmpty
            case .following: return followingUsers.isEmpty && followsYouUsers.isEmpty
            }
        }
    }

    /// Searching reaches past your own network to everybody else — which is the
    /// only time a stranger belongs on this screen.
    private func searchBeyondNetwork(_ query: String) {
        guard query.count >= 2 else {
            nonConnectedUsers = []
            filterUsers()
            tableView.reloadData()
            return
        }

        UserService.shared.searchUsers(query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.searchQuery == query else { return }
                if case .success(let users) = result {
                    let known = Set(self.allUsers.map { $0.id })
                    self.nonConnectedUsers = users.filter { !known.contains($0.id) }
                    self.filterUsers()
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func sortAndFilterUsers() {
        connectedUsers = allUsers.filter { RelationshipTier(user: $0) == .connected }
        pendingIncomingUsers = allUsers.filter { RelationshipTier(user: $0) == .requestReceived }
        pendingOutgoingUsers = allUsers.filter { RelationshipTier(user: $0) == .requestSent }
        // Everyone the caller follows — INCLUDING connections and pending
        // requests. Filtering by tier here hid every followed person who had
        // also connected, which read as "Not following anyone yet" for users
        // whose follows are mostly connections.
        followingUsers = allUsers.filter { $0.isFollowing ?? false }
        // The follow-back list: they follow you, you haven't followed back
        followsYouUsers = allUsers.filter { RelationshipTier(user: $0) == .followsYou }
        followsYouUsers.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        // Mutual follows first inside Following — those are the rows offering
        // Connect, which is the action worth surfacing.
        followingUsers.sort { lhs, rhs in
            let lhsMutual = RelationshipTier(user: lhs) == .mutualFollow
            let rhsMutual = RelationshipTier(user: rhs) == .mutualFollow
            if lhsMutual != rhsMutual { return lhsMutual }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let byName: (User, User) -> Bool = {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        // Connections: most places first — the size of someone's collection is
        // what makes their profile worth opening. Names break ties.
        connectedUsers.sort { lhs, rhs in
            let lhsPlaces = lhs.placesCount ?? 0
            let rhsPlaces = rhs.placesCount ?? 0
            if lhsPlaces != rhsPlaces { return lhsPlaces > rhsPlaces }
            return byName(lhs, rhs)
        }
        pendingIncomingUsers.sort(by: byName)
        pendingOutgoingUsers.sort(by: byName)

        filterUsers()
    }

    private func filterUsers() {
        guard !searchQuery.isEmpty else {
            filteredConnectedUsers = connectedUsers
            filteredPendingIncomingUsers = pendingIncomingUsers
            filteredPendingOutgoingUsers = pendingOutgoingUsers
            filteredFollowingUsers = followingUsers
            filteredFollowsYouUsers = followsYouUsers
            filteredNonConnectedUsers = []
            return
        }

        let query = searchQuery.lowercased()
        let matches: (User) -> Bool = { user in
            user.displayName.lowercased().contains(query)
                || (user.email?.lowercased().contains(query) ?? false)
                || (user.username?.lowercased().contains(query) ?? false)
        }

        filteredConnectedUsers = connectedUsers.filter(matches)
        filteredPendingIncomingUsers = pendingIncomingUsers.filter(matches)
        filteredPendingOutgoingUsers = pendingOutgoingUsers.filter(matches)
        filteredFollowingUsers = followingUsers.filter(matches)
        filteredFollowsYouUsers = followsYouUsers.filter(matches)
        filteredNonConnectedUsers = nonConnectedUsers.filter(matches)
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        filterUsers()
        tableView.reloadData()
        searchBeyondNetwork(query)
    }

    @objc private func refreshUsers() {
        loadPeople()
    }

    @objc private func discoverUsersTapped() {
        // The parent tab owns the segmented control, so ask it to switch rather
        // than pushing a duplicate discovery screen on top of this one.
        NotificationCenter.default.post(name: .showDiscoverSegment, object: nil)
    }

    // MARK: - Empty State
    private func showEmptyState() {
        guard !isLoadingData else { return }

        emptyStateView.isHidden = false
        tableView.isHidden = true
        emptyImageView.image = UIImage(systemName: "person.2.slash")
        emptyTitleLabel.text = "Couldn't load your network"
        emptySubtitleLabel.text = "Pull down to try again."
        emptySubtitleLabel.isHidden = false
        discoverUsersButton.isHidden = true
    }

    /// Shown when the account is real but the network is empty. This existed
    /// before and was never called, so a new account saw "There are no users in
    /// the system yet" — which reads as the app being broken rather than the
    /// network being new. Now it points at the one useful next step.
    private func showNoConnectionsState() {
        guard !isLoadingData else { return }

        emptyStateView.isHidden = false
        tableView.isHidden = true
        switch listMode {
        case .requests:
            emptyImageView.image = UIImage(systemName: "envelope.open")
            emptyTitleLabel.text = "No requests right now"
            emptySubtitleLabel.text = "Connection requests you send or receive will show up here."
        case .people:
            switch peopleScope {
            case .connections:
                emptyImageView.image = UIImage(systemName: "person.2")
                emptyTitleLabel.text = "No connections yet"
                emptySubtitleLabel.text = "Connect with people you know to unlock messaging and their network-only circles."
            case .following:
                emptyImageView.image = UIImage(systemName: "person.badge.plus")
                emptyTitleLabel.text = "Not following anyone yet"
                emptySubtitleLabel.text = "Follow someone to see the places they save. They don't have to approve it."
            }
        }
        emptySubtitleLabel.isHidden = false
        discoverUsersButton.setTitle("Find people", for: .normal)
        discoverUsersButton.isHidden = false
    }

    private func hideEmptyState() {
        emptyStateView.isHidden = true
        tableView.isHidden = false
        discoverUsersButton.isHidden = true
    }
    
    private func showLoadingState() {
        tableView.isHidden = true
        emptyStateView.isHidden = true
        loadingIndicator.startAnimating()
    }
    
    private func hideLoadingState() {
        loadingIndicator.stopAnimating()
    }
}

// MARK: - UITableViewDataSource
extension AllUsersListViewController: UITableViewDataSource {

    // MARK: Section Model
    //
    // Order encodes urgency. Incoming requests are a task someone else handed
    // you, so they sit first and open. Sent requests sit right below them —
    // they used to live last and collapsed, which buried them so thoroughly
    // people thought their requests had vanished. "Everyone else" is no longer
    // a permanent section at all — strangers belong in Discover, and surface
    // here only when you actually search for them.
    private enum NetworkListSection {
        case requests
        case sent
        case connections
        case following
        case followsYou
        case searchResults
    }

    private var visibleSections: [NetworkListSection] {
        var sections: [NetworkListSection] = []
        switch listMode {
        case .requests:
            // The requests tab: just the in/out requests, nothing else.
            if !filteredPendingIncomingUsers.isEmpty { sections.append(.requests) }
            if !filteredPendingOutgoingUsers.isEmpty { sections.append(.sent) }
        case .people:
            switch peopleScope {
            case .connections:
                if !filteredConnectedUsers.isEmpty { sections.append(.connections) }
            case .following:
                if !filteredFollowingUsers.isEmpty { sections.append(.following) }
                if !filteredFollowsYouUsers.isEmpty { sections.append(.followsYou) }
            }
            if isSearchActive && !filteredNonConnectedUsers.isEmpty { sections.append(.searchResults) }
        }
        return sections
    }

    private func users(for section: NetworkListSection) -> [User] {
        switch section {
        case .requests:
            // Never collapsed. The tab badge already announced these; hiding
            // them behind a chevron is what makes tapping the badge feel broken.
            return filteredPendingIncomingUsers
        case .connections:
            return filteredConnectedUsers
        case .following:
            return filteredFollowingUsers
        case .followsYou:
            return filteredFollowsYouUsers
        case .sent:
            return (isPendingOutgoingExpanded || isSearchActive) ? filteredPendingOutgoingUsers : []
        case .searchResults:
            return filteredNonConnectedUsers
        }
    }

    private func title(for section: NetworkListSection) -> String {
        switch section {
        case .requests:
            let count = filteredPendingIncomingUsers.count
            return count == 1 ? "Wants to connect" : "\(count) want to connect"
        case .connections:
            return "Your connections (\(filteredConnectedUsers.count))"
        case .following:
            return "Following (\(filteredFollowingUsers.count))"
        case .followsYou:
            return "Follows you (\(filteredFollowsYouUsers.count))"
        case .sent:
            return "Sent"
        case .searchResults:
            return "Not in your network"
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        // Don't show sections while loading
        if isLoadingData && !hasLoadedInitialData {
            return 0
        }
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < visibleSections.count else { return 0 }
        return users(for: visibleSections[section]).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // All headers are custom views so they can carry an info button.
        return nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < visibleSections.count else { return nil }
        let listSection = visibleSections[section]

        switch listSection {
        case .sent:
            // The one section still worth collapsing: it is pure status, and
            // most people never act on it.
            return makeCollapsibleHeader(
                title: "SENT",
                count: filteredPendingOutgoingUsers.count,
                color: .secondaryLabel,
                isExpanded: isPendingOutgoingExpanded || isSearchActive,
                action: #selector(togglePendingOutgoingSection)
            )
        case .requests:
            return makeSectionHeader(title: title(for: listSection).uppercased(),
                                     color: Constants.Colors.brightOrange,
                                     showsInfo: false)
        case .connections, .following, .followsYou:
            // These are exactly what the Follow/Connect explainer is about,
            // so each carries the info affordance.
            return makeSectionHeader(title: title(for: listSection).uppercased(),
                                     color: .secondaryLabel,
                                     showsInfo: true)
        case .searchResults:
            return makeSectionHeader(title: title(for: listSection).uppercased(),
                                     color: .secondaryLabel,
                                     showsInfo: false)
        }
    }

    /// Plain section header, optionally with an ⓘ that opens the Follow vs
    /// Connect explainer. One per section rather than one per row: it is a fact
    /// you learn once, and fifty of them down a scroll is just noise.
    private func makeSectionHeader(title: String, color: UIColor, showsInfo: Bool) -> UIView {
        let header = UIView()
        header.backgroundColor = .clear

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            label.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])

        if showsInfo {
            let info = UIButton(type: .system)
            info.setImage(UIImage(systemName: "info.circle"), for: .normal)
            info.tintColor = .tertiaryLabel
            info.accessibilityLabel = "What's the difference between following and connecting?"
            info.addTarget(self, action: #selector(showRelationshipExplainer), for: .touchUpInside)
            info.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(info)

            NSLayoutConstraint.activate([
                info.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
                info.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                info.widthAnchor.constraint(equalToConstant: 22),
                info.heightAnchor.constraint(equalToConstant: 22)
            ])
        }

        return header
    }

    @objc private func showRelationshipExplainer() {
        RelationshipExplainer.present(from: self)
    }

    @objc private func dismissExplainerCard() {
        RelationshipExplainer.markInlineCardSeen()
        guard let header = tableView.tableHeaderView else { return }
        // Collapse the header's height and reassign it so the table reclaims the
        // space (setting tableHeaderView straight to nil leaves a gap the size of
        // the card). The list slides up as it shrinks; remove it when done.
        UIView.animate(withDuration: 0.25, animations: {
            header.alpha = 0
            header.frame.size.height = 0
            self.tableView.tableHeaderView = header
            self.tableView.layoutIfNeeded()
        }, completion: { _ in
            self.tableView.tableHeaderView = nil
        })
    }

    /// Puts the first-run Follow/Connect card at the top of the list, where it
    /// scrolls away with the content instead of permanently occupying the tab.
    func installExplainerCardIfNeeded() {
        // The Follow/Connect explainer belongs with the people list, not the
        // requests tab.
        guard listMode == .people else { return }
        guard let card = RelationshipExplainer.makeInlineCard(
            target: self,
            dismissAction: #selector(dismissExplainerCard),
            infoAction: #selector(showRelationshipExplainer)
        ) else {
            tableView.tableHeaderView = nil
            return
        }

        // A tableHeaderView can't use Auto Layout against the table, so size it
        // once against the current width and wrap it for inset margins.
        let container = UIView()
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : UIScreen.main.bounds.width
        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        container.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = container
    }

    private func makeCollapsibleHeader(title: String, count: Int, color: UIColor, isExpanded: Bool, action: Selector) -> UIView {
        let headerView = UIView()
        headerView.backgroundColor = .clear

        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        var attributedTitle = AttributedString("\(title) (\(count))")
        attributedTitle.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        config.attributedTitle = attributedTitle
        config.image = UIImage(
            systemName: isExpanded ? "chevron.up" : "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.baseForegroundColor = color
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: headerView.topAnchor),
            button.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ])

        return headerView
    }

    @objc private func togglePendingOutgoingSection() {
        isPendingOutgoingExpanded.toggle()
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! AllUsersCell

        guard indexPath.section < visibleSections.count else { return cell }
        let sectionUsers = users(for: visibleSections[indexPath.section])
        guard indexPath.row < sectionUsers.count else { return cell }

        cell.configure(with: sectionUsers[indexPath.row])
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AllUsersListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Self-sizing: the row now stacks a tier chip, stats, and a location
        // line, so a fixed 72 would clip it.
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 84
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Handled by cell buttons
    }
}

// MARK: - AllUsersCellDelegate
extension AllUsersListViewController: AllUsersCellDelegate {

    /// One entry point for every row button. The cell reports what the person
    /// meant; this decides how to carry it out.
    func allUsersCell(_ cell: AllUsersCell, didTap action: RelationshipTier.Action, for user: User) {
        switch action {
        case .follow:      setFollow(true, for: user)
        case .unfollow:    confirmUnfollow(user)
        case .connect:     sendConnectionRequest(to: user)
        case .cancelRequest: confirmCancelRequest(user)
        case .accept:      acceptConnectionRequest(user)
        case .decline:     confirmDecline(user)
        case .message:     openConversation(with: user)
        case .more:        presentMoreMenu(for: user, from: cell)
        }
    }

    func allUsersCell(_ cell: AllUsersCell, didTapProfileImage user: User) {
        viewUserProfile(user)
    }

    private func viewUserProfile(_ user: User) {
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }

    // MARK: - Follow

    /// Follow and unfollow flip the row immediately and reconcile with the
    /// server afterwards. A follow is cheap and reversible, so making someone
    /// watch a spinner for one is a poor trade.
    private func setFollow(_ shouldFollow: Bool, for user: User) {
        applyLocalUpdate(userId: user.id) { $0.copy(isFollowing: shouldFollow) }

        let endpoint = "users/\(user.id)/\(shouldFollow ? "follow" : "unfollow")"
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    // Prefer the server's version of the user when it sends one,
                    // but keep followsYou: the follow endpoint doesn't compute it
                    // and losing it would silently demote a mutual follow.
                    if let updated = response.user {
                        self.applyLocalUpdate(userId: user.id) { current in
                            updated.copy(followsYou: current.followsYou)
                        }
                    }
                case .failure(let error):
                    self.applyLocalUpdate(userId: user.id) { $0.copy(isFollowing: !shouldFollow) }
                    self.showError(error)
                }
            }
        }
    }

    private func confirmUnfollow(_ user: User) {
        AlertPresenter.showConfirmation(
            title: "Unfollow \(user.displayName)?",
            message: "Their places will stop appearing in your feed. You can follow again any time.",
            confirmTitle: "Unfollow",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.setFollow(false, for: user) }
        )
    }

    // MARK: - Connect

    private func sendConnectionRequest(to user: User) {
        // Optimistic: the row becomes "Requested" on tap. This used to raise a
        // modal "Sending Request" alert followed by a second success alert —
        // two dismissals for one tap.
        applyLocalUpdate(userId: user.id) {
            $0.copy(connectionStatus: "pending", connectionDirection: "outgoing")
        }

        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    self.applyLocalUpdate(userId: user.id) {
                        $0.copy(connectionStatus: "none", connectionDirection: nil)
                    }
                    self.showError(error)
                }
            }
        }
    }

    private func acceptConnectionRequest(_ user: User) {
        guard let connectionId = user.connectionId else {
            showError("That request is no longer available. Pull to refresh.")
            return
        }

        applyLocalUpdate(userId: user.id) { $0.copy(connectionStatus: "accepted") }

        NetworkManager.shared.acceptConnection(connectionId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    NetworkManager.shared.refreshBadgeCount()
                    self.loadPeople()
                case .failure(let error):
                    self.applyLocalUpdate(userId: user.id) {
                        $0.copy(connectionStatus: "pending", connectionDirection: "incoming")
                    }
                    self.showError(error)
                }
            }
        }
    }

    private func confirmDecline(_ user: User) {
        AlertPresenter.showConfirmation(
            title: "Decline request?",
            message: "\(user.displayName) won't be told you declined.",
            confirmTitle: "Decline",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.resolveConnection(user, successMessage: nil) }
        )
    }

    private func confirmCancelRequest(_ user: User) {
        AlertPresenter.showConfirmation(
            title: "Cancel request?",
            message: "Withdraw your connection request to \(user.displayName)?",
            confirmTitle: "Cancel Request",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.resolveConnection(user, successMessage: nil) }
        )
    }

    private func confirmDisconnect(_ user: User) {
        AlertPresenter.showConfirmation(
            title: "Disconnect from \(user.displayName)?",
            message: "You'll lose access to each other's network-only circles and can no longer message each other.",
            confirmTitle: "Disconnect",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in self?.resolveConnection(user, successMessage: nil) }
        )
    }

    /// Tears down whichever connection record exists between the two of you —
    /// pending or accepted, in either direction.
    ///
    /// This used to call `loadConnections()` and then guess that 0.5 seconds was
    /// long enough for it to finish before searching the result for an id. On a
    /// slow connection it simply failed with "Could not find the pending
    /// connection request". The id is already on the user model, put there by
    /// the server's connection map, so no lookup is needed at all.
    private func resolveConnection(_ user: User, successMessage: String?) {
        guard let connectionId = user.connectionId else {
            showError("That connection is no longer available. Pull to refresh.")
            return
        }

        NetworkManager.shared.declineConnection(connectionId) { [weak self] (result: Result<Void, Error>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    NetworkManager.shared.refreshBadgeCount()
                    if let message = successMessage {
                        AlertPresenter.showSuccess(message, from: self)
                    }
                    self.loadPeople()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Message

    private func openConversation(with user: User) {
        MessagingManager.shared.createOrGetDirectConversation(with: user.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let conversation):
                    let chatVC = ChatViewController()
                    chatVC.conversation = conversation
                    self.navigationController?.pushViewController(chatVC, animated: true)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Overflow menu

    /// Destructive options live here rather than as a permanent red button on
    /// every row.
    private func presentMoreMenu(for user: User, from cell: AllUsersCell) {
        let tier = RelationshipTier(user: user)
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            ("View Profile", .default, { [weak self] in self?.viewUserProfile(user) })
        ]

        for action in tier.menuActions {
            switch action {
            case .unfollow:
                actions.append(("Unfollow", .destructive, { [weak self] in self?.confirmUnfollow(user) }))
            case .cancelRequest:
                actions.append(("Cancel Request", .destructive, { [weak self] in self?.confirmCancelRequest(user) }))
            case .decline:
                actions.append(("Disconnect", .destructive, { [weak self] in self?.confirmDisconnect(user) }))
            default:
                break
            }
        }

        AlertPresenter.showActionSheet(
            title: user.displayName,
            actions: actions,
            from: self,
            sourceView: cell
        )
    }

    // MARK: - Local state

    /// Applies a change to a person wherever they currently sit, then rebuilds
    /// the sections so they move to the right one.
    private func applyLocalUpdate(userId: String, _ transform: (User) -> User) {
        if let index = allUsers.firstIndex(where: { $0.id == userId }) {
            allUsers[index] = transform(allUsers[index])
        }
        sortAndFilterUsers()
        tableView.reloadData()
    }
}
