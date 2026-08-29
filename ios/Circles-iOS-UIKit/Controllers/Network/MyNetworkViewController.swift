import UIKit

class MyNetworkViewController: BaseViewController {
    
    // MARK: - Segments
    //
    // This page is about PEOPLE: the ones you know, and the ones worth knowing.
    // (It was once six chips — My Network, Discover, Popular, Nearby, Mutual,
    // Circles — four of which were the same endpoint sorted differently. The
    // shared-circles list was removed from here entirely: circle management
    // doesn't belong in a people space.)
    // Popular is the DEFAULT (Wes, 2026-08-12): it ranks everyone by
    // collection size INCLUDING your own connections, so it works for both a
    // thin network (interesting strangers) and an established one (your
    // people near the top) — the best single landing view. Discover remains
    // the dedicated grow-your-network tab.
    enum NetworkTab: String, CaseIterable {
        case discover = "Discover"
        case popular = "Popular"
        case people = "My People"
        case requests = "Requests"
    }

    // MARK: - SSE Integration
    private var sseConnected = false
    private var selectedTab: NetworkTab = .popular
    
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
        // Must match the selectedTab default above (Popular)
        control.selectedSegmentIndex = NetworkTab.allCases.firstIndex(of: .popular) ?? 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    // Red count bubble for pending requests, floated over the Requests segment
    // (UISegmentedControl has no native badge support). Mirrors the tab bar
    // badge so the user can see where to tap once they arrive on this screen.
    private let requestsBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.textAlignment = .center
        label.layer.cornerRadius = 9
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    
    // Incoming-request banner: pending requests used to be visible ONLY on the
    // Requests segment, so a new user landing on Popular never saw that Wes and
    // Brittany were already waiting for them. This strip shows on every
    // segment except Requests, with a one-tap Accept.
    private let incomingRequestBanner: UIControl = {
        let view = UIControl()
        view.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.12)
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    private let incomingRequestLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.primary
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private lazy var incomingRequestAcceptButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Accept", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(acceptBannerRequestTapped), for: .touchUpInside)
        return button
    }()
    private var bannerHeightConstraint: NSLayoutConstraint?
    private var containerTopConstraint: NSLayoutConstraint?

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
        // Default segment is Popular (Wes: surfaces your own connections too).
        // This must match the selectedTab/segmentedControl defaults above.
        selectTab(.popular)
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

        // Same signal the tab bar badge listens to — fires whenever
        // NetworkManager reloads or mutates the pending-connections list.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pendingRequestsCountChanged),
            name: .pendingConnectionsCountChanged,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Force refresh connections to ensure badge is accurate
        NetworkManager.shared.refreshBadgeCount()
        // Show the cached count immediately; the refresh above re-posts
        // .pendingConnectionsCountChanged once fresh data lands.
        updateRequestsBadge()
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
        
        // (The old find-your-people tutorial bubble was removed 2026-08-19 —
        // the tour now lives entirely on the home page.)
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

        // In-person connect: your QR is one tap away — the other person scans
        // it with their camera and the connect link does the rest. (It existed
        // only inside Share Profile before, where nobody standing next to you
        // could find it.)
        let qrButton = UIBarButtonItem(
            image: UIImage(systemName: "qrcode"),
            style: .plain,
            target: self,
            action: #selector(showMyQRCodeTapped)
        )
        qrButton.accessibilityLabel = "Show my connect QR code"

        // Tap to stay in touch: hold two phones together, connect in one tap
        let nearbyButton = UIBarButtonItem(
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            style: .plain,
            target: self,
            action: #selector(tapToConnectTapped)
        )
        nearbyButton.accessibilityLabel = "Tap phones to connect"

        navigationItem.rightBarButtonItems = [addConnectionButton, nearbyButton, qrButton]
        
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(incomingRequestBanner)
        incomingRequestBanner.addSubview(incomingRequestLabel)
        incomingRequestBanner.addSubview(incomingRequestAcceptButton)
        incomingRequestBanner.addTarget(self, action: #selector(showRequestsSegment), for: .touchUpInside)
        view.addSubview(containerView)
        view.addSubview(requestsBadgeLabel)

        let bannerHeight = incomingRequestBanner.heightAnchor.constraint(equalToConstant: 0)
        bannerHeightConstraint = bannerHeight
        let containerTop = containerView.topAnchor.constraint(equalTo: incomingRequestBanner.bottomAnchor, constant: 16)
        containerTopConstraint = containerTop

        NSLayoutConstraint.activate([
            incomingRequestBanner.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            incomingRequestBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            incomingRequestBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bannerHeight,

            incomingRequestLabel.leadingAnchor.constraint(equalTo: incomingRequestBanner.leadingAnchor, constant: 14),
            incomingRequestLabel.centerYAnchor.constraint(equalTo: incomingRequestBanner.centerYAnchor),
            incomingRequestLabel.trailingAnchor.constraint(lessThanOrEqualTo: incomingRequestAcceptButton.leadingAnchor, constant: -10),

            incomingRequestAcceptButton.trailingAnchor.constraint(equalTo: incomingRequestBanner.trailingAnchor, constant: -10),
            incomingRequestAcceptButton.centerYAnchor.constraint(equalTo: incomingRequestBanner.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 44),

            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Straddles the top-right corner of the last segment (Requests).
            requestsBadgeLabel.centerYAnchor.constraint(equalTo: segmentedControl.topAnchor),
            requestsBadgeLabel.centerXAnchor.constraint(equalTo: segmentedControl.trailingAnchor, constant: -10),
            requestsBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
            requestsBadgeLabel.widthAnchor.constraint(greaterThanOrEqualTo: requestsBadgeLabel.heightAnchor),

            containerTop,
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

        // The banner hides on the Requests segment (redundant there)
        updateIncomingRequestBanner()
    }

    @objc private func showDiscoverSegment() {
        selectTab(.discover)
    }

    @objc private func showRequestsSegment() {
        selectTab(.requests)
    }

    @objc private func showMyQRCodeTapped() {
        guard let me = AuthService.shared.currentUser else { return }
        let shareProfileVC = ShareProfileViewController(user: me)
        shareProfileVC.modalPresentationStyle = .overFullScreen
        shareProfileVC.modalTransitionStyle = .crossDissolve
        present(shareProfileVC, animated: true)
    }

    @objc private func tapToConnectTapped() {
        let tapVC = TapToConnectViewController()
        let navController = UINavigationController(rootViewController: tapVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }

    // MARK: - Requests badge

    @objc private func pendingRequestsCountChanged() {
        updateRequestsBadge()
    }

    private func updateRequestsBadge() {
        NetworkManager.shared.getPendingConnectionsCount { [weak self] count in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.requestsBadgeLabel.isHidden = count == 0
                self.requestsBadgeLabel.text = count > 9 ? "9+" : "\(count)"
                self.requestsBadgeLabel.accessibilityLabel = "\(count) pending connection requests"
                self.updateIncomingRequestBanner()
            }
        }
    }

    // MARK: - Incoming-request banner

    /// The newest incoming pending request, or nil.
    private var firstIncomingRequest: Connection? {
        let currentUserId = AuthService.shared.getUserId()
        return NetworkManager.shared.pendingConnections.first {
            $0.status == .pending && $0.connectedUserId == currentUserId
        }
    }

    private func updateIncomingRequestBanner() {
        let currentUserId = AuthService.shared.getUserId()
        let incoming = NetworkManager.shared.pendingConnections.filter {
            $0.status == .pending && $0.connectedUserId == currentUserId
        }
        // The Requests segment already lists them in full
        let show = !incoming.isEmpty && selectedTab != .requests
        incomingRequestBanner.isHidden = !show
        bannerHeightConstraint?.constant = show ? 44 : 0
        containerTopConstraint?.constant = show ? 16 : 6
        guard show else { return }

        let name = incoming.first?.connectedUser?.displayName ?? "Someone"
        incomingRequestLabel.text = incoming.count == 1
            ? "🤝 \(name) wants to connect"
            : "🤝 \(name) and \(incoming.count - 1) other\(incoming.count == 2 ? "" : "s") want to connect"
        incomingRequestAcceptButton.isHidden = incoming.count != 1
    }

    @objc private func acceptBannerRequestTapped() {
        guard let request = firstIncomingRequest else { return }
        incomingRequestAcceptButton.isEnabled = false
        NetworkManager.shared.acceptConnectionWithCredit(request.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.incomingRequestAcceptButton.isEnabled = true
                switch result {
                case .success(let (_, credit)):
                    // Accepting a connection earns coins — play the deposit
                    PiggyBankDepositView.play(credit: credit)
                    let name = request.connectedUser?.displayName ?? "your new connection"
                    self.showSuccess("You're now connected with \(name)!")
                    self.updateIncomingRequestBanner()
                    // The lists below hold relationship state too — refresh them
                    self.allUsersListVC?.loadPeople()
                    self.requestsListVC?.loadPeople()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
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

    /// Tutorial follow-through for the "Find Your People" step: instead of
    /// narrating and moving on, offer the two concrete ways to act on it.
    /// Cancel just defers — the privacy step appears the next time the user
    /// visits their profile (ProfileViewController.viewDidAppear).
    func showOnboardingConnectPrompt() {
        AlertPresenter.showActionSheet(
            title: "Connect with someone you know",
            message: "Circles comes alive when you swap favorite spots with people you trust.",
            actions: [
                ("Invite My Best Friend", .default, { [weak self] in
                    self?.shareConnectionInvite()
                }),
                ("Show My QR Code", .default, { [weak self] in
                    self?.showMyQRCodeTapped()
                }),
                ("Tap Phones to Connect", .default, { [weak self] in
                    self?.tapToConnectTapped()
                }),
                ("Search People I Know", .default, { [weak self] in
                    self?.searchBar.becomeFirstResponder()
                })
            ],
            from: self
        )
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


