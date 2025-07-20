import UIKit

class FollowersListViewController: BaseViewController {
    
    // MARK: - Properties
    var userId: String?
    var listType: FollowListType = .followers
    private var users: [User] = []
    private var filteredUsers: [User] = []
    private var isSearching = false
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = Constants.Colors.background
        return tableView
    }()
    
    private let searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search users"
        return searchController
    }()
    
    // Loading indicator removed - using BaseViewController's built-in indicator
    
    // Empty state label removed - using BaseViewController's built-in empty state
    
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
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { 
        if listType == .followers {
            return "No followers yet\n\nWhen people follow you, they'll appear here."
        } else {
            return "Not following anyone\n\nFind people to follow and they'll appear here."
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchController()
        setupSSEListener()
    }
    
    override func loadData(completion: (() -> Void)?) {
        loadUsers()
        completion?()
    }
    
    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }
    
    deinit {
        SSEService.shared.removeDelegate(self)
    }
    
    // MARK: - Setup
    private func setupUI() {
        setupNavigationBar(title: listType == .followers ? "Followers" : "Following")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FollowerUserCell.self, forCellReuseIdentifier: "FollowerUserCell")
    }
    
    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupSSEListener() {
        SSEService.shared.addDelegate(self)
    }
    
    // MARK: - Data Loading
    private func loadUsers() {
        guard let userId = userId else { return }
        
        if listType == .followers {
            loadFollowers(userId: userId)
        } else {
            loadFollowing(userId: userId)
        }
    }
    
    private func loadFollowers(userId: String) {
        APIService.shared.request(
            endpoint: "users/\(userId)/followers",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowersResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.users = response.followers
                    self.filteredUsers = response.followers
                    self.tableView.reloadData()
                    self.updateEmptyState()
                case .failure(let error):
                    self.showError("Failed to load followers: \(error.localizedDescription)")
                    self.updateEmptyState()
                }
            }
        }
    }
    
    private func loadFollowing(userId: String) {
        APIService.shared.request(
            endpoint: "users/\(userId)/following",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowingResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.users = response.following
                    self.filteredUsers = response.following
                    self.tableView.reloadData()
                    self.updateEmptyState()
                case .failure(let error):
                    self.showError("Failed to load following: \(error.localizedDescription)")
                    self.updateEmptyState()
                }
            }
        }
    }
    
    private func updateEmptyState() {
        let isEmpty = isSearching ? filteredUsers.isEmpty : users.isEmpty
        
        if isEmpty {
            if isSearching {
                showEmptyState(message: "No users found")
            } else {
                showEmptyState()
            }
        } else {
            hideEmptyState()
        }
    }
    
    // Removed - using BaseViewController's showError method
}

// MARK: - UITableViewDataSource
extension FollowersListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filteredUsers.count : users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FollowerUserCell", for: indexPath) as! FollowerUserCell
        let user = isSearching ? filteredUsers[indexPath.row] : users[indexPath.row]
        cell.configure(with: user, listType: listType)
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension FollowersListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = isSearching ? filteredUsers[indexPath.row] : users[indexPath.row]
        
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - UISearchResultsUpdating
extension FollowersListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.lowercased(), !searchText.isEmpty else {
            isSearching = false
            filteredUsers = users
            tableView.reloadData()
            updateEmptyState()
            return
        }
        
        isSearching = true
        filteredUsers = users.filter { user in
            let displayName = user.displayName.lowercased()
            let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".lowercased()
            return displayName.contains(searchText) || fullName.contains(searchText)
        }
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - UISearchControllerDelegate
extension FollowersListViewController: UISearchControllerDelegate {
    func willDismissSearchController(_ searchController: UISearchController) {
        isSearching = false
        filteredUsers = users
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - SSEServiceDelegate
extension FollowersListViewController: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        switch event.type {
        case .followerAdded, .followerRemoved:
            if listType == .followers {
                // Reload the followers list
                loadUsers()
            }
        case .followingAdded, .followingRemoved:
            if listType == .following {
                // Reload the following list
                loadUsers()
            }
        default:
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
    }
}

// MARK: - FollowerUserCellDelegate
extension FollowersListViewController: FollowerUserCellDelegate {
    func didTapFollowButton(for user: User, isFollowing: Bool) {
        let endpoint = isFollowing ? "users/\(user.id)/unfollow" : "users/\(user.id)/follow"
        
        // Find the cell to revert state if API call fails
        var cellToUpdate: FollowerUserCell?
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            if let cell = tableView.cellForRow(at: indexPath) as? FollowerUserCell,
               let cellUser = cell.user,
               cellUser.id == user.id {
                cellToUpdate = cell
                break
            }
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success:
                    // Update will happen via SSE
                    // Update the user in our local array
                    if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                        self.users[index] = user.copy(isFollowing: !isFollowing)
                    }
                    if let index = self.filteredUsers.firstIndex(where: { $0.id == user.id }) {
                        self.filteredUsers[index] = user.copy(isFollowing: !isFollowing)
                    }
                case .failure(let error):
                    // Revert the cell state on failure
                    cellToUpdate?.setFollowingState(!isFollowing)
                    self.showError("Failed to \(isFollowing ? "unfollow" : "follow") user: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func didTapViewButton(for user: User) {
        // Navigate to user profile
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - Response Model
struct UsersListResponse: Codable {
    let success: Bool
    let users: [User]
}

struct FollowersResponse: Codable {
    let success: Bool
    let count: Int
    let followers: [User]
}

struct FollowingResponse: Codable {
    let success: Bool
    let count: Int
    let following: [User]
}


// MARK: - Follower User Cell
protocol FollowerUserCellDelegate: AnyObject {
    func didTapFollowButton(for user: User, isFollowing: Bool)
    func didTapViewButton(for user: User)
}

class FollowerUserCell: UITableViewCell {
    
    // MARK: - Properties
    weak var delegate: FollowerUserCellDelegate?
    private(set) var user: User?
    private var isFollowing = false
    private var currentListType: FollowListType?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 25
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var followButton = UIButton.smallActionButton(title: "Follow", style: .secondary)
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .default
        
        contentView.addSubview(containerView)
        containerView.addSubview(profileImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(usernameLabel)
        containerView.addSubview(followButton)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -12),
            
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            usernameLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            usernameLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -12),
            
            followButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            followButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            followButton.widthAnchor.constraint(equalToConstant: 100),
            followButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Initial setup - will be updated in configure method based on follow status
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Configuration
    func configure(with user: User, listType: FollowListType) {
        self.user = user
        self.currentListType = listType
        
        // Set user info
        if let firstName = user.firstName, let lastName = user.lastName {
            nameLabel.text = "\(firstName) \(lastName)"
        } else {
            nameLabel.text = user.displayName
        }
        usernameLabel.text = "@\(user.displayName)"
        
        // Load profile image
        if let profilePicture = user.profilePicture {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
        
        // Check follow status - for following list, always show as following
        if listType == .following {
            isFollowing = true
        } else {
            isFollowing = user.isFollowing ?? false
        }
        updateFollowButton(listType: listType)
        
        // Hide follow button for current user
        if user.id == AuthService.shared.getUserId() {
            followButton.isHidden = true
        } else {
            followButton.isHidden = false
        }
    }
    
    private func checkFollowStatus() {
        // Use the isFollowing field from the user model
        isFollowing = user?.isFollowing ?? false
        updateFollowButton()
    }
    
    private func updateFollowButton(listType: FollowListType? = nil) {
        if isFollowing {
            if listType == .following {
                // In following list, show "Following" button that can unfollow
                followButton.setTitle("Following", for: .normal)
                followButton.setStyle(.primary)
                followButton.removeTarget(self, action: #selector(viewButtonTapped), for: .touchUpInside)
                followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
            } else {
                // In followers list, show "View" button to view profile
                followButton.setTitle("View", for: .normal)
                followButton.setStyle(.secondary)
                followButton.removeTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
                followButton.addTarget(self, action: #selector(viewButtonTapped), for: .touchUpInside)
            }
        } else {
            // Not following - show "Follow" button
            followButton.setTitle("Follow", for: .normal)
            followButton.setStyle(.secondary)
            followButton.removeTarget(self, action: #selector(viewButtonTapped), for: .touchUpInside)
            followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        }
    }
    
    // Public method to set following state (used for reverting on API failure)
    func setFollowingState(_ following: Bool) {
        isFollowing = following
        updateFollowButton(listType: currentListType)
    }
    
    // MARK: - Actions
    @objc private func followButtonTapped() {
        guard let user = user else { return }
        
        // Toggle the state immediately for better UX
        isFollowing.toggle()
        updateFollowButton(listType: currentListType)
        
        // Notify delegate with the previous state (before toggle)
        delegate?.didTapFollowButton(for: user, isFollowing: !isFollowing)
    }
    
    @objc private func viewButtonTapped() {
        guard let user = user else { return }
        delegate?.didTapViewButton(for: user)
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = nil
        nameLabel.text = nil
        usernameLabel.text = nil
        user = nil
        isFollowing = false
        followButton.isHidden = false
        // Reset button to default state
        followButton.removeTarget(nil, action: nil, for: .allEvents)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        followButton.setTitle("Follow", for: .normal)
        followButton.setStyle(.secondary)
    }
}