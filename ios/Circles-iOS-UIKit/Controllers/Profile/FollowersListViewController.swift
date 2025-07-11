import UIKit

class FollowersListViewController: UIViewController {
    
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
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = Constants.Colors.secondaryLabel
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchController()
        setupSSEListener()
        loadUsers()
    }
    
    deinit {
        SSEService.shared.removeDelegate(self)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = listType == .followers ? "Followers" : "Following"
        
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
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
        
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        emptyStateLabel.isHidden = true
        
        let endpoint = listType == .followers ? "users/\(userId)/followers" : "users/\(userId)/following"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UsersListResponse, APIError>) in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()
                self?.tableView.isHidden = false
                
                switch result {
                case .success(let response):
                    self?.users = response.users
                    self?.filteredUsers = response.users
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    self?.showAlert(title: "Error", message: "Failed to load users: \(error.localizedDescription)")
                    self?.updateEmptyState()
                }
            }
        }
    }
    
    private func updateEmptyState() {
        let isEmpty = isSearching ? filteredUsers.isEmpty : users.isEmpty
        emptyStateLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        
        if isEmpty {
            if isSearching {
                emptyStateLabel.text = "No users found"
            } else if listType == .followers {
                emptyStateLabel.text = "No followers yet\n\nWhen people follow you, they'll appear here."
            } else {
                emptyStateLabel.text = "Not following anyone\n\nFind people to follow and they'll appear here."
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension FollowersListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filteredUsers.count : users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FollowerUserCell", for: indexPath) as! FollowerUserCell
        let user = isSearching ? filteredUsers[indexPath.row] : users[indexPath.row]
        cell.configure(with: user)
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
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update will happen via SSE
                    break
                case .failure(let error):
                    self?.showAlert(title: "Error", message: "Failed to \(isFollowing ? "unfollow" : "follow") user: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Response Model
struct UsersListResponse: Codable {
    let success: Bool
    let users: [User]
}

// MARK: - Follower User Cell
protocol FollowerUserCellDelegate: AnyObject {
    func didTapFollowButton(for user: User, isFollowing: Bool)
}

class FollowerUserCell: UITableViewCell {
    
    // MARK: - Properties
    weak var delegate: FollowerUserCellDelegate?
    private var user: User?
    private var isFollowing = false
    
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
    
    private let followButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
        
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Configuration
    func configure(with user: User) {
        self.user = user
        
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
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
        
        // Check follow status (this would need to be implemented)
        checkFollowStatus()
        
        // Hide follow button for current user
        if user.id == AuthService.shared.getUserId() {
            followButton.isHidden = true
        } else {
            followButton.isHidden = false
        }
    }
    
    private func checkFollowStatus() {
        // For now, default to not following
        // This would need to check current user's following list
        isFollowing = false
        updateFollowButton()
    }
    
    private func updateFollowButton() {
        if isFollowing {
            followButton.setTitle("Following", for: .normal)
            followButton.backgroundColor = Constants.Colors.primary
            followButton.setTitleColor(.white, for: .normal)
            followButton.layer.borderWidth = 0
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.backgroundColor = .clear
            followButton.setTitleColor(Constants.Colors.primary, for: .normal)
            followButton.layer.borderWidth = 1
            followButton.layer.borderColor = Constants.Colors.primary.cgColor
        }
    }
    
    // MARK: - Actions
    @objc private func followButtonTapped() {
        guard let user = user else { return }
        delegate?.didTapFollowButton(for: user, isFollowing: isFollowing)
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
    }
}