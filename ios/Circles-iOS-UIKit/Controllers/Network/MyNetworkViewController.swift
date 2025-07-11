import UIKit

class MyNetworkViewController: UIViewController {
    
    // MARK: - SSE Integration
    private var sseConnected = false
    
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
    
    
    // Child View Controllers
    private var allUsersListVC: AllUsersListViewController?
    private var sharedCirclesListVC: SharedCirclesListViewController?
    private var currentViewController: UIViewController?
    
    // Search properties
    private var searchTimer: Timer?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupChildViewControllers()
        showConnectionsList()
        setupSSE()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Force refresh connections to ensure badge is accurate
        NetworkManager.shared.refreshBadgeCount()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Clear newly accepted connection highlight after a delay
        if UserDefaults.standard.string(forKey: "newlyAcceptedConnectionId") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UserDefaults.standard.removeObject(forKey: "newlyAcceptedConnectionId")
                UserDefaults.standard.removeObject(forKey: "newlyAcceptedConnectionDate")
                // Refresh the table view to remove highlight
                if let allUsersVC = self.allUsersListVC {
                    allUsersVC.updateSearchQuery("")
                }
            }
        }
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
        // Don't add searchResultsTableView anymore - we'll use AllUsersListViewController
        
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
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Setup search bar
        searchBar.delegate = self
        
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
        allUsersListVC = AllUsersListViewController()
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
            self?.filterUsers(with: query)
        }
    }
    
    private func filterUsers(with query: String) {
        // Filter the all users list if it's showing
        if segmentedControl.selectedSegmentIndex == 0 {
            allUsersListVC?.updateSearchQuery(query)
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
        guard let allUsersListVC = allUsersListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        addChild(allUsersListVC)
        containerView.addSubview(allUsersListVC.view)
        allUsersListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            allUsersListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            allUsersListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            allUsersListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            allUsersListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        allUsersListVC.didMove(toParent: self)
        currentViewController = allUsersListVC
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
        // Clear the filter
        filterUsers(with: "")
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }
}

// MARK: - SSE Setup
extension MyNetworkViewController {
    private func setupSSE() {
        SSEService.shared.addDelegate(self)
    }
}

// MARK: - SSEServiceDelegate
extension MyNetworkViewController: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        print("📡 MyNetwork: Received SSE event: \(event.type)")
        
        switch event.type {
        case .connectionRequest:
            // New connection request received
            handleNewConnectionRequest(event.data)
            
        case .connectionAccepted:
            // Connection was accepted
            handleConnectionAccepted(event.data)
            
        case .connectionDeclined:
            // Connection was declined
            handleConnectionDeclined(event.data)
            
        default:
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        print("📡 MyNetwork: SSE connected")
        sseConnected = true
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        print("📡 MyNetwork: SSE disconnected")
        sseConnected = false
    }
    
    // MARK: - Event Handlers
    private func handleNewConnectionRequest(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh the connections list to show new request
            NetworkManager.shared.loadConnections()
            
            // If showing all users list, refresh it
            if self?.segmentedControl.selectedSegmentIndex == 0 {
                self?.allUsersListVC?.loadAllUsers()
            }
            
            // Show visual feedback - could add a badge or notification banner
            self?.showNewConnectionBanner(data)
        }
    }
    
    private func handleConnectionAccepted(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh connections
            NetworkManager.shared.loadConnections()
            
            // Refresh the current view
            if self?.segmentedControl.selectedSegmentIndex == 0 {
                self?.allUsersListVC?.loadAllUsers()
            }
        }
    }
    
    private func handleConnectionDeclined(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh connections
            NetworkManager.shared.loadConnections()
            
            // Refresh the current view
            if self?.segmentedControl.selectedSegmentIndex == 0 {
                self?.allUsersListVC?.loadAllUsers()
            }
        }
    }
    
    private func showNewConnectionBanner(_ data: [String: Any]) {
        // Create a banner notification
        let banner = UIView()
        banner.backgroundColor = Constants.Colors.primary
        banner.layer.cornerRadius = 8
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = "New connection request!"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        banner.addSubview(label)
        view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            banner.heightAnchor.constraint(equalToConstant: 44),
            
            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
        
        // Animate in
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: -20)
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            banner.alpha = 1
            banner.transform = .identity
        }
        
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3, animations: {
                banner.alpha = 0
                banner.transform = CGAffineTransform(translationX: 0, y: -20)
            }) { _ in
                banner.removeFromSuperview()
            }
        }
    }
}


