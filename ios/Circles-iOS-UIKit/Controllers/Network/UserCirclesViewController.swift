import UIKit

class UserCirclesViewController: UIViewController {
    
    // MARK: - Properties
    private let userId: String
    private let userName: String
    private let connectionId: String?
    private var userCircles: [Circle] = []
    private let refreshControl = UIRefreshControl()
    private var hasRecentActivity = false
    
    // MARK: - UI Elements
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 30
        imageView.backgroundColor = .tertiarySystemFill
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let userNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circleCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CircleCell")
        return table
    }()
    
    // MARK: - Init
    init(userId: String, userName: String, connectionId: String? = nil) {
        self.userId = userId
        self.userName = userName
        self.connectionId = connectionId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        loadUserCircles()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        title = "\(userName)'s Circles"
        
        view.addSubview(headerView)
        headerView.addSubview(profileImageView)
        headerView.addSubview(userNameLabel)
        headerView.addSubview(circleCountLabel)
        view.addSubview(tableView)
        
        userNameLabel.text = userName
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 140),
            
            profileImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            profileImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 60),
            profileImageView.heightAnchor.constraint(equalToConstant: 60),
            
            userNameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 12),
            userNameLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            userNameLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            
            circleCountLabel.topAnchor.constraint(equalTo: userNameLabel.bottomAnchor, constant: 4),
            circleCountLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            circleCountLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    // MARK: - Data Loading
    private func loadUserCircles() {
        struct UserCirclesResponse: Codable {
            let success: Bool
            let data: UserCirclesData
        }
        
        struct UserCirclesData: Codable {
            let user: User
            let circles: [Circle]
            let hasRecentActivity: Bool?
        }
        
        APIService.shared.request(
            endpoint: "network/user-circles/\(userId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                self?.refreshControl.endRefreshing()
                
                switch result {
                case .success(let response):
                    self?.userCircles = response.data.circles
                    self?.hasRecentActivity = response.data.hasRecentActivity ?? false
                    self?.updateUI(with: response.data.user)
                    self?.tableView.reloadData()
                    
                    // Show activity banner if there's recent activity
                    if self?.hasRecentActivity == true {
                        self?.showActivityBanner()
                    }
                case .failure(let error):
                    print("Error loading user circles: \(error)")
                    self?.showError("Failed to load circles")
                }
            }
        }
    }
    
    @objc private func refreshData() {
        loadUserCircles()
    }
    
    private func updateUI(with user: User) {
        // Update circle count
        let count = userCircles.count
        circleCountLabel.text = "\(count) Circle\(count == 1 ? "" : "s") Shared"
        
        // Load profile image
        if let urlString = user.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showActivityBanner() {
        let bannerView = UIView()
        bannerView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        bannerView.layer.cornerRadius = 8
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = "🆕 New activity from \(userName)"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        
        bannerView.addSubview(label)
        view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bannerView.heightAnchor.constraint(equalToConstant: 36),
            
            label.centerXAnchor.constraint(equalTo: bannerView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor)
        ])
        
        // Animate banner appearance
        bannerView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            bannerView.alpha = 1
        }
        
        // Remove banner after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3, animations: {
                bannerView.alpha = 0
            }) { _ in
                bannerView.removeFromSuperview()
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension UserCirclesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return userCircles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath)
        let circle = userCircles[indexPath.row]
        
        // Configure cell with basic information
        var content = cell.defaultContentConfiguration()
        content.text = circle.name
        content.secondaryText = "\(circle.places?.count ?? 0) places"
        
        // Set image based on category
        let iconName: String
        switch circle.category {
        case .travel: iconName = "airplane"
        case .food: iconName = "fork.knife"
        case .services: iconName = "wrench.and.screwdriver"
        case .shopping: iconName = "bag"
        case .healthcare: iconName = "heart"
        case .entertainment: iconName = "tv"
        case .other: iconName = "circle.grid.3x3"
        }
        content.image = UIImage(systemName: iconName)
        content.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        
        // Highlight new circles
        if circle.isNew == true {
            cell.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.05)
            
            // Add new badge
            let newBadge = UILabel()
            newBadge.text = "NEW"
            newBadge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            newBadge.textColor = .white
            newBadge.backgroundColor = Constants.Colors.primary
            newBadge.layer.cornerRadius = 4
            newBadge.clipsToBounds = true
            newBadge.textAlignment = .center
            newBadge.translatesAutoresizingMaskIntoConstraints = false
            
            cell.contentView.addSubview(newBadge)
            NSLayoutConstraint.activate([
                newBadge.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -36),
                newBadge.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                newBadge.widthAnchor.constraint(equalToConstant: 32),
                newBadge.heightAnchor.constraint(equalToConstant: 18)
            ])
        } else {
            cell.backgroundColor = .systemBackground
            // Remove any existing new badges
            cell.contentView.subviews.forEach { view in
                if view is UILabel && (view as? UILabel)?.text == "NEW" {
                    view.removeFromSuperview()
                }
            }
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension UserCirclesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let circle = userCircles[indexPath.row]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}