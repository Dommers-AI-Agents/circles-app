import UIKit

class MyNetworkViewController: BaseViewController {
    
    // MARK: - Segments
    //
    // This page is about PEOPLE: the ones you know, and the ones worth knowing.
    // (It was once six chips — My Network, Discover, Popular, Nearby, Mutual,
    // Circles — four of which were the same endpoint sorted differently. The
    // shared-circles list was removed from here entirely: circle management
    // doesn't belong in a people space.)
    enum NetworkTab: String, CaseIterable {
        case people = "People"
        case discover = "Discover"
    }

    // MARK: - SSE Integration
    private var sseConnected = false
    private var selectedTab: NetworkTab = .people
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search users..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: NetworkTab.allCases.map { $0.rawValue })
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    
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
    private var currentViewController: UIViewController?
    
    // Search properties
    private var searchTimer: Timer?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupChildViewControllers()
        selectTab(.people)
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

        // Child lists hand off to Discover rather than pushing their own copy.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showDiscoverSegment),
            name: .showDiscoverSegment,
            object: nil
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Force refresh connections to ensure badge is accurate
        NetworkManager.shared.refreshBadgeCount()
    }

    /// Refreshes whichever segment is visible.
    ///
    /// `CirclesTabBarController` calls this when the Network tab is re-tapped
    /// while already selected. This class never overrode it, so the call landed
    /// on `BaseViewController`'s empty implementation and re-tapping the tab
    /// did nothing at all.
    override func loadData(completion: (() -> Void)? = nil) {
        switch selectedTab {
        case .people:
            allUsersListVC?.loadPeople()
        case .discover:
            discoveryListVC?.loadData()
        }
        NetworkManager.shared.refreshBadgeCount()
        completion?()
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
        view.addSubview(segmentedControl)
        view.addSubview(findContactsBar)
        view.addSubview(containerView)
        
        // Add subviews to findContactsBar
        findContactsBar.addSubview(findContactsIcon)
        findContactsBar.addSubview(findContactsLabel)
        findContactsBar.addSubview(findContactsChevron)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            findContactsBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
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
    
    private func setupChildViewControllers() {
        // Create child view controllers
        allUsersListVC = AllUsersListViewController()
        discoveryListVC = DiscoveryListViewController()
    }
    
    // MARK: - Actions
    @objc private func segmentChanged() {
        let index = segmentedControl.selectedSegmentIndex
        guard index >= 0 && index < NetworkTab.allCases.count else { return }
        selectTab(NetworkTab.allCases[index])
    }

    private func selectTab(_ tab: NetworkTab) {
        selectedTab = tab
        if let index = NetworkTab.allCases.firstIndex(of: tab) {
            segmentedControl.selectedSegmentIndex = index
        }

        switch tab {
        case .people:
            showConnectionsList()
        case .discover:
            showDiscoveryList()
        }

        // Finding people is a Discover activity, so the bar only earns its
        // 56pt there. It used to sit on every tab, pushing your own
        // connections further down the screen.
        findContactsBar.isHidden = (tab != .discover)

        // Whatever is showing has to reflect the current query — the search
        // field is shared across segments.
        filterUsers(with: searchBar.text ?? "")
    }

    /// The nav-bar button offers the two ways to bring someone in. It used to
    /// be labelled "Add Connection" and open a share sheet immediately, which
    /// is neither adding nor a connection.
    @objc private func showConnectionMenu() {
        AlertPresenter.showActionSheet(
            title: "Add people",
            actions: [
                ("Find people you know", .default, { [weak self] in self?.findContactsTapped() }),
                ("Share an invite link", .default, { [weak self] in self?.shareConnectionInvite() })
            ],
            from: self,
            sourceView: view
        )
    }

    @objc private func showDiscoverSegment() {
        selectTab(.discover)
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
        AlertPresenter.showConfirmation(
            title: "Contacts access is off",
            message: "Turn on contacts access in Settings to find people you already know.",
            confirmTitle: "Open Settings",
            from: self,
            onConfirm: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
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
    
    /// Routes the query to whichever segment is showing.
    ///
    /// The search field sits above both segments but used to filter only
    /// the first — on the other chips typing did nothing at all, with no
    /// indication why. A control that silently does nothing is worse than no
    /// control.
    private func filterUsers(with query: String) {
        switch selectedTab {
        case .people:
            allUsersListVC?.updateSearchQuery(query)
        case .discover:
            discoveryListVC?.updateSearchQuery(query)
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
    
    private func showDiscoveryList() {
        guard let discoveryListVC = discoveryListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        discoveryListVC.loadData()

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
        Logger.debug("📡 MyNetwork: Received SSE event: \(event.type)")
        
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
        Logger.debug("📡 MyNetwork: SSE connected")
        sseConnected = true
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        Logger.debug("📡 MyNetwork: SSE disconnected")
        sseConnected = false
    }
    
    // MARK: - Event Handlers
    private func handleNewConnectionRequest(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh the connections list to show new request
            NetworkManager.shared.loadConnections()
            
            // If showing all users list, refresh it
            if self?.selectedTab == .people {
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
            if self?.selectedTab == .people {
                self?.allUsersListVC?.loadAllUsers()
            }
        }
    }
    
    private func handleConnectionDeclined(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh connections
            NetworkManager.shared.loadConnections()
            
            // Refresh the current view
            if self?.selectedTab == .people {
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


