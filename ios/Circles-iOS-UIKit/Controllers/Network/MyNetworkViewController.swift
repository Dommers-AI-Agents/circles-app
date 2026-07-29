import UIKit

class MyNetworkViewController: BaseViewController {
    
    // MARK: - Segments
    //
    // This page is about PEOPLE: the ones you know, and the ones worth knowing.
    // (It was once six chips — My Network, Discover, Popular, Nearby, Mutual,
    // Circles — four of which were the same endpoint sorted differently. The
    // shared-circles list was removed from here entirely: circle management
    // doesn't belong in a people space.)
    // Discover leads: the app is young, so most people arrive with a thin
    // network — the page's job is growing it, not admiring it. Popular is the
    // scorecard (everyone ranked by collection size, including people you
    // follow); it earns its own tab because a leaderboard is a different mood
    // than a suggestion list.
    enum NetworkTab: String, CaseIterable {
        case discover = "Discover"
        case popular = "Popular"
        case people = "My People"
        case requests = "Requests"
    }

    // MARK: - SSE Integration
    private var sseConnected = false
    private var selectedTab: NetworkTab = .discover
    
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

    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    // Child View Controllers
    private var allUsersListVC: AllUsersListViewController?
    private var requestsListVC: AllUsersListViewController?
    private var discoveryListVC: DiscoveryListViewController?
    private var popularListVC: DiscoveryListViewController?
    private var currentViewController: UIViewController?
    
    // Search properties
    private var searchTimer: Timer?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupChildViewControllers()
        selectTab(.discover)
        setupSSE()
        
        // Check if user needs notification prompt for connections
        NotificationPromptManager.shared.checkAndPromptIfNeeded(in: self, context: .connections)

        // Child lists hand off to Discover rather than pushing their own copy.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showDiscoverSegment),
            name: .showDiscoverSegment,
            object: nil
        )

        // Connection-request notifications land on the Requests segment.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showRequestsSegment),
            name: .showRequestsSegment,
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
        case .requests:
            requestsListVC?.loadPeople()
        case .discover:
            discoveryListVC?.loadData()
        case .popular:
            popularListVC?.loadData()
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
        
        // Invite button: straight to the share sheet. (The phone-contacts
        // import flow is gone — nobody used it, and a share link does the job.)
        let addConnectionButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(shareInviteTapped)
        )
        addConnectionButton.accessibilityLabel = "Invite people"
        
        navigationItem.rightBarButtonItem = addConnectionButton
        
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),

            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        searchBar.delegate = self
    }
    
    private func setupChildViewControllers() {
        // Create child view controllers
        allUsersListVC = AllUsersListViewController()
        let requestsVC = AllUsersListViewController()
        requestsVC.listMode = .requests
        requestsListVC = requestsVC
        discoveryListVC = DiscoveryListViewController(mode: .discover)
        popularListVC = DiscoveryListViewController(mode: .popular)
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
        case .requests:
            showRequestsList()
        case .discover:
            showChildList(discoveryListVC)
        case .popular:
            showChildList(popularListVC)
        }

        // Whatever is showing has to reflect the current query — the search
        // field is shared across segments. (With a live query this re-routes
        // straight back to the global results list.)
        filterUsers(with: searchBar.text ?? "")
    }

    @objc private func showDiscoverSegment() {
        selectTab(.discover)
    }

    @objc private func showRequestsSegment() {
        selectTab(.requests)
    }

    private func performSearch(with query: String) {
        // Cancel previous timer
        searchTimer?.invalidate()
        
        // Start new timer to debounce search
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.filterUsers(with: query)
        }
    }
    
    /// A typed query searches EVERYONE; the segments only organize the
    /// untyped view. Typing routes to the People list (which searches your
    /// whole network plus a server-side "Not in your network" sweep) no matter
    /// which segment is selected; clearing restores the selected segment.
    private var isShowingGlobalSearchResults = false

    private func filterUsers(with query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty {
            if currentViewController !== allUsersListVC {
                showPeopleList(allUsersListVC)
                isShowingGlobalSearchResults = true
            }
            allUsersListVC?.updateSearchQuery(trimmed)
            return
        }

        if isShowingGlobalSearchResults {
            // Search borrowed the container from another segment — hand it back.
            isShowingGlobalSearchResults = false
            allUsersListVC?.updateSearchQuery("")
            selectTab(selectedTab)
            return
        }

        switch selectedTab {
        case .people:
            allUsersListVC?.updateSearchQuery(trimmed)
        case .requests:
            requestsListVC?.updateSearchQuery(trimmed)
        case .discover:
            discoveryListVC?.updateSearchQuery(trimmed)
        case .popular:
            popularListVC?.updateSearchQuery(trimmed)
        }
    }

    @objc private func shareInviteTapped() {
        shareConnectionInvite()
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
        showPeopleList(allUsersListVC)
    }

    private func showRequestsList() {
        showPeopleList(requestsListVC)
    }

    /// Shared child-swap for the two AllUsersListViewController-backed tabs
    /// (My People and Requests).
    private func showPeopleList(_ listVC: AllUsersListViewController?) {
        guard let listVC = listVC else { return }

        if currentViewController != nil {
            removeCurrentViewController()
        }

        addChild(listVC)
        containerView.addSubview(listVC.view)
        listVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            listVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            listVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            listVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            listVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        listVC.didMove(toParent: self)
        currentViewController = listVC
    }
    
    /// Shared child-swap for the Discover and Popular lists (same VC type,
    /// different mode).
    private func showChildList(_ childVC: DiscoveryListViewController?) {
        guard let childVC = childVC else { return }

        if currentViewController != nil {
            removeCurrentViewController()
        }

        childVC.loadData()

        addChild(childVC)
        containerView.addSubview(childVC.view)
        childVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            childVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            childVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            childVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            childVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        childVC.didMove(toParent: self)
        currentViewController = childVC
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


