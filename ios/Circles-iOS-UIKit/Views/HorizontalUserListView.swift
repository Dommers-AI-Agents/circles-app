import UIKit

protocol HorizontalUserListViewDelegate: AnyObject {
    func didSelectUser(_ user: User, connectionId: String)
    /// Long-press on an avatar — the delegate decides the action (the home
    /// screen shows a quick-actions menu; other screens may open the profile).
    func didLongPressUser(_ user: User, connectionId: String)
    /// A SUGGESTED person (not yet followed) was tapped — open their profile.
    func didSelectSuggestedUser(_ user: User)
}

// Default no-op so conformers that never show suggestions (the modal map's
// filter row) compile untouched
extension HorizontalUserListViewDelegate {
    func didSelectSuggestedUser(_ user: User) {}
}

class HorizontalUserListView: UIView {

    // MARK: - Properties
    weak var delegate: HorizontalUserListViewDelegate?
    private var connections: [Connection] = []
    private var loadRetryCount = 0
    private let maxRetries = 3

    // MARK: - Discovery suffix (home embed only)

    /// When true, the row appends SUGGESTED people (when sparse) and a
    /// trailing "Find People +" cell. Off by default — the modal map's avatar
    /// row is a pure filter surface and must stay relationships-only.
    var showsDiscoverySuffix = false

    private var suggestions: [User] = []
    private var isFetchingSuggestions = false
    private var hasFetchedSuggestions = false

    /// What the collection view actually renders. Connections ALWAYS occupy
    /// indices 0..<connections.count — the selection pinning, SSE insert-at-0,
    /// and clearActivityForConnection index math all rely on that invariant.
    private enum RowItem {
        case connection(Connection)
        case suggestion(User)
        case findPeople
    }

    private var rowItems: [RowItem] {
        var items: [RowItem] = connections.map { RowItem.connection($0) }
        if showsDiscoverySuffix {
            // A suggestion the user has since followed shows up in connections —
            // drop it from the suffix immediately (refetch catches up later)
            let visibleSuggestions = suggestions.filter { user in
                !connections.contains { connection in
                    guard let id = connection.connectedUser?.id else { return false }
                    return IDNormalizer.isSameUser(id, user.id)
                }
            }
            items += visibleSuggestions.map { RowItem.suggestion($0) }
            // The "+" trails any content; a fully empty row keeps the
            // text empty state instead of a lone plus
            if !items.isEmpty { items.append(.findPeople) }
        }
        return items
    }

    /// Snapshot the collection view actually renders. Rebuilt inside
    /// numberOfItemsInSection — the one place UIKit is guaranteed to call
    /// before configuring cells (reloadData AND performBatchUpdates) — so the
    /// count UIKit holds and the array cellForItemAt indexes can never drift
    /// (a live computed property raced connection mutations and left blank
    /// guard-cells at the tail).
    private var displayedRowItems: [RowItem] = []

    // NOTE (2026-08-19, Wes): no relationship filter here on purpose. This
    // row's one job is "the most relevant people to you right now" — the
    // connectionScore ranking already blends connections and follows, and a
    // Connections/Following toggle was tried and removed same-day: splitting
    // by mechanism hid whoever mattered most at the moment.

    /// User id of the currently selected connection (map filter); the matching
    /// avatar shows a blue selection ring and is pinned to the front of the
    /// list until someone else is selected
    var selectedUserId: String? {
        didSet {
            guard oldValue != selectedUserId else { return }
            // Update ONLY the affected cells' highlight rings and animate the
            // selected avatar to the front — a full reloadData() here tore down
            // every visible cell on each tap, which (with async image loads)
            // was the visible "flashing".
            refreshSelectionHighlights()
            animateSelectedToFront()
        }
    }

    /// Toggles the blue selection ring on the currently visible cells without
    /// reconfiguring them (no image reload, no flash).
    private func refreshSelectionHighlights() {
        for cell in collectionView.visibleCells {
            guard let userCell = cell as? UserActivityCell,
                  let indexPath = collectionView.indexPath(for: cell) else { continue }
            // Suffix cells (suggestions, "+") never carry a selection ring
            guard indexPath.item < connections.count,
                  let userId = connections[indexPath.item].connectedUser?.id else {
                userCell.setSelectedHighlight(false)
                continue
            }
            let isSelected = selectedUserId.map { IDNormalizer.isSameUser($0, userId) } ?? false
            userCell.setSelectedHighlight(isSelected)
        }
    }

    /// Moves the selected connection to the front of the list with an animated
    /// move (not a full reload). Score-based re-sorts on refresh must never
    /// shuffle the selected avatar away from position 0 while its filter is active.
    private func animateSelectedToFront() {
        guard let selectedUserId = selectedUserId,
              let index = connections.firstIndex(where: { connection in
                  guard let userId = connection.connectedUser?.id else { return false }
                  return IDNormalizer.isSameUser(selectedUserId, userId)
              }),
              index > 0 else {
            // Nothing to reorder — just make sure the front is visible when a
            // selection was cleared
            if selectedUserId == nil, !connections.isEmpty {
                collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .left, animated: true)
            }
            return
        }
        collectionView.performBatchUpdates({
            let selected = connections.remove(at: index)
            connections.insert(selected, at: 0)
            collectionView.moveItem(at: IndexPath(item: index, section: 0), to: IndexPath(item: 0, section: 0))
        }, completion: { [weak self] _ in
            self?.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .left, animated: true)
        })
    }

    /// Reorders the model so the selected avatar sits at index 0. Used by the
    /// data-refresh path (which does its own reloadData), separate from the
    /// selection animation above.
    private func applySelectionPinning() {
        guard let selectedUserId = selectedUserId,
              let index = connections.firstIndex(where: { connection in
                  guard let userId = connection.connectedUser?.id else { return false }
                  return IDNormalizer.isSameUser(selectedUserId, userId)
              }),
              index > 0 else { return }
        let selected = connections.remove(at: index)
        connections.insert(selected, at: 0)
    }
    
    // MARK: - Pagination Properties
    private var currentPage = 0
    private var pageSize = 10
    private var isLoadingMore = false
    private var hasMoreConnections = true
    private var allLoadedConnections: [Connection] = []
    private var maxPages = 50 // Safety limit to prevent infinite pagination
    
    // MARK: - UI Elements
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 100)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "Follow people to fill your map"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let goToNetworkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Find People to Follow →", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    
    private var hasLoadedConnections = false
    private var hasCompletedInitialLoad = false
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupCollectionView()
        
        // Register for SSE events
        SSEService.shared.addDelegate(self)
        
        // Register for connection change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionsChanged),
            name: NSNotification.Name("ConnectionsChanged"),
            object: nil
        )

        // When NetworkManager finishes a connections load and this row is
        // still showing its empty state, refresh — covers the first-launch
        // window where the row's own fetch beat the relationship writes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionsLoaded),
            name: .connectionsLoaded,
            object: nil
        )

        // Show loading state initially
        loadingIndicator.startAnimating()
        collectionView.isHidden = true

        // Paint whatever NetworkManager already holds (preload/previous
        // session) so the row is never a spinner when data exists, then load
        // fresh immediately. Painted directly (not via displayConnections) so
        // pagination state stays untouched; the in-flight first-page load
        // REPLACES this set when it lands. The old 0.5s arm timer added half
        // a second of guaranteed spinner to every launch on this init path.
        let cachedConnections = NetworkManager.shared.connections
        if !cachedConnections.isEmpty {
            Logger.debug("💾 HorizontalUserListView: Painting \(cachedConnections.count) cached connections while refreshing")
            connections = cachedConnections
            allLoadedConnections = cachedConnections
            loadingIndicator.stopAnimating()
            collectionView.reloadData()
            collectionView.isHidden = false
            emptyStateView.isHidden = true
        }
        loadActiveConnections()
    }
    
    // Initializer with preloaded connections to prevent race condition
    init(frame: CGRect = .zero, initialConnections: [Connection]?) {
        super.init(frame: frame)
        setupUI()
        setupCollectionView()
        
        // Register for SSE events
        SSEService.shared.addDelegate(self)
        
        // Register for connection change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionsChanged),
            name: NSNotification.Name("ConnectionsChanged"),
            object: nil
        )
        
        if let connections = initialConnections {
            // Use preloaded connections to prevent showing fake users
            useInitialConnections(connections)
        } else {
            // Fall back to loading from network
            loadActiveConnections()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        SSEService.shared.removeDelegate(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = Constants.Colors.background
        layer.cornerRadius = 12
        
        addSubview(collectionView)
        addSubview(loadingIndicator)
        addSubview(emptyStateView)

        // Add empty state subviews
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateView.addSubview(goToNetworkButton)

        // Add button target
        goToNetworkButton.addTarget(self, action: #selector(goToNetworkTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            // Collection view
            collectionView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            collectionView.heightAnchor.constraint(equalToConstant: 100),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            
            // Empty state container
            emptyStateView.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            
            // Empty state label
            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            // Go to network button
            goToNetworkButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 8),
            goToNetworkButton.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            goToNetworkButton.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(UserActivityCell.self, forCellWithReuseIdentifier: UserActivityCell.reuseIdentifier)

        // Add pull-to-refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        // Long-press an avatar to open that connection's profile
        // (a tap filters the map to their places instead)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        collectionView.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let location = gesture.location(in: collectionView)
        let items = displayedRowItems
        guard let indexPath = collectionView.indexPathForItem(at: location),
              indexPath.item < items.count else { return }

        switch items[indexPath.item] {
        case .connection(let connection):
            guard let user = connection.connectedUser else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            delegate?.didLongPressUser(user, connectionId: connection.id)
        case .suggestion(let user):
            // Same destination as a tap — their profile
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            delegate?.didSelectSuggestedUser(user)
        case .findPeople:
            break
        }
    }
    
    @objc private func handlePullToRefresh() {
        refresh()
        // End refreshing after a delay to ensure smooth animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.collectionView.refreshControl?.endRefreshing()
        }
    }
    
    @objc private func goToNetworkTapped() {
        // Check button title to determine action
        if goToNetworkButton.currentTitle == "Try again" {
            // Reset and retry loading
            loadRetryCount = 0
            emptyStateView.isHidden = true
            loadActiveConnections()
        } else {
            // Post notification to navigate to My Network tab
            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
        }
    }

    // MARK: - Discovery suffix

    /// The "+" cell's destination: My Network tab, Discover segment. The
    /// segment post is delayed because MyNetworkViewController registers its
    /// observer in viewDidLoad, which runs on the tab switch itself.
    private func navigateToDiscover() {
        NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: .showDiscoverSegment, object: nil)
        }
    }

    /// Fills the row's tail with people worth following when it's sparse.
    /// Only runs once per load cycle, and only when every relationship is
    /// already loaded (so the suffix can't interleave with scroll paging).
    private func fetchSuggestionsIfNeeded() {
        guard showsDiscoverySuffix, !hasMoreConnections, connections.count < 8 else { return }
        fetchSuggestions { [weak self] in
            guard let self = self, !self.suggestions.isEmpty else { return }
            self.collectionView.reloadData()
        }
    }

    private func fetchSuggestions(completion: (() -> Void)? = nil) {
        guard !isFetchingSuggestions, !hasFetchedSuggestions else { completion?(); return }
        isFetchingSuggestions = true
        // Backend already excludes self, dismissed, blocked, and everyone the
        // user follows; the client just dedups against what the row shows
        APIService.shared.request(
            endpoint: "users/contacts/discover?type=all&limit=15",
            method: .get
        ) { [weak self] (result: Result<DiscoveryUsersResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingSuggestions = false
                self.hasFetchedSuggestions = true
                if case .success(let response) = result {
                    let myId = AuthService.shared.getUserId()
                    let shownIds = self.connections.compactMap { $0.connectedUser?.id }
                    let fillCount = max(3, 10 - self.connections.count)
                    self.suggestions = response.users
                        .filter { user in myId.map { !IDNormalizer.isSameUser($0, user.id) } ?? true }
                        .filter { user in !shownIds.contains { IDNormalizer.isSameUser($0, user.id) } }
                        .prefix(fillCount).map { $0 }
                    Logger.debug("🌱 HorizontalUserListView: \(self.suggestions.count) suggested people appended")
                }
                completion?()
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadActiveConnections() {
        // Only blank the UI when nothing is displayed yet. If avatars are already
        // visible, refresh silently and swap the data in when it arrives -
        // hiding a populated row behind a spinner reads as everything vanishing.
        if currentPage == 0 && connections.isEmpty {
            loadingIndicator.startAnimating()
            collectionView.isHidden = true
            emptyStateView.isHidden = true
        }
        
        // First page: the sorted active-relationships call is what the row
        // actually renders; the full connections list is only its fallback.
        // The two are independent, so they run IN PARALLEL — the old serial
        // chain (connections → active-relationships) put two full round trips
        // between launch and the spinner stopping.
        if currentPage == 0 {
            let offset = currentPage * pageSize
            var acceptedConnections = NetworkManager.shared.connections
            var connectionsError: Error?
            var activeRelationships: [Connection]?
            var activeError: Error?

            let group = DispatchGroup()

            // Reuse NetworkManager's in-memory copy when it has one — the
            // launch paths already load it once; no need for this row to
            // issue its own GET connections on top.
            if acceptedConnections.isEmpty {
                group.enter()
                NetworkManager.shared.fetchConnections { allConnections, error in
                    connectionsError = error
                    acceptedConnections = allConnections?.filter { $0.status == .accepted } ?? []
                    group.leave()
                }
            }

            group.enter()
            NetworkManager.shared.fetchActiveRelationships(limit: pageSize, offset: offset) { relationships, error in
                activeRelationships = relationships
                activeError = error
                group.leave()
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                // Preferred: backend-sorted active relationships (connections
                // + followed users)
                if let active = activeRelationships, !active.isEmpty {
                    self.hasLoadedConnections = true
                    self.displayConnections(active, alreadySorted: true, allowEmptyState: true)
                    return
                }

                // Fallback: plain accepted connections, client-side sorted
                if !acceptedConnections.isEmpty {
                    self.hasLoadedConnections = true
                    Logger.debug("🔄 HorizontalUserListView: Active relationships empty/failed — falling back to accepted connections")
                    self.displayConnections(acceptedConnections, alreadySorted: false, allowEmptyState: true)
                    return
                }

                // Nothing displayable and at least one call failed → retry
                // the load with exponential backoff (1s, 2s, 4s)
                if (activeError != nil || connectionsError != nil), self.loadRetryCount < self.maxRetries {
                    self.loadRetryCount += 1
                    let retryDelay = pow(2.0, Double(self.loadRetryCount - 1))
                    Logger.debug("🔄 HorizontalUserListView: Retrying load attempt \(self.loadRetryCount) of \(self.maxRetries) after \(retryDelay)s delay")
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                        self?.loadActiveConnections()
                    }
                    return
                }

                // Hard failure after max retries → error state with retry button
                if activeError != nil && connectionsError != nil {
                    Logger.debug("❌ HorizontalUserListView: Max retries reached, stopping load attempts")
                    self.hasLoadedConnections = true
                    self.loadingIndicator.stopAnimating()
                    self.collectionView.isHidden = true
                    self.emptyStateLabel.text = "Unable to load connections"
                    self.goToNetworkButton.setTitle("Try again", for: .normal)
                    self.emptyStateView.isHidden = false
                    return
                }

                // Genuinely empty (calls succeeded, no relationships) — the
                // empty path also handles the young-account race retry
                self.hasLoadedConnections = true
                self.displayConnections([], alreadySorted: false, allowEmptyState: true)
            }
        } else {
            // For subsequent pages, directly load more relationships
            let offset = currentPage * pageSize
            NetworkManager.shared.fetchActiveRelationships(limit: pageSize, offset: offset) { [weak self] activeRelationships, error in
                guard let self = self else { return }
                
                if let error = error {
                    Logger.debug("❌ HorizontalUserListView: Error loading more relationships: \(error)")
                    self.isLoadingMore = false
                    return
                }
                
                if let activeRelationships = activeRelationships, !activeRelationships.isEmpty {
                    self.displayConnections(activeRelationships, alreadySorted: true, allowEmptyState: true)
                } else {
                    // No more relationships available
                    Logger.debug("🔍 HorizontalUserListView: No relationships returned for page \(self.currentPage), stopping pagination")
                    self.hasMoreConnections = false
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    // MARK: - Notification Handlers
    @objc private func handleConnectionsChanged() {
        Logger.debug("🔄 HorizontalUserListView: Connections changed notification received, refreshing")
        refresh()
    }

    @objc private func handleConnectionsLoaded() {
        // Only worth a refetch when the row is visibly empty — an occupied
        // row already refreshes through its own paths
        guard !emptyStateView.isHidden || connections.isEmpty else { return }
        Logger.debug("🔄 HorizontalUserListView: Connections loaded while row empty — refreshing")
        refresh()
    }
    
    // MARK: - Public Methods
    func refresh() {
        // Reset retry count and pagination on manual refresh
        loadRetryCount = 0
        resetPagination()
        loadActiveConnections()
    }
    
    func forceRefresh() {
        Logger.debug("🔄 HorizontalUserListView: Force refresh requested - clearing all cached data")
        // Clear all cached connections
        connections.removeAll()
        allLoadedConnections.removeAll()
        loadRetryCount = 0
        resetPagination()
        hasLoadedConnections = false
        hasCompletedInitialLoad = false
        
        // Update UI immediately
        collectionView.reloadData()
        
        // Reload from network
        loadActiveConnections()
    }
    
    private func resetPagination() {
        currentPage = 0
        hasMoreConnections = true
        isLoadingMore = false
        allLoadedConnections.removeAll()
        // Suggestions refetch after the reload lands (existing ones stay
        // visible meanwhile — rowItems drops any that became connections)
        hasFetchedSuggestions = false
    }
    
    func setInitialConnections(_ connections: [Connection]) {
        // Only set if we haven't loaded connections yet to prevent overriding fresh data
        if !hasLoadedConnections {
            useInitialConnections(connections)
        }
    }
    
    // MARK: - Sorting Logic
    static func sortConnections(_ connections: [Connection]) -> [Connection] {
        // Filter for accepted connections and following relationships
        return HorizontalUserListView.rankedConnections(connections)
    }

    /// The home page's connection ordering, exposed so other surfaces (the
    /// map's Connection dropdown) list people in exactly the same order the
    /// connections row does — one ranking, learned once.
    static func rankedConnections(_ connections: [Connection]) -> [Connection] {
        let validRelationships = connections.filter {
            $0.status == .accepted || $0.relationshipType == "following"
        }

        // Sort connections by weighted score if available
        let sortedConnections = validRelationships.sorted { (a, b) in
            let aScore = a.connectionScore
            let bScore = b.connectionScore
            
            // If both connections have backend scores, trust the backend completely
            if let aScore = aScore, let bScore = bScore {
                if aScore != bScore {
                    return aScore > bScore
                }
                // If scores are equal, use display name for consistent ordering
                let aName = a.connectedUser?.displayName ?? ""
                let bName = b.connectedUser?.displayName ?? ""
                return aName < bName
            }
            
            // If only one has a score, prioritize it
            if aScore != nil && bScore == nil {
                return true
            }
            if bScore != nil && aScore == nil {
                return false
            }
            
            // If neither has a score, use simplified fallback logic
            // Priority 1: Recent messages (most recent first)
            if let aMessageTime = a.lastMessageAt, let bMessageTime = b.lastMessageAt {
                return aMessageTime > bMessageTime
            } else if a.lastMessageAt != nil {
                return true // a has messages, b doesn't - a comes first
            } else if b.lastMessageAt != nil {
                return false // b has messages, a doesn't - b comes first
            }
            
            // Priority 2: Recent activity
            let aHasActivity = (a.hasRecentPlace ?? false) || (a.hasNewActivity ?? false)
            let bHasActivity = (b.hasRecentPlace ?? false) || (b.hasNewActivity ?? false)
            if aHasActivity != bHasActivity {
                return aHasActivity
            }
            
            // Priority 3: Total places count
            let aPlaces = a.totalPlaces ?? 0
            let bPlaces = b.totalPlaces ?? 0
            if aPlaces != bPlaces {
                return aPlaces > bPlaces
            }
            
            // Default: alphabetical by name
            let aName = a.connectedUser?.displayName ?? ""
            let bName = b.connectedUser?.displayName ?? ""
            return aName < bName
        }
        
        return sortedConnections
    }
    
    // MARK: - Shared Display Logic
    private func displayConnections(_ connectionList: [Connection], alreadySorted: Bool = false, allowEmptyState: Bool = true) {
        // Only show the loading state when nothing is displayed yet; otherwise
        // keep the current avatars visible while the new data is processed
        if connections.isEmpty {
            loadingIndicator.startAnimating()
            collectionView.isHidden = true
            emptyStateView.isHidden = true
        }
        
        // Process connections on a background queue to prevent UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if !connectionList.isEmpty {
                let finalConnections: [Connection]
                
                if alreadySorted {
                    // Trust backend sorting - filter for accepted connections and following relationships
                    var validRelationships = connectionList.filter { 
                        $0.status == .accepted || $0.relationshipType == "following" 
                    }
                    
                    // CLIENT-SIDE VALIDATION: Filter out users with suspicious scores
                    // If a user has a high content score but no actual activity, it's likely a bug
                    validRelationships = validRelationships.filter { connection in
                        guard let components = connection.scoreComponents else { 
                            // No score components, keep the connection
                            return true 
                        }
                        
                        // Check for suspicious content score without actual activity
                        let hasHighContentScore = components.content >= 25.0
                        let hasNoMessages = connection.lastMessageAt == nil
                        let hasNoRecentActivity = !(connection.hasRecentPlace ?? false) && 
                                                  !(connection.hasNewActivity ?? false)
                        let totalActivityCount = connection.recentActivity?.count ?? 0
                        
                        if hasHighContentScore && hasNoMessages && hasNoRecentActivity && totalActivityCount == 0 {
                            // This is suspicious - user has high content score but no actual activity
                            Logger.debug("⚠️ FILTERING OUT: \(connection.connectedUser?.displayName ?? "Unknown") has content score \(components.content) but no actual activity")
                            return false
                        }
                        
                        return true
                    }
                    
                    finalConnections = validRelationships
                    Logger.debug("🔍 HorizontalUserListView: Using backend-sorted relationships, filtered to \(finalConnections.count) valid relationships")
                } else {
                    // Use client-side sorting for fallback data
                    let sortedConnections = HorizontalUserListView.sortConnections(connectionList)
                    finalConnections = sortedConnections
                    Logger.debug("🔍 HorizontalUserListView: Client-sorted to \(finalConnections.count) accepted connections")
                }
                Logger.debug("🔍 HorizontalUserListView: Final connections to display: \(finalConnections.count)")
                
                // Log connections being displayed
                Logger.debug("🔍 HorizontalUserListView: Final relationships in display order:")
                for (index, connection) in finalConnections.enumerated() {
                    let typeInfo = " | Type: \(connection.relationshipType ?? "connection")"
                    let messageInfo = connection.lastMessageAt != nil ? " | Has messages" : " | No messages"
                    let activityInfo = (connection.hasRecentPlace ?? false) ? " | Recent activity" : ""
                    let scoreInfo = connection.connectionScore != nil ? " | Score: \(String(format: "%.2f", connection.connectionScore!))" : " | NO SCORE"
                    let componentsInfo = connection.scoreComponents != nil ? " | Components: M:\(String(format: "%.1f", connection.scoreComponents!.messages)) E:\(String(format: "%.1f", connection.scoreComponents!.engagement)) C:\(String(format: "%.1f", connection.scoreComponents!.content)) R:\(String(format: "%.1f", connection.scoreComponents!.recency))" : ""
                    Logger.debug("   \(index + 1). \(connection.connectedUser?.displayName ?? "Unknown")\(typeInfo)\(scoreInfo)\(componentsInfo)\(messageInfo)\(activityInfo)")
                    
                    // Log missing score reasons
                    if connection.connectionScore == nil {
                        Logger.debug("      ⚠️ Missing score for \(connection.connectedUser?.displayName ?? "Unknown") - using fallback sorting")
                    }
                }
                
                // Update UI on main thread after sorting is complete
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Handle pagination: append new connections or replace for first page
                    if self.currentPage == 0 {
                        // First page: filter out any duplicate users even on first load
                        var seenUserIds = Set<String>()
                        var uniqueConnections: [Connection] = []
                        
                        for connection in finalConnections {
                            if let userId = connection.connectedUser?.id {
                                if !seenUserIds.contains(userId) {
                                    seenUserIds.insert(userId)
                                    uniqueConnections.append(connection)
                                } else {
                                    Logger.debug("⚠️ HorizontalUserListView: Filtering out duplicate user on first page: \(connection.connectedUser?.displayName ?? "Unknown") (ID: \(userId))")
                                }
                            } else {
                                // Keep connections without user data (shouldn't happen)
                                uniqueConnections.append(connection)
                            }
                        }
                        
                        self.allLoadedConnections = uniqueConnections
                        self.connections = uniqueConnections
                        self.applySelectionPinning()
                        
                        // Update pagination state for first page
                        self.hasMoreConnections = finalConnections.count == self.pageSize
                        self.currentPage += 1
                    } else {
                        // Subsequent pages: append new connections and remove duplicates
                        // Check both connection ID and user ID to prevent showing same user twice
                        let existingUserIds = Set(self.allLoadedConnections.compactMap { $0.connectedUser?.id })
                        
                        let newConnections = finalConnections.filter { newConnection in
                            // Check if connection ID already exists
                            let isDuplicateConnection = self.allLoadedConnections.contains { existingConnection in
                                existingConnection.id == newConnection.id
                            }
                            
                            // Check if user already exists (handles cases like merged accounts)
                            let isDuplicateUser = newConnection.connectedUser?.id != nil && 
                                existingUserIds.contains(newConnection.connectedUser!.id)
                            
                            if isDuplicateUser && !isDuplicateConnection {
                                Logger.debug("⚠️ HorizontalUserListView: Filtering out duplicate user: \(newConnection.connectedUser?.displayName ?? "Unknown") (ID: \(newConnection.connectedUser?.id ?? "nil"))")
                            }
                            
                            return !isDuplicateConnection && !isDuplicateUser
                        }
                        
                        // Check if we got any new connections
                        if newConnections.isEmpty && !finalConnections.isEmpty {
                            // All connections were duplicates - we've reached the end
                            Logger.debug("🔍 HorizontalUserListView: Page \(self.currentPage) returned \(finalConnections.count) connections, but all were duplicates. Stopping pagination.")
                            self.hasMoreConnections = false
                        } else if !newConnections.isEmpty {
                            // We got new connections, add them
                            self.allLoadedConnections.append(contentsOf: newConnections)
                            self.connections = self.allLoadedConnections
                            self.applySelectionPinning()
                            Logger.debug("🔍 HorizontalUserListView: Added \(newConnections.count) new connections (out of \(finalConnections.count) returned)")
                            
                            // Only increment page if we actually added new connections
                            self.currentPage += 1
                            
                            // Continue pagination if we got a full page worth of data
                            self.hasMoreConnections = finalConnections.count == self.pageSize
                        } else {
                            // Empty result - no more connections
                            self.hasMoreConnections = false
                        }
                    }
                    
                    // Always reset loading state
                    self.isLoadingMore = false
                    
                    // Mark initial load as completed
                    self.hasCompletedInitialLoad = true
                    
                    // Reset retry count on successful load
                    self.loadRetryCount = 0
                    
                    // Stop loading and show the sorted connections immediately
                    // (a 0.1s "smooth transition" delay here just held the row
                    // hostage for another frame batch)
                    self.loadingIndicator.stopAnimating()
                    self.collectionView.reloadData()
                    self.collectionView.isHidden = false
                    self.emptyStateView.isHidden = true

                    // Sparse row → top it up with people worth following
                    self.fetchSuggestionsIfNeeded()
                }
            } else {
                // No connections - show empty state only if allowed
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.connections = []
                    
                    // Only mark initial load as completed if we allow empty state
                    // This prevents showing empty state if this is a temporary/failed load
                    if allowEmptyState {
                        self.hasCompletedInitialLoad = true
                    }
                    
                    // Launch-night race (2026-08-15): a brand-new account has
                    // auto-follows of Wes+Brittany server-side, but the very
                    // first active-relationships call can land before those
                    // writes settle — retry before declaring the row empty.
                    if allowEmptyState, self.loadRetryCount < self.maxRetries,
                       let created = AuthService.shared.currentUser?.createdAt,
                       Date().timeIntervalSince(created) < 48 * 3600 {
                        self.loadRetryCount += 1
                        Logger.debug("🔄 HorizontalUserListView: Young account with empty row — retry \(self.loadRetryCount)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.loadActiveConnections()
                        }
                        return
                    }

                    if allowEmptyState && self.hasCompletedInitialLoad {
                        if self.showsDiscoverySuffix {
                            // A row of suggested faces beats a text plea —
                            // fall back to the empty state only if suggestions
                            // also come back empty
                            self.fetchSuggestions { [weak self] in
                                guard let self = self else { return }
                                if self.suggestions.isEmpty && self.connections.isEmpty {
                                    self.showEmptyStateUI()
                                } else {
                                    self.loadingIndicator.stopAnimating()
                                    self.collectionView.reloadData()
                                    self.collectionView.isHidden = false
                                    self.emptyStateView.isHidden = true
                                }
                            }
                        } else {
                            self.showEmptyStateUI()
                        }
                    } else {
                        // Keep loading state - either initial load hasn't completed or empty state not allowed
                        if !self.hasCompletedInitialLoad {
                            Logger.debug("🔍 HorizontalUserListView: Keeping loading state - initial load not completed")
                        } else {
                            Logger.debug("🔍 HorizontalUserListView: Keeping loading state - empty state not allowed")
                        }
                        // Keep the loading indicator running and views hidden
                    }
                }
            }
        }
    }
    
    /// The zero-relationships text plea (extracted so the discovery-suffix
    /// path can try suggestions first and use this only as the last resort)
    private func showEmptyStateUI() {
        Logger.debug("🔍 HorizontalUserListView: Showing empty state - no connections available")
        loadingIndicator.stopAnimating()
        collectionView.isHidden = true
        // Reset to default text when showing empty state due to no connections
        emptyStateLabel.text = "Follow people to fill your map"
        goToNetworkButton.setTitle("Find People to Follow →", for: .normal)
        emptyStateView.isHidden = false
    }

    private func useInitialConnections(_ initialConnections: [Connection]) {
        hasLoadedConnections = true
        
        Logger.debug("🔍 HorizontalUserListView: Using \(initialConnections.count) preloaded connections")
        
        // Use the shared display logic - allow empty state since these are preloaded connections
        displayConnections(initialConnections, alreadySorted: false, allowEmptyState: true)
    }
    
    func clearActivityForConnection(_ connectionId: String) {
        if let index = connections.firstIndex(where: { $0.id == connectionId }) {
            // Update local state immediately
            var updatedConnection = connections[index]
            updatedConnection.hasRecentPlace = false
            updatedConnection.hasNewActivity = false
            connections[index] = updatedConnection
            
            // Update UI immediately
            if let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? UserActivityCell {
                cell.configure(with: updatedConnection)
            }
            
            // Clear on server
            NetworkManager.shared.clearConnectionActivity(connectionId: connectionId) { [weak self] error in
                if let error = error {
                    Logger.debug("Error clearing activity: \(error)")
                } else {
                    // Refresh all connections to get latest state after clearing
                    // This ensures we get the properly calculated hasRecentPlace values
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.refresh()
                    }
                }
            }
        }
    }
    
    // MARK: - Public Properties
    var connectionCount: Int {
        return connections.count
    }
}

// MARK: - UICollectionViewDataSource
extension HorizontalUserListView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        displayedRowItems = rowItems
        return displayedRowItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserActivityCell.reuseIdentifier, for: indexPath) as! UserActivityCell
        let items = displayedRowItems
        guard indexPath.item < items.count else { return cell }
        switch items[indexPath.item] {
        case .connection(let connection):
            cell.configure(with: connection)
            let isSelected: Bool
            if let selectedUserId = selectedUserId, let userId = connection.connectedUser?.id {
                isSelected = IDNormalizer.isSameUser(selectedUserId, userId)
            } else {
                isSelected = false
            }
            cell.setSelectedHighlight(isSelected)
        case .suggestion(let user):
            cell.configure(withSuggestion: user)
            cell.setSelectedHighlight(false)
        case .findPeople:
            cell.configureAsButton(title: "Find People", icon: "plus")
            cell.setSelectedHighlight(false)
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension HorizontalUserListView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let items = displayedRowItems
        guard indexPath.item < items.count else { return }
        switch items[indexPath.item] {
        case .connection(let connection):
            if let user = connection.connectedUser {
                // Track the view
                NetworkManager.shared.trackConnectionView(connectionId: connection.id) { error in
                    if let error = error {
                        Logger.debug("Error tracking view: \(error)")
                    }
                }

                delegate?.didSelectUser(user, connectionId: connection.id)

                // Clear activity notification after viewing if they had new activity
                // or recent place. clearActivityForConnection already refreshes the
                // list after the server clears — a second refresh() here just
                // double-reloaded the row (extra avatar re-flash ~0.5s after the tap).
                if connection.hasNewActivity ?? false || connection.hasRecentPlace ?? false {
                    clearActivityForConnection(connection.id)
                }
            }
        case .suggestion(let user):
            delegate?.didSelectSuggestedUser(user)
        case .findPeople:
            navigateToDiscover()
        }
    }
    
    // MARK: - Scroll Detection for Infinite Scrolling
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let contentWidth = scrollView.contentSize.width
        let width = scrollView.frame.size.width
        
        // Check if user scrolled near the end (80% of the way)
        let threshold = width * 0.8
        
        if offsetX > contentWidth - width - threshold {
            loadMoreConnectionsIfNeeded()
        }
    }
    
    private func loadMoreConnectionsIfNeeded() {
        guard !isLoadingMore && hasMoreConnections && hasCompletedInitialLoad else {
            Logger.debug("🔄 HorizontalUserListView: Skipping load more - isLoadingMore: \(isLoadingMore), hasMoreConnections: \(hasMoreConnections), hasCompletedInitialLoad: \(hasCompletedInitialLoad)")
            return
        }
        
        // Safety check to prevent infinite pagination
        guard currentPage < maxPages else {
            Logger.debug("⚠️ HorizontalUserListView: Reached maximum page limit (\(maxPages)), stopping pagination")
            hasMoreConnections = false
            return
        }
        
        Logger.debug("🔄 HorizontalUserListView: Loading more connections - page \(currentPage)")
        isLoadingMore = true
        loadActiveConnections()
    }
}

// MARK: - SSEServiceDelegate
extension HorizontalUserListView: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        switch event.type {
        case .placeAdded, .circleCreated, .connectionActivity:
            handleActivityEvent(event)
        case .connectionAccepted, .connectionDeclined:
            // Connection status changed, refresh the list
            Logger.debug("🔄 HorizontalUserListView: Connection status changed, refreshing")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        default:
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        Logger.debug("📶 HorizontalUserListView: SSE connected")
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        Logger.debug("📶 HorizontalUserListView: SSE disconnected: \(error?.localizedDescription ?? "no error")")
    }
    
    private func handleActivityEvent(_ event: SSEEvent) {
        guard let data = event.data as? [String: Any],
              let connectionId = data["connectionId"] as? String else {
            Logger.debug("⚠️ HorizontalUserListView: Invalid activity event data")
            return
        }
        
        Logger.debug("🔄 HorizontalUserListView: Received activity event for connection \(connectionId)")
        
        // Find the connection in our current list
        if let connectionIndex = connections.firstIndex(where: { $0.id == connectionId }) {
            var updatedConnection = connections[connectionIndex]
            
            // Update the connection with recent activity
            updatedConnection.hasRecentPlace = true
            updatedConnection.hasNewActivity = true
            
            // Remove from current position
            connections.remove(at: connectionIndex)
            
            // Insert at the beginning (most recent activity first)
            connections.insert(updatedConnection, at: 0)
            
            DispatchQueue.main.async { [weak self] in
                self?.collectionView.reloadData()
                Logger.debug("✨ HorizontalUserListView: Updated UI for connection activity")
            }
        } else {
            // Connection not in current list, refresh to get updated data
            Logger.debug("🔄 HorizontalUserListView: Connection not found, refreshing list")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }
    }
}