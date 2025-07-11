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
    private var nonConnectedUsers: [User] = []
    private var filteredConnectedUsers: [User] = []
    private var filteredPendingIncomingUsers: [User] = []
    private var filteredNonConnectedUsers: [User] = []
    
    private let cellIdentifier = "UserCell"
    private var searchQuery: String = ""
    private var isLoadingData = false
    private var hasLoadedInitialData = false
    private static var hasEverLoadedConnections = false
    private var minimumLoadingTimer: Timer?
    
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
            DispatchQueue.main.async {
                self?.tableView.refreshControl?.endRefreshing()
                
                // Wait for minimum loading time if this is initial load
                let completion = {
                    self?.isLoadingData = false
                    self?.hasLoadedInitialData = true
                    self?.hideLoadingState()
                    
                    switch result {
                    case .success(let users):
                        print("🔍 AllUsersListVC: Received \(users.count) users from server")
                        self?.allUsers = users
                        self?.sortAndFilterUsers()
                        print("🔍 AllUsersListVC: After filtering - Connected: \(self?.connectedUsers.count ?? 0), Pending: \(self?.pendingIncomingUsers.count ?? 0), Others: \(self?.nonConnectedUsers.count ?? 0)")
                        self?.tableView.reloadData()
                        
                        // Track if we've ever had connections
                        if let hasConnections = self?.connectedUsers.isEmpty, !hasConnections {
                            AllUsersListViewController.hasEverLoadedConnections = true
                        }
                        
                        // Only show empty state if we have no users at all
                        if self?.allUsers.isEmpty == true {
                            self?.showEmptyState()
                        } else {
                            self?.hideEmptyState()
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
                        
                        self?.allUsers = []
                        self?.sortAndFilterUsers()
                        self?.tableView.reloadData()
                        
                        // Show error state only if we have no users at all
                        if self?.allUsers.isEmpty == true {
                            self?.showEmptyState()
                        }
                    }
                }
                
                // If minimum loading timer is still active, wait for it
                if let timer = self?.minimumLoadingTimer, timer.isValid {
                    timer.invalidate()
                    self?.minimumLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
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
        
        nonConnectedUsers = allUsers.filter { user in
            (user.connectionStatus != "connected" && user.connectionStatus != "accepted") &&
            !(user.connectionStatus == "pending" && user.connectionDirection == "incoming")
        }
        
        // Sort each group alphabetically
        connectedUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        pendingIncomingUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        nonConnectedUsers.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
        
        // Apply search filter if needed
        filterUsers()
    }
    
    private func filterUsers() {
        if searchQuery.isEmpty {
            filteredConnectedUsers = connectedUsers
            filteredPendingIncomingUsers = pendingIncomingUsers
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
    
    private func sendConnectionRequest(to user: User) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Sending Request", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
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
                        self?.present(successAlert, animated: true)
                        
                        // Reload users to update status
                        self?.loadAllUsers()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
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
            // Show loading
            let loadingAlert = UIAlertController(title: "Canceling...", message: nil, preferredStyle: .alert)
            self?.present(loadingAlert, animated: true)
            
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
                                    self?.present(successAlert, animated: true)
                                    
                                    // Reload users to update status
                                    self?.loadAllUsers()
                                    
                                case .failure(let error):
                                    let errorAlert = UIAlertController(
                                        title: "Error",
                                        message: error.localizedDescription,
                                        preferredStyle: .alert
                                    )
                                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self?.present(errorAlert, animated: true)
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
                        self?.present(errorAlert, animated: true)
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
            // Show loading
            let loadingAlert = UIAlertController(title: "Removing...", message: nil, preferredStyle: .alert)
            self?.present(loadingAlert, animated: true)
            
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
                                    self?.present(errorAlert, animated: true)
                                } else {
                                    let successAlert = UIAlertController(
                                        title: "Connection Removed",
                                        message: "You are no longer connected with \(user.displayName).",
                                        preferredStyle: .alert
                                    )
                                    successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self?.present(successAlert, animated: true)
                                    
                                    // Reload users to update status
                                    self?.loadAllUsers()
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
                        self?.present(errorAlert, animated: true)
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
        
        NetworkManager.shared.acceptConnection(connectionId) { [weak self] (result: Result<Connection, Error>) in
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
                        self?.present(successAlert, animated: true)
                        
                        // Reload users to update status
                        self?.loadAllUsers()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
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
            // Show loading
            let loadingAlert = UIAlertController(title: "Declining...", message: nil, preferredStyle: .alert)
            self?.present(loadingAlert, animated: true)
            
            NetworkManager.shared.declineConnection(connectionId) { (result: Result<Void, Error>) in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success:
                            // Reload users to update status
                            self?.loadAllUsers()
                            
                        case .failure(let error):
                            let errorAlert = UIAlertController(
                                title: "Error",
                                message: error.localizedDescription,
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self?.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - AllUsersCell
protocol AllUsersCellDelegate: AnyObject {
    func allUsersCell(_ cell: AllUsersCell, didTapActionButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapRemoveButton user: User)
    func allUsersCell(_ cell: AllUsersCell, didTapDeclineButton user: User)
}

class AllUsersCell: UITableViewCell {
    weak var delegate: AllUsersCellDelegate?
    private var user: User?
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let highlightView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.setTitleColor(.systemRed, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let declineButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Decline", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.setTitleColor(.systemRed, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = .systemBackground
        selectionStyle = .none
        
        contentView.addSubview(highlightView)
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(actionButton)
        contentView.addSubview(removeButton)
        contentView.addSubview(declineButton)
        
        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            highlightView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -8),
            
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            emailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -8),
            
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.widthAnchor.constraint(equalToConstant: 70),
            removeButton.heightAnchor.constraint(equalToConstant: 32),
            
            declineButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            declineButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            declineButton.widthAnchor.constraint(equalToConstant: 70),
            declineButton.heightAnchor.constraint(equalToConstant: 32),
            
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            actionButton.widthAnchor.constraint(equalToConstant: 60),
            actionButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineButtonTapped), for: .touchUpInside)
    }
    
    func configure(with user: User) {
        self.user = user
        nameLabel.text = user.displayName
        emailLabel.text = user.email
        
        // Check if this is a newly accepted connection
        let newlyAcceptedId = UserDefaults.standard.string(forKey: "newlyAcceptedConnectionId")
        let isNewlyAccepted = newlyAcceptedId == user.id
        highlightView.isHidden = !isNewlyAccepted
        
        // Set profile image
        if let profilePicture = user.profilePicture {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = .systemGray3
        }
        
        // Configure action button based on connection status
        switch user.connectionStatus {
        case "connected", "accepted":
            actionButton.setTitle("View", for: .normal)
            actionButton.backgroundColor = Constants.Colors.primary
            actionButton.setTitleColor(.white, for: .normal)
            actionButton.isEnabled = true
            removeButton.isHidden = false
            declineButton.isHidden = true
            // Normal background for connected users
            contentView.backgroundColor = .systemBackground
        case "pending":
            if user.connectionDirection == "incoming" {
                // Show Accept and Decline buttons for incoming requests
                actionButton.setTitle("Accept", for: .normal)
                actionButton.backgroundColor = .systemGreen
                actionButton.setTitleColor(.white, for: .normal)
                actionButton.isEnabled = true
                removeButton.isHidden = true
                declineButton.isHidden = false
                // Highlight pending incoming requests
                contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
            } else {
                // Show Cancel for outgoing requests
                actionButton.setTitle("Cancel", for: .normal)
                actionButton.backgroundColor = .systemRed.withAlphaComponent(0.1)
                actionButton.setTitleColor(.systemRed, for: .normal)
                actionButton.isEnabled = true
                removeButton.isHidden = true
                declineButton.isHidden = true
                // Normal background for outgoing requests
                contentView.backgroundColor = .systemBackground
            }
        default:
            actionButton.setTitle("Connect", for: .normal)
            actionButton.backgroundColor = Constants.Colors.primary
            actionButton.setTitleColor(.white, for: .normal)
            actionButton.isEnabled = true
            removeButton.isHidden = true
            declineButton.isHidden = true
            // Normal background for non-connected users
            contentView.backgroundColor = .systemBackground
        }
    }
    
    @objc private func actionButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapActionButton: user)
    }
    
    @objc private func removeButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapRemoveButton: user)
    }
    
    @objc private func declineButtonTapped() {
        guard let user = user else { return }
        delegate?.allUsersCell(self, didTapDeclineButton: user)
    }
}