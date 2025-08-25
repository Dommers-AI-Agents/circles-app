import UIKit

protocol UserSearchViewControllerDelegate: AnyObject {
    func userSearchViewController(_ controller: UserSearchViewController, didSelectUser user: User)
}

class UserSearchViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: UserSearchViewControllerDelegate?
    var excludedUserIds: [String] = []
    private var searchResults: [User] = []
    private var networkConnections: [User] = []
    private var isSearching = false
    private var searchTimer: Timer?
    private var isLoadingConnections = false
    
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
    
    // MARK: - UI Elements
    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Search by name or username"
        return controller
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.separatorStyle = .singleLine
        table.keyboardDismissMode = .onDrag
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
        imageView.image = UIImage(systemName: "magnifyingglass")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "Your network connections will appear here"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupSearchController()
        setupTableView()
        setupEmptyState()
        loadNetworkConnections()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        title = "Search Users"
        
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        let cancelButton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        navigationItem.leftBarButtonItem = cancelButton
    }
    
    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UserSearchCell.self, forCellReuseIdentifier: "UserSearchCell")
    }
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyLabel)
        
        NSLayoutConstraint.activate([
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 60),
            emptyImageView.heightAnchor.constraint(equalToConstant: 60),
            
            emptyLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
        
        // Don't show empty state initially, wait for connections to load
        hideEmptyState()
    }
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Search
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            tableView.reloadData()
            showEmptyState()
            return
        }
        
        isSearching = true
        activityIndicator.startAnimating()
        hideEmptyState()
        
        APIService.shared.request(
            endpoint: "users/search",
            method: .get,
            queryParams: ["query": query],
            requiresAuth: true
        ) { [weak self] (result: Result<UsersSearchResponse, APIError>) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isSearching = false
                self.activityIndicator.stopAnimating()
                
                switch result {
                case .success(let response):
                    // Filter out excluded users
                    self.searchResults = response.users.filter { user in
                        !(self.excludedUserIds.contains(user.id) ?? false)
                    }
                    self.tableView.reloadData()
                    
                    if self.searchResults.isEmpty ?? true {
                        self.showNoResultsState(for: query)
                    }
                    
                case .failure(let error):
                    print("Search error: \(error)")
                    self.searchResults = []
                    self.tableView.reloadData()
                    self.showErrorState()
                }
            }
        }
    }
    
    // MARK: - Network Connections
    private func loadNetworkConnections() {
        isLoadingConnections = true
        activityIndicator.startAnimating()
        
        NetworkManager.shared.getConnections { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoadingConnections = false
                self.activityIndicator.stopAnimating()
                
                switch result {
                case .success(let connections):
                    // Filter out excluded users and sort alphabetically
                    self.networkConnections = connections
                        .filter { connection in
                            !(self.excludedUserIds.contains(connection.id) ?? false)
                        }
                        .sorted { (user1, user2) in
                            let name1 = self.getDisplayName(for: user1) ?? ""
                            let name2 = self.getDisplayName(for: user2) ?? ""
                            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                        }
                    
                    // Show connections if no search is active
                    if self.searchController.searchBar.text?.isEmpty ?? true {
                        self.searchResults = self.networkConnections ?? []
                        self.tableView.reloadData()
                        
                        if self.searchResults.isEmpty ?? true {
                            self.showEmptyConnectionsState()
                        } else {
                            self.hideEmptyState()
                        }
                    }
                    
                case .failure(let error):
                    print("Failed to load connections: \\(error)")
                    if self.searchController.searchBar.text?.isEmpty ?? true {
                        self.showEmptyState()
                    }
                }
            }
        }
    }
    
    private func getDisplayName(for user: User) -> String {
        return user.displayName
    }
    
    // MARK: - Empty States
    private func showEmptyState() {
        emptyImageView.image = UIImage(systemName: "magnifyingglass")
        emptyLabel.text = "Search for users by name or username"
        emptyStateView.isHidden = false
        tableView.isHidden = true
    }
    
    private func showEmptyConnectionsState() {
        emptyImageView.image = UIImage(systemName: "person.2.slash")
        emptyLabel.text = "No connections available"
        emptyStateView.isHidden = false
        tableView.isHidden = true
    }
    
    override func hideEmptyState() {
        emptyStateView.isHidden = true
        tableView.isHidden = false
    }
    
    private func showNoResultsState(for query: String) {
        emptyImageView.image = UIImage(systemName: "magnifyingglass")
        emptyLabel.text = "No results found for '\(query)'"
        emptyStateView.isHidden = false
        tableView.isHidden = true
    }
    
    private func showErrorState() {
        emptyImageView.image = UIImage(systemName: "exclamationmark.triangle")
        emptyLabel.text = "An error occurred while searching. Please try again."
        emptyStateView.isHidden = false
        tableView.isHidden = true
    }
}

// MARK: - UISearchResultsUpdating
extension UserSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchTimer?.invalidate()
        
        guard let query = searchController.searchBar.text, !query.isEmpty else {
            // Show network connections when search is empty
            searchResults = networkConnections
            tableView.reloadData()
            
            if searchResults.isEmpty {
                showEmptyConnectionsState()
            } else {
                hideEmptyState()
            }
            return
        }
        
        // Debounce search to avoid too many API calls
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.performSearch(query: query)
        }
    }
}

// MARK: - UISearchControllerDelegate
extension UserSearchViewController: UISearchControllerDelegate {
    func willDismissSearchController(_ searchController: UISearchController) {
        searchTimer?.invalidate()
    }
}

// MARK: - UITableViewDataSource
extension UserSearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserSearchCell", for: indexPath) as! UserSearchCell
        let user = searchResults[indexPath.row]
        cell.configure(with: user)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension UserSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = searchResults[indexPath.row]
        delegate?.userSearchViewController(self, didSelectUser: user)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - UserSearchCell
class UserSearchCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = 24
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let userInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let connectionStatusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .systemBlue
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(userInfoLabel)
        contentView.addSubview(connectionStatusLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: connectionStatusLabel.leadingAnchor, constant: -8),
            
            userInfoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            userInfoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            userInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            connectionStatusLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            connectionStatusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    // MARK: - Configure
    func configure(with user: User) {
        // Display only displayName for privacy
        nameLabel.text = user.displayName
        // Display bio instead of email for privacy
        if let bio = user.bio, !bio.isEmpty {
            userInfoLabel.text = bio
        } else if let location = user.location, !location.isEmpty {
            userInfoLabel.text = location
        } else {
            userInfoLabel.text = "Circles member"
        }
        
        // Set profile image
        if let profilePicture = user.profilePicture {
            // Check if it's a default SF Symbol avatar
            if profilePicture.starts(with: "sf-symbol:") {
                let symbolName = String(profilePicture.dropFirst("sf-symbol:".count))
                if let avatarCase = DefaultImages.AvatarDefault.allCases.first(where: { $0.rawValue == symbolName }) {
                    profileImageView.image = avatarCase.image(size: 35)
                    profileImageView.backgroundColor = avatarCase.backgroundColor
                    profileImageView.tintColor = .white
                    profileImageView.contentMode = .scaleAspectFit
                } else {
                    // Fallback to the symbol name directly
                    profileImageView.image = UIImage(systemName: symbolName)
                    profileImageView.tintColor = .systemGray3
                    profileImageView.contentMode = .scaleAspectFit
                }
            } else {
                // Regular image URL
                ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.profileImageView.image = image
                        self.profileImageView.contentMode = .scaleAspectFill
                    }
                }
            }
        } else {
            // Default profile image
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = .systemGray3
            profileImageView.contentMode = .scaleAspectFit
        }
        
        // Set connection status if available
        if let status = user.connectionStatus {
            switch status {
            case "connected":
                connectionStatusLabel.text = "Connected"
                connectionStatusLabel.textColor = .systemGreen
            case "pending":
                connectionStatusLabel.text = "Pending"
                connectionStatusLabel.textColor = .systemOrange
            default:
                connectionStatusLabel.text = ""
            }
        } else {
            connectionStatusLabel.text = ""
        }
    }
}

// MARK: - Response Models
struct UserSearchResponse: Codable {
    let success: Bool
    let count: Int
    let users: [User]
}