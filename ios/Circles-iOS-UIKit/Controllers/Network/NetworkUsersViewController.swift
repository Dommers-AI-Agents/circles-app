import UIKit

class NetworkUsersViewController: BaseViewController {
    
    // MARK: - Properties
    private var usersWithCircles: [UserWithCircles] = []
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        table.register(NetworkUserTableViewCell.self, forCellReuseIdentifier: "UserCell")
        return table
    }()
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No Circles from Network\n\nYour connections haven't shared any circles yet." }
    
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
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        title = "My Network's Circles"
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        loadUsersWithCircles()
        completion?()
    }
    
    private func loadUsersWithCircles() {
        struct UsersWithCirclesResponse: Codable {
            let success: Bool
            let data: [UserWithCircles]
        }
        
        APIService.shared.request(
            endpoint: "network/users-with-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UsersWithCirclesResponse, APIError>) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshControl.endRefreshing()
                
                switch result {
                case .success(let response):
                    self.usersWithCircles = response.data.filter { $0.circleCount > 0 }
                    self.tableView.reloadData()
                    self.updateUI()
                case .failure(let error):
                    print("Error loading users with circles: \(error)")
                    self.showError("Failed to load network circles")
                }
            }
        }
    }
    
    @objc override func refreshData() {
        loadUsersWithCircles()
    }
    
    private func updateUI() {
        if usersWithCircles.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
    }
    
}

// MARK: - UITableViewDataSource
extension NetworkUsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return usersWithCircles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell", for: indexPath) as! NetworkUserTableViewCell
        let user = usersWithCircles[indexPath.row]
        cell.configure(with: user)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension NetworkUsersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let user = usersWithCircles[indexPath.row]
        let userCirclesVC = UserCirclesViewController(userId: user.userId, userName: user.displayName)
        navigationController?.pushViewController(userCirclesVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - UserWithCircles Model
struct UserWithCircles: Codable {
    let userId: String
    let displayName: String
    let profilePicture: String?
    let email: String
    let location: String?
    let circleCount: Int
}

struct UsersWithCirclesResponse: Codable {
    let success: Bool
    let data: [UserWithCircles]
}

// MARK: - NetworkUserTableViewCell
class NetworkUserTableViewCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = .tertiarySystemFill
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
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
    
    private let circleCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let chevronImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupView() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(profileImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(userInfoLabel)
        containerView.addSubview(circleCountLabel)
        containerView.addSubview(chevronImageView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: circleCountLabel.leadingAnchor, constant: -8),
            
            userInfoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            userInfoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            userInfoLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            circleCountLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            circleCountLabel.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -8),
            
            chevronImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            chevronImageView.widthAnchor.constraint(equalToConstant: 12),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    // MARK: - Configuration
    func configure(with user: UserWithCircles) {
        nameLabel.text = user.displayName
        // Display location if available
        if let location = user.location, !location.isEmpty {
            userInfoLabel.text = location
        } else {
            userInfoLabel.text = "Connected member"
        }
        circleCountLabel.text = "\(user.circleCount) Circle\(user.circleCount == 1 ? "" : "s")"
        
        // Load profile image
        if let urlString = user.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = UIImage(systemName: "person.circle.fill")
    }
}