import UIKit

class MyNetworkViewController: BaseViewController {
    
    // MARK: - Tab Types
    enum NetworkTab: String, CaseIterable {
        case myNetwork = "My Network"
        case discover = "Discover"
        case popular = "Popular"
        case nearby = "Nearby"
        case mutual = "Mutual"
        case sharedCircles = "Circles"
        
        var icon: UIImage? {
            switch self {
            case .myNetwork: return UIImage(systemName: "person.2.fill")
            case .discover: return UIImage(systemName: "person.3.fill")
            case .popular: return UIImage(systemName: "star.fill")
            case .nearby: return UIImage(systemName: "location.fill")
            case .mutual: return UIImage(systemName: "person.2.badge.plus")
            case .sharedCircles: return UIImage(systemName: "circle.hexagongrid.fill")
            }
        }
    }
    
    // MARK: - SSE Integration
    private var sseConnected = false
    private var selectedTab: NetworkTab = .myNetwork
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search users..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let tabScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let tabStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private var tabButtons: [UIButton] = []
    
    private let findContactsBar: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemGray5.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let findContactsLabel: UILabel = {
        let label = UILabel()
        label.text = "Find Contacts"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let findContactsIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "person.badge.plus")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let findContactsChevron: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    // Child View Controllers
    private var allUsersListVC: AllUsersListViewController?
    private var discoveryListVC: DiscoveryListViewController?
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
        selectTab(.myNetwork)  // Start with My Network tab
        setupSSE()
        
        // Check if user needs notification prompt for connections
        NotificationPromptManager.shared.checkAndPromptIfNeeded(in: self, context: .connections)
        
        // Listen for contacts import notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowContactsImport),
            name: NSNotification.Name("ShowContactsImport"),
            object: nil
        )
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
        
        // Show network tutorial if needed (only if progressing through tutorial)
        if OnboardingManager.shared.shouldShowTutorial && 
           OnboardingManager.shared.hasCompletedStep(.addPlace) &&
           !OnboardingManager.shared.hasCompletedStep(.exploreNetwork) {
            // Give a slight delay for the UI to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // Find the add connection button in the navigation bar
                if let addButton = self.navigationItem.rightBarButtonItem {
                    if let buttonView = addButton.value(forKey: "view") as? UIView {
                        OnboardingManager.shared.showTutorialStep(
                            .exploreNetwork,
                            targetView: buttonView,
                            in: self,
                            arrowDirection: .bottom
                        )
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Dismiss any tutorial bubble when leaving
        OnboardingManager.shared.dismissCurrentBubble()
    }
    
    // MARK: - Setup
    private func setupView() {
        setupNavigationBar(title: "My Network", largeTitleMode: .never)
        
        // Add connection button to navigation bar
        let addConnectionButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(showConnectionMenu)
        )
        addConnectionButton.accessibilityLabel = "Add Connection"
        
        navigationItem.rightBarButtonItem = addConnectionButton
        
        view.addSubview(searchBar)
        view.addSubview(tabScrollView)
        tabScrollView.addSubview(tabStackView)
        view.addSubview(findContactsBar)
        view.addSubview(containerView)
        
        // Create tab buttons
        setupTabButtons()
        
        // Add subviews to findContactsBar
        findContactsBar.addSubview(findContactsIcon)
        findContactsBar.addSubview(findContactsLabel)
        findContactsBar.addSubview(findContactsChevron)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            tabScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16),
            tabScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: 44),
            
            tabStackView.topAnchor.constraint(equalTo: tabScrollView.topAnchor),
            tabStackView.leadingAnchor.constraint(equalTo: tabScrollView.leadingAnchor, constant: 16),
            tabStackView.trailingAnchor.constraint(equalTo: tabScrollView.trailingAnchor, constant: -16),
            tabStackView.bottomAnchor.constraint(equalTo: tabScrollView.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: tabScrollView.heightAnchor),
            
            findContactsBar.topAnchor.constraint(equalTo: tabScrollView.bottomAnchor, constant: 16),
            findContactsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            findContactsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            findContactsBar.heightAnchor.constraint(equalToConstant: 56),
            
            // Find Contacts Bar internal layout
            findContactsIcon.leadingAnchor.constraint(equalTo: findContactsBar.leadingAnchor, constant: 16),
            findContactsIcon.centerYAnchor.constraint(equalTo: findContactsBar.centerYAnchor),
            findContactsIcon.widthAnchor.constraint(equalToConstant: 24),
            findContactsIcon.heightAnchor.constraint(equalToConstant: 24),
            
            findContactsLabel.leadingAnchor.constraint(equalTo: findContactsIcon.trailingAnchor, constant: 12),
            findContactsLabel.centerYAnchor.constraint(equalTo: findContactsBar.centerYAnchor),
            
            findContactsChevron.trailingAnchor.constraint(equalTo: findContactsBar.trailingAnchor, constant: -16),
            findContactsChevron.centerYAnchor.constraint(equalTo: findContactsBar.centerYAnchor),
            findContactsChevron.widthAnchor.constraint(equalToConstant: 16),
            findContactsChevron.heightAnchor.constraint(equalToConstant: 16),
            
            containerView.topAnchor.constraint(equalTo: findContactsBar.bottomAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        searchBar.delegate = self
        
        // Add tap gesture to Find Contacts bar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(findContactsTapped))
        findContactsBar.addGestureRecognizer(tapGesture)
        findContactsBar.isUserInteractionEnabled = true
    }
    
    private func setupTabButtons() {
        // Create a button for each tab
        for (index, tab) in NetworkTab.allCases.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(tab.rawValue, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tag = index
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            
            // Style the button
            button.backgroundColor = index == 0 ? Constants.Colors.primary : Constants.Colors.secondaryBackground
            button.setTitleColor(index == 0 ? .white : Constants.Colors.secondaryLabel, for: .normal)
            button.layer.cornerRadius = 18
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            
            tabButtons.append(button)
            tabStackView.addArrangedSubview(button)
        }
    }
    
    private func setupChildViewControllers() {
        // Create child view controllers
        allUsersListVC = AllUsersListViewController()
        discoveryListVC = DiscoveryListViewController()
        sharedCirclesListVC = SharedCirclesListViewController()
    }
    
    // MARK: - Actions
    @objc private func tabButtonTapped(_ sender: UIButton) {
        let tab = NetworkTab.allCases[sender.tag]
        selectTab(tab)
    }
    
    private func selectTab(_ tab: NetworkTab) {
        selectedTab = tab
        
        // Update button styles
        for (index, button) in tabButtons.enumerated() {
            let isSelected = NetworkTab.allCases[index] == tab
            button.backgroundColor = isSelected ? Constants.Colors.primary : Constants.Colors.secondaryBackground
            button.setTitleColor(isSelected ? .white : Constants.Colors.secondaryLabel, for: .normal)
        }
        
        // Show appropriate view controller
        switch tab {
        case .myNetwork:
            showConnectionsList()
        case .discover, .popular, .nearby, .mutual:
            showDiscoveryList(type: tab)
        case .sharedCircles:
            showSharedCirclesList()
        }
        
        // Update Find Contacts bar visibility
        findContactsBar.isHidden = (tab == .sharedCircles)
    }
    
    @objc private func showConnectionMenu() {
        // Directly show the share sheet without a menu
        shareConnectionInvite()
    }
    
    @objc private func findContactsTapped() {
        // Check if contacts permission is already granted
        let contactsStatus = ContactsService.shared.checkContactsPermission()
        
        if contactsStatus == .authorized {
            // Permission already granted, show contacts list
            showContactsList()
        } else if contactsStatus == .notDetermined {
            // Request permission first
            ContactsService.shared.requestContactsPermission { [weak self] granted in
                if granted {
                    self?.showContactsList()
                } else {
                    self?.showContactsPermissionDenied()
                }
            }
        } else {
            // Permission denied or restricted
            showContactsPermissionDenied()
        }
    }
    
    private func showContactsList() {
        let contactsVC = FindContactsViewController()
        let navController = UINavigationController(rootViewController: contactsVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    private func showContactsPermissionDenied() {
        let alert = UIAlertController(
            title: "Contacts Access Required",
            message: "To find and invite your contacts, please enable contacts access in Settings.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    @objc private func handleShowContactsImport() {
        // Trigger the find contacts flow when coming from suggested users overlay
        findContactsTapped()
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
        // Filter based on selected tab
        switch selectedTab {
        case .myNetwork:
            allUsersListVC?.updateSearchQuery(query)
        case .discover, .popular, .nearby, .mutual:
            // Discovery tabs handle search differently - would need to implement search in DiscoveryListViewController
            break
        case .sharedCircles:
            // Shared circles might have its own search logic
            break
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
    
    private func showDiscoveryList(type: NetworkTab) {
        guard let discoveryListVC = discoveryListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        // Configure discovery list for the selected type
        discoveryListVC.setDiscoveryType(type)
        
        addChild(discoveryListVC)
        containerView.addSubview(discoveryListVC.view)
        discoveryListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            discoveryListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            discoveryListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            discoveryListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            discoveryListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        discoveryListVC.didMove(toParent: self)
        currentViewController = discoveryListVC
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
            if self?.selectedTab == .myNetwork {
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
            if self?.selectedTab == .myNetwork {
                self?.allUsersListVC?.loadAllUsers()
            }
        }
    }
    
    private func handleConnectionDeclined(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh connections
            NetworkManager.shared.loadConnections()
            
            // Refresh the current view
            if self?.selectedTab == .myNetwork {
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


