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
    
    // MARK: - Properties
    private var allUsers: [User] = []
    private var connectedUsers: [User] = []
    private var pendingIncomingUsers: [User] = []
    private var pendingOutgoingUsers: [User] = []
    private var nonConnectedUsers: [User] = []
    private var filteredConnectedUsers: [User] = []
    private var filteredPendingIncomingUsers: [User] = []
    private var filteredPendingOutgoingUsers: [User] = []
    private var filteredNonConnectedUsers: [User] = []
    
    private let cellIdentifier = "UserCell"
    private var searchQuery: String = ""
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
        
        loadAllUsers()
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
            loadAllUsers()
        }
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
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
            emptySubtitleLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    func loadAllUsers() {
        // Show loading indicator only on initial load
        if !hasLoadedInitialData && !isLoadingData {
            showLoadingState()
            
            // Start minimum loading timer to prevent jarring transitions
            minimumLoadingTimer?.invalidate()
            minimumLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                // Timer will be checked when data loads
            }
        }
        
        isLoadingData = true
        
        // Load all users (empty query returns all)
        UserService.shared.searchUsers(query: "") { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.tableView.refreshControl?.endRefreshing()
                
                // Wait for minimum loading time if this is initial load
                let completion = {
                    self.isLoadingData = false
                    self.hasLoadedInitialData = true
                    self.hideLoadingState()
                    
                    switch result {
                    case .success(let users):
                        print("🔍 AllUsersListVC: Received \(users.count) users from server")
                        self.allUsers = users
                        self.sortAndFilterUsers()
                        print("🔍 AllUsersListVC: After filtering - Connected: \(self.connectedUsers.count ?? 0), Pending: \(self.pendingIncomingUsers.count ?? 0), Others: \(self.nonConnectedUsers.count ?? 0)")
                        self.tableView.reloadData()
                        
                        // Track if we've ever had connections
                        if !self.connectedUsers.isEmpty {
                            AllUsersListViewController.hasEverLoadedConnections = true
                        }
                        
                        // Only show empty state if we have no users at all
                        if self.allUsers.isEmpty == true {
                            self.showEmptyState()
                        } else {
                            self.hideEmptyState()
                        }
                        
                    case .failure(let error):
                        print("Failed to load users: \(error)")
                        
                        // Check if it's a duplicate request error
                        if case .duplicateRequest = error as? APIError {
                            // Don't show empty state for duplicate requests
                            // Keep the loading state active - the other request will complete
                            print("Ignoring duplicate request error - keeping loading state")
                            // Don't update any state, just return
                            return
                        }
                        
                        self.allUsers = []
                        self.sortAndFilterUsers()
                        self.tableView.reloadData()
                        
                        // Show error state only if we have no users at all
                        if self.allUsers.isEmpty == true {
                            self.showEmptyState()
                        }
                    }
                }
                
                // If minimum loading timer is still active, wait for it
                if let timer = self.minimumLoadingTimer, timer.isValid {
                    timer.invalidate()
                    self.minimumLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                        completion()
                    }
                } else {
                    completion()
                }
            }
        }
    }
    
    private func sortAndFilterUsers() {
        // Separate users by connection status
        connectedUsers = allUsers.filter { user in
            user.connectionStatus == "connected" || user.connectionStatus == "accepted"
        }
        
        pendingIncomingUsers = allUsers.filter { user in
            user.connectionStatus == "pending" && user.connectionDirection == "incoming"
        }
        
        pendingOutgoingUsers = allUsers.filter { user in
            user.connectionStatus == "pending" && user.connectionDirection == "outgoing"
        }
        
        nonConnectedUsers = allUsers.filter { user in
            (user.connectionStatus != "connected" && user.connectionStatus != "accepted") &&
            !(user.connectionStatus == "pending" && user.connectionDirection == "incoming") &&
            !(user.connectionStatus == "pending" && user.connectionDirection == "outgoing")
        }
        
        // Sort each group alphabetically
        connectedUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        pendingIncomingUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        pendingOutgoingUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        nonConnectedUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        
        // Apply search filter if needed
        filterUsers()
    }
    
    private func filterUsers() {
        if searchQuery.isEmpty {
            filteredConnectedUsers = connectedUsers
            filteredPendingIncomingUsers = pendingIncomingUsers
            filteredPendingOutgoingUsers = pendingOutgoingUsers
            filteredNonConnectedUsers = nonConnectedUsers
        } else {
            let query = searchQuery.lowercased()
            
            filteredConnectedUsers = connectedUsers.filter { user in
                user.displayName.lowercased().contains(query) ||
                user.email.lowercased().contains(query)
            }
            
            filteredPendingIncomingUsers = pendingIncomingUsers.filter { user in
                user.displayName.lowercased().contains(query) ||
                user.email.lowercased().contains(query)
            }
            
            filteredPendingOutgoingUsers = pendingOutgoingUsers.filter { user in
                user.displayName.lowercased().contains(query) ||
                user.email.lowercased().contains(query)
            }
            
            filteredNonConnectedUsers = nonConnectedUsers.filter { user in
                user.displayName.lowercased().contains(query) ||
                user.email.lowercased().contains(query)
            }
        }
    }
    
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        filterUsers()
        tableView.reloadData()
    }
    
    @objc private func refreshUsers() {
        loadAllUsers()
    }
    
    // MARK: - Empty State
    private func showEmptyState() {
        // Never show empty state while loading
        guard !isLoadingData else { return }
        
        emptyStateView.isHidden = false
        tableView.isHidden = true
        emptyImageView.image = UIImage(systemName: "person.2.slash")
        emptyTitleLabel.text = "No Users Found"
        emptySubtitleLabel.text = "There are no users in the system yet."
        emptySubtitleLabel.isHidden = false
    }
    
    private func showNoConnectionsState() {
        // Never show empty state while loading
        guard !isLoadingData else { return }
        
        emptyStateView.isHidden = false
        tableView.isHidden = true
        emptyImageView.image = UIImage(systemName: "person.2.badge.gearshape")
        emptyTitleLabel.text = "No Connections Yet"
        emptySubtitleLabel.text = "Start building your network by inviting people to connect with you."
        emptySubtitleLabel.isHidden = false
    }
    
    private func hideEmptyState() {
        emptyStateView.isHidden = true
        tableView.isHidden = false
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
    func numberOfSections(in tableView: UITableView) -> Int {
        // Don't show sections while loading
        if isLoadingData && !hasLoadedInitialData {
            return 0
        }
        
        var sections = 0
        if !filteredPendingIncomingUsers.isEmpty { sections += 1 }
        if !filteredPendingOutgoingUsers.isEmpty { sections += 1 }
        if !filteredConnectedUsers.isEmpty { sections += 1 }
        if !filteredNonConnectedUsers.isEmpty { sections += 1 }
        return sections
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Determine which section this is based on what's visible
        var currentSection = 0
        
        if !filteredPendingIncomingUsers.isEmpty {
            if section == currentSection {
                return filteredPendingIncomingUsers.count
            }
            currentSection += 1
        }
        
        if !filteredPendingOutgoingUsers.isEmpty {
            if section == currentSection {
                return filteredPendingOutgoingUsers.count
            }
            currentSection += 1
        }
        
        if !filteredConnectedUsers.isEmpty {
            if section == currentSection {
                return filteredConnectedUsers.count
            }
            currentSection += 1
        }
        
        return filteredNonConnectedUsers.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // Determine which section this is based on what's visible
        var currentSection = 0
        
        if !filteredPendingIncomingUsers.isEmpty {
            if section == currentSection {
                return "Pending Requests"
            }
            currentSection += 1
        }
        
        if !filteredPendingOutgoingUsers.isEmpty {
            if section == currentSection {
                return "Connection Requests Pending"
            }
            currentSection += 1
        }
        
        if !filteredConnectedUsers.isEmpty {
            if section == currentSection {
                return "Your Connections"
            }
            currentSection += 1
        }
        
        return "Other Users"
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! AllUsersCell
        
        let user: User
        var currentSection = 0
        
        if !filteredPendingIncomingUsers.isEmpty {
            if indexPath.section == currentSection {
                user = filteredPendingIncomingUsers[indexPath.row]
                cell.configure(with: user)
                cell.delegate = self
                return cell
            }
            currentSection += 1
        }
        
        if !filteredPendingOutgoingUsers.isEmpty {
            if indexPath.section == currentSection {
                user = filteredPendingOutgoingUsers[indexPath.row]
                cell.configure(with: user)
                cell.delegate = self
                return cell
            }
            currentSection += 1
        }
        
        if !filteredConnectedUsers.isEmpty {
            if indexPath.section == currentSection {
                user = filteredConnectedUsers[indexPath.row]
                cell.configure(with: user)
                cell.delegate = self
                return cell
            }
            currentSection += 1
        }
        
        user = filteredNonConnectedUsers[indexPath.row]
        cell.configure(with: user)
        cell.delegate = self
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AllUsersListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Handled by cell buttons
    }
}

// MARK: - AllUsersCellDelegate
extension AllUsersListViewController: AllUsersCellDelegate {
    func allUsersCell(_ cell: AllUsersCell, didTapActionButton user: User) {
        switch user.connectionStatus {
        case "connected", "accepted":
            viewUserProfile(user)
        case "pending":
            if user.connectionDirection == "incoming" {
                // Accept the incoming request
                acceptConnectionRequest(user)
            } else {
                // Cancel outgoing request
                cancelConnectionRequest(with: user)
            }
        default:
            sendConnectionRequest(to: user)
        }
    }
    
    func allUsersCell(_ cell: AllUsersCell, didTapRemoveButton user: User) {
        removeConnection(with: user)
    }
    
    private func viewUserProfile(_ user: User) {
        // Navigate to profile view
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    private func updateUserFollowStatus(userId: String, isFollowing: Bool) {
        // Update in all user arrays
        if let index = allUsers.firstIndex(where: { $0.id == userId }) {
            allUsers[index] = createUpdatedUser(from: allUsers[index], isFollowing: isFollowing)
        }
        
        if let index = pendingIncomingUsers.firstIndex(where: { $0.id == userId }) {
            pendingIncomingUsers[index] = createUpdatedUser(from: pendingIncomingUsers[index], isFollowing: isFollowing)
        }
        
        if let index = pendingOutgoingUsers.firstIndex(where: { $0.id == userId }) {
            pendingOutgoingUsers[index] = createUpdatedUser(from: pendingOutgoingUsers[index], isFollowing: isFollowing)
        }
        
        if let index = connectedUsers.firstIndex(where: { $0.id == userId }) {
            connectedUsers[index] = createUpdatedUser(from: connectedUsers[index], isFollowing: isFollowing)
        }
        
        if let index = nonConnectedUsers.firstIndex(where: { $0.id == userId }) {
            nonConnectedUsers[index] = createUpdatedUser(from: nonConnectedUsers[index], isFollowing: isFollowing)
        }
        
        // Refresh the table view to update the UI
        filterUsers()
        tableView.reloadData()
    }
    
    private func updateUserWithServerData(userId: String, updatedUser: User) {
        // Update in all user arrays with server data
        if let index = allUsers.firstIndex(where: { $0.id == userId }) {
            allUsers[index] = updatedUser
        }
        
        if let index = pendingIncomingUsers.firstIndex(where: { $0.id == userId }) {
            pendingIncomingUsers[index] = updatedUser
        }
        
        if let index = pendingOutgoingUsers.firstIndex(where: { $0.id == userId }) {
            pendingOutgoingUsers[index] = updatedUser
        }
        
        if let index = connectedUsers.firstIndex(where: { $0.id == userId }) {
            connectedUsers[index] = updatedUser
        }
        
        if let index = nonConnectedUsers.firstIndex(where: { $0.id == userId }) {
            nonConnectedUsers[index] = updatedUser
        }
        
        // Refresh the table view to update the UI
        filterUsers()
        tableView.reloadData()
    }
    
    private func createUpdatedUser(from user: User, isFollowing: Bool) -> User {
        return user.copy(isFollowing: isFollowing)
    }
    
    private func sendConnectionRequest(to user: User) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Sending Request", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        let successAlert = UIAlertController(
                            title: "Request Sent",
                            message: "Connection request sent to \(user.displayName)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(successAlert, animated: true)
                        
                        // Reload users to update status
                        self.loadAllUsers()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    private func cancelConnectionRequest(with user: User) {
        let alert = UIAlertController(
            title: "Cancel Request",
            message: "Cancel connection request to \(user.displayName)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel Request", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            // Show loading
            let loadingAlert = UIAlertController(title: "Canceling...", message: nil, preferredStyle: .alert)
            self.present(loadingAlert, animated: true)
            
            // Find the pending connection and cancel it
            NetworkManager.shared.loadConnections()
            
            // Wait for connections to load then find the pending one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let pendingConnection = NetworkManager.shared.pendingConnections.first(where: { 
                    $0.connectedUserId == user.id || $0.userId == user.id 
                }) {
                    NetworkManager.shared.declineConnection(pendingConnection.id) { result in
                        DispatchQueue.main.async {
                            loadingAlert.dismiss(animated: true) {
                                switch result {
                                case .success:
                                    let successAlert = UIAlertController(
                                        title: "Request Canceled",
                                        message: "Connection request has been canceled.",
                                        preferredStyle: .alert
                                    )
                                    successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(successAlert, animated: true)
                                    
                                    // Reload users to update status
                                    self.loadAllUsers()
                                    
                                case .failure(let error):
                                    let errorAlert = UIAlertController(
                                        title: "Error",
                                        message: error.localizedDescription,
                                        preferredStyle: .alert
                                    )
                                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(errorAlert, animated: true)
                                }
                            }
                        }
                    }
                } else {
                    loadingAlert.dismiss(animated: true) {
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Could not find the pending connection request.",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Keep Request", style: .cancel))
        present(alert, animated: true)
    }
    
    private func removeConnection(with user: User) {
        let alert = UIAlertController(
            title: "Remove Connection",
            message: "Are you sure you want to remove \(user.displayName) from your connections?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            // Show loading
            let loadingAlert = UIAlertController(title: "Removing...", message: nil, preferredStyle: .alert)
            self.present(loadingAlert, animated: true)
            
            // Find the connection to remove
            NetworkManager.shared.loadConnections()
            
            // Wait for connections to load then find the one to remove
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let connection = NetworkManager.shared.connections.first(where: { 
                    $0.connectedUserId == user.id || $0.userId == user.id 
                }) {
                    NetworkManager.shared.removeConnection(connectionId: connection.id) { error in
                        DispatchQueue.main.async {
                            loadingAlert.dismiss(animated: true) {
                                if let error = error {
                                    let errorAlert = UIAlertController(
                                        title: "Error",
                                        message: error.localizedDescription,
                                        preferredStyle: .alert
                                    )
                                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(errorAlert, animated: true)
                                } else {
                                    let successAlert = UIAlertController(
                                        title: "Connection Removed",
                                        message: "You are no longer connected with \(user.displayName).",
                                        preferredStyle: .alert
                                    )
                                    successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(successAlert, animated: true)
                                    
                                    // Reload users to update status
                                    self.loadAllUsers()
                                }
                            }
                        }
                    }
                } else {
                    loadingAlert.dismiss(animated: true) {
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Could not find the connection to remove.",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func acceptConnectionRequest(_ user: User) {
        guard let connectionId = user.connectionId else {
            print("No connection ID for incoming request")
            return
        }
        
        // Show loading
        let loadingAlert = UIAlertController(title: "Accepting...", message: nil, preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        NetworkManager.shared.acceptConnection(connectionId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        let successAlert = UIAlertController(
                            title: "Connection Accepted",
                            message: "You are now connected with \(user.displayName)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(successAlert, animated: true)
                        
                        // Reload users to update status
                        self.loadAllUsers()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    func allUsersCell(_ cell: AllUsersCell, didTapDeclineButton user: User) {
        guard let connectionId = user.connectionId else {
            print("No connection ID for incoming request")
            return
        }
        
        let alert = UIAlertController(
            title: "Decline Request",
            message: "Decline connection request from \(user.displayName)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Decline", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            // Show loading
            let loadingAlert = UIAlertController(title: "Declining...", message: nil, preferredStyle: .alert)
            self.present(loadingAlert, animated: true)
            
            NetworkManager.shared.declineConnection(connectionId) { (result: Result<Void, Error>) in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success:
                            // Reload users to update status
                            self.loadAllUsers()
                            
                        case .failure(let error):
                            let errorAlert = UIAlertController(
                                title: "Error",
                                message: error.localizedDescription,
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func allUsersCell(_ cell: AllUsersCell, didTapFollowButton user: User) {
        let isCurrentlyFollowing = user.isFollowing ?? false
        let action = isCurrentlyFollowing ? "unfollow" : "follow"
        let endpoint = "users/\(user.id)/\(action)"
        
        print("🔵 Follow button tapped - Action: \(action), User: \(user.displayName)")
        
        // Optimistically update the UI
        updateUserFollowStatus(userId: user.id, isFollowing: !isCurrentlyFollowing)
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    print("✅ Successfully \(action)ed user: \(user.displayName)")
                    
                    // Use the server response to update user data instead of optimistic update
                    if let updatedUser = response.user {
                        // Update the user with the server response data
                        self.updateUserWithServerData(userId: user.id, updatedUser: updatedUser)
                    }
                    // If no user data in response, keep the optimistic update
                    
                case .failure(let error):
                    print("❌ Failed to \(action) user: \(error)")
                    // Revert the optimistic update
                    self.updateUserFollowStatus(userId: user.id, isFollowing: isCurrentlyFollowing)
                    
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to \(action) user: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    func allUsersCell(_ cell: AllUsersCell, didTapProfileImage user: User) {
        // Navigate to user profile
        viewUserProfile(user)
    }
}
