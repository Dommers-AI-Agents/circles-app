import UIKit

class PlaceLikesViewController: BaseViewController {
    
    // MARK: - Properties
    var placeId: String?
    var placeName: String?
    private var users: [User] = []
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = Constants.Colors.background
        return tableView
    }()
    
    // MARK: - Configuration
    override var emptyStateMessage: String? { "No likes yet\n\nWhen people like this place, they'll appear here." }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Liked by"
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UserRowCell.self, forCellReuseIdentifier: UserRowCell.reuseIdentifier)
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)?) {
        guard let placeId = placeId else {
            completion?()
            return
        }
        
        PlaceService.shared.fetchPlaceLikes(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.users = response.likes
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    self?.showError(error)
                    self?.updateEmptyState()
                }
                completion?()
            }
        }
    }
    
    private func updateEmptyState() {
        if users.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
    }
}

// MARK: - UITableViewDataSource
extension PlaceLikesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UserRowCell.reuseIdentifier, for: indexPath) as! UserRowCell
        let user = users[indexPath.row]
        // Bio when they wrote one, otherwise a neutral line
        let bio = user.bio.flatMap { $0.isEmpty ? nil : $0 }
        cell.configure(with: user, subtitle: bio ?? "Circles user")
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PlaceLikesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = users[indexPath.row]
        
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// PlaceLikesResponse is now defined in PlaceService.swift
