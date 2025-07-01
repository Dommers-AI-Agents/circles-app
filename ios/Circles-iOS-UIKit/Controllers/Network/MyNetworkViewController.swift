import UIKit

class MyNetworkViewController: UIViewController {
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search users..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let items = ["Connections", "Shared Circles"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let searchResultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .systemBackground
        tableView.layer.cornerRadius = 12
        tableView.layer.shadowColor = UIColor.black.cgColor
        tableView.layer.shadowOpacity = 0.1
        tableView.layer.shadowOffset = CGSize(width: 0, height: 2)
        tableView.layer.shadowRadius = 4
        tableView.isHidden = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // Child View Controllers
    private var connectionsListVC: ConnectionsListViewController?
    private var sharedCirclesListVC: SharedCirclesListViewController?
    private var currentViewController: UIViewController?
    
    // Search properties
    private var searchResults: [User] = []
    private var searchTimer: Timer?
    private var isSearching = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupChildViewControllers()
        showConnectionsList()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        // Removed redundant title - tab bar already shows "My Network"
        
        // Set large title display mode to never to save space
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        
        // Add views
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(containerView)
        view.addSubview(searchResultsTableView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Search bar
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            // Segmented control
            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Container view
            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Search results table view
            searchResultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            searchResultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchResultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchResultsTableView.heightAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
        
        // Setup search bar
        searchBar.delegate = self
        
        // Setup search results table
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        searchResultsTableView.separatorStyle = .singleLine
        
        // Add action for segmented control
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }
    
    private func setupNavigationBar() {
        // Add the connection button
        let addConnectionButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(showConnectionMenu)
        )
        
        navigationItem.rightBarButtonItem = addConnectionButton
    }
    
    private func setupChildViewControllers() {
        // Create child view controllers
        connectionsListVC = ConnectionsListViewController()
        sharedCirclesListVC = SharedCirclesListViewController()
    }
    
    // MARK: - Actions
    @objc private func segmentChanged() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            showConnectionsList()
        case 1:
            showSharedCirclesList()
        default:
            break
        }
    }
    
    @objc private func showConnectionMenu() {
        // Directly show the share sheet without a menu
        shareConnectionInvite()
    }
    
    private func performSearch(with query: String) {
        // Cancel previous timer
        searchTimer?.invalidate()
        
        // Start new timer to debounce search
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.searchUsers(query: query)
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            searchResultsTableView.reloadData()
            searchResultsTableView.isHidden = true
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Show the table view immediately with loading state
        searchResultsTableView.isHidden = false
        
        // Search users via UserService
        UserService.shared.searchUsers(query: query) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.searchResults = users
                    self?.searchResultsTableView.reloadData()
                    
                    // Only hide if no results
                    if users.isEmpty {
                        self?.searchResultsTableView.isHidden = true
                    }
                case .failure(let error):
                    print("Search error: \(error)")
                    self?.searchResults = []
                    self?.searchResultsTableView.reloadData()
                    self?.searchResultsTableView.isHidden = true
                }
                self?.isSearching = false
            }
        }
    }
    
    private func shareConnectionInvite() {
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    // MARK: - Child View Controller Management
    private func showConnectionsList() {
        guard let connectionsListVC = connectionsListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        addChild(connectionsListVC)
        containerView.addSubview(connectionsListVC.view)
        connectionsListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            connectionsListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            connectionsListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            connectionsListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            connectionsListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        connectionsListVC.didMove(toParent: self)
        currentViewController = connectionsListVC
    }
    
    private func showSharedCirclesList() {
        guard let sharedCirclesListVC = sharedCirclesListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        addChild(sharedCirclesListVC)
        containerView.addSubview(sharedCirclesListVC.view)
        sharedCirclesListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            sharedCirclesListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            sharedCirclesListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sharedCirclesListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sharedCirclesListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        sharedCirclesListVC.didMove(toParent: self)
        currentViewController = sharedCirclesListVC
    }
    
    
    private func removeCurrentViewController() {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()
        currentViewController = nil
    }
}

// MARK: - UserSearchViewControllerDelegate
extension MyNetworkViewController: UserSearchViewControllerDelegate {
    func userSearchViewController(_ controller: UserSearchViewController, didSelectUser user: User) {
        // Dismiss the search controller
        controller.dismiss(animated: true) { [weak self] in
            // Send connection request
            self?.sendConnectionRequest(to: user)
        }
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
                        
                        // Refresh connections list if it's currently showing
                        if self?.segmentedControl.selectedSegmentIndex == 0 {
                            self?.connectionsListVC?.loadConnections()
                        }
                        
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
}
// MARK: - UISearchBarDelegate
extension MyNetworkViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(with: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        searchResults = []
        searchResultsTableView.reloadData()
        searchResultsTableView.isHidden = true
        isSearching = false
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension MyNetworkViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchResultCell")
        }
        
        let user = searchResults[indexPath.row]
        
        cell?.textLabel?.text = user.displayName
        cell?.detailTextLabel?.text = user.email
        cell?.detailTextLabel?.textColor = .secondaryLabel
        cell?.imageView?.image = UIImage(systemName: "person.circle.fill")
        cell?.imageView?.tintColor = .systemGray
        
        // Load avatar if available
        if let profilePicture = user.profilePicture, let url = URL(string: profilePicture) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        if let currentCell = tableView.cellForRow(at: indexPath) {
                            currentCell.imageView?.image = image
                            currentCell.imageView?.layer.cornerRadius = 20
                            currentCell.imageView?.clipsToBounds = true
                        }
                    }
                }
            }.resume()
        }
        
        return cell!
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = searchResults[indexPath.row]
        
        // Hide search results and clear search
        searchBar.text = ""
        searchBar.resignFirstResponder()
        searchResults = []
        searchResultsTableView.reloadData()
        searchResultsTableView.isHidden = true
        isSearching = false
        
        // Send connection request
        sendConnectionRequest(to: user)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}
