import UIKit

protocol HorizontalUserListViewDelegate: AnyObject {
    func didSelectUser(_ user: User, connectionId: String)
}

class HorizontalUserListView: UIView, SSEServiceDelegate {
    
    // MARK: - Properties
    weak var delegate: HorizontalUserListViewDelegate?
    private var connections: [Connection] = []
    
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
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No connections yet"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var hasLoadedConnections = false
    
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
        
        // Don't automatically load connections - wait for either:
        // 1. Initial connections to be set via setInitialConnections()
        // 2. Manual refresh() call
        // This prevents showing fake users during app startup
        
        // Show loading state initially
        loadingIndicator.startAnimating()
        collectionView.isHidden = true
        
        // Set a timer to load connections if initial connections aren't provided quickly
        // This prevents the view from staying in loading state indefinitely
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if !self.hasLoadedConnections {
                print("⏰ HorizontalUserListView: No initial connections received after 0.5 seconds, loading from network")
                self.loadActiveConnections()
            }
        }
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
        addSubview(emptyStateLabel)
        
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
            
            // Empty state
            emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
        ])
    }
    
    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(UserActivityCell.self, forCellWithReuseIdentifier: UserActivityCell.reuseIdentifier)
    }
    
    // MARK: - Data Loading
    private func loadActiveConnections() {
        loadingIndicator.startAnimating()
        collectionView.isHidden = true
        emptyStateLabel.isHidden = true
        
        // First, check if user has ANY connections at all
        NetworkManager.shared.fetchConnections { [weak self] allConnections, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ HorizontalUserListView: Error checking connections: \(error)")
                self.hasLoadedConnections = true
                self.loadingIndicator.stopAnimating()
                self.emptyStateLabel.isHidden = false
                return
            }
            
            let acceptedConnections = allConnections?.filter { $0.status == .accepted } ?? []
            print("🔍 HorizontalUserListView: User has \(acceptedConnections.count) accepted connections total")
            
            if acceptedConnections.isEmpty {
                // User truly has no connections - but still try active connections endpoint
                print("🔍 HorizontalUserListView: No accepted connections found, checking active connections endpoint")
                
                NetworkManager.shared.fetchActiveConnections { [weak self] activeConnections, error in
                    guard let self = self else { return }
                    
                    self.hasLoadedConnections = true
                    
                    // If active connections also returns empty, then truly show empty state
                    print("🔍 HorizontalUserListView: Active connections check complete - truly no connections")
                    self.displayConnections([], alreadySorted: false, allowEmptyState: true)
                }
            } else {
                // User has connections - try to get active ones, but fall back to all if needed
                NetworkManager.shared.fetchActiveConnections { [weak self] activeConnections, error in
                    guard let self = self else { return }
                    
                    self.hasLoadedConnections = true
                    
                    print("🔍 HorizontalUserListView: Received \(activeConnections?.count ?? 0) active connections")
                    if let error = error {
                        print("❌ HorizontalUserListView: Error loading active connections: \(error)")
                    }
                    
                    // Debug: Log all active connections received from backend
                    if let activeConnections = activeConnections {
                        print("🔍 HorizontalUserListView: Raw active connections from backend:")
                        for (index, connection) in activeConnections.enumerated() {
                            let name = connection.connectedUser?.displayName ?? "Unknown"
                            let score = connection.connectionScore != nil ? String(format: "%.2f", connection.connectionScore!) : "NO SCORE"
                            let hasMessages = connection.lastMessageAt != nil ? "✓" : "✗"
                            let hasActivity = (connection.hasRecentPlace ?? false) ? "✓" : "✗"
                            print("   \(index + 1). \(name) | Score: \(score) | Messages: \(hasMessages) | Activity: \(hasActivity)")
                            
                            // Special attention to Dan Wickner
                            if name.lowercased().contains("dan") || name.lowercased().contains("wickner") {
                                print("      🎯 FOUND DAN WICKNER at position \(index + 1)")
                                if let components = connection.scoreComponents {
                                    print("      Score components: M:\(components.messages) E:\(components.engagement) C:\(components.content) R:\(components.recency)")
                                }
                            }
                        }
                    }
                    
                    if let activeConnections = activeConnections, !activeConnections.isEmpty {
                        // Use active connections (already sorted by backend)
                        print("🔍 HorizontalUserListView: ✅ USING BACKEND-SORTED ACTIVE CONNECTIONS")
                        print("🔍 HorizontalUserListView: This should preserve backend ordering with Dan first if scored correctly")
                        self.displayConnections(activeConnections, alreadySorted: true, allowEmptyState: true)
                    } else {
                        // Fall back to all connections if active endpoint returns empty
                        print("🔍 HorizontalUserListView: ❌ FALLING BACK TO CLIENT-SIDE SORTING")
                        print("🔍 HorizontalUserListView: This means active endpoint failed or returned empty")
                        self.displayConnections(acceptedConnections, alreadySorted: false, allowEmptyState: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    func refresh() {
        loadActiveConnections()
    }
    
    func setInitialConnections(_ connections: [Connection]) {
        // Only set if we haven't loaded connections yet to prevent overriding fresh data
        if !hasLoadedConnections {
            useInitialConnections(connections)
        }
    }
    
    // MARK: - Notification Handlers
    @objc private func handleConnectionsChanged() {
        print("🔄 HorizontalUserListView: Connections changed notification received, refreshing")
        refresh()
    }
    
    // MARK: - Sorting Logic
    static func sortConnections(_ connections: [Connection]) -> [Connection] {
        // Filter for accepted connections only
        let acceptedConnections = connections.filter { $0.status == .accepted }
        
        // Sort connections by weighted score if available
        let sortedConnections = acceptedConnections.sorted { (a, b) in
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
        // Keep loading state visible while we process and sort connections
        loadingIndicator.startAnimating()
        collectionView.isHidden = true
        emptyStateLabel.isHidden = true
        
        // Process connections on a background queue to prevent UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if !connectionList.isEmpty {
                let finalConnections: [Connection]
                
                if alreadySorted {
                    // Trust backend sorting - just filter for accepted and take top 10
                    let acceptedConnections = connectionList.filter { $0.status == .accepted }
                    finalConnections = Array(acceptedConnections.prefix(10))
                    print("🔍 HorizontalUserListView: Using backend-sorted connections, filtered to \(finalConnections.count) accepted")
                } else {
                    // Use client-side sorting for fallback data
                    let sortedConnections = HorizontalUserListView.sortConnections(connectionList)
                    finalConnections = Array(sortedConnections.prefix(10))
                    print("🔍 HorizontalUserListView: Client-sorted to \(finalConnections.count) accepted connections")
                }
                print("🔍 HorizontalUserListView: Final connections to display: \(finalConnections.count)")
                
                // Log connections being displayed
                print("🔍 HorizontalUserListView: Final connections in display order:")
                for (index, connection) in finalConnections.enumerated() {
                    let messageInfo = connection.lastMessageAt != nil ? " | Has messages" : " | No messages"
                    let activityInfo = (connection.hasRecentPlace ?? false) ? " | Recent activity" : ""
                    let scoreInfo = connection.connectionScore != nil ? " | Score: \(String(format: "%.2f", connection.connectionScore!))" : " | NO SCORE"
                    let componentsInfo = connection.scoreComponents != nil ? " | Components: M:\(String(format: "%.1f", connection.scoreComponents!.messages)) E:\(String(format: "%.1f", connection.scoreComponents!.engagement)) C:\(String(format: "%.1f", connection.scoreComponents!.content)) R:\(String(format: "%.1f", connection.scoreComponents!.recency))" : ""
                    print("   \(index + 1). \(connection.connectedUser?.displayName ?? "Unknown")\(scoreInfo)\(componentsInfo)\(messageInfo)\(activityInfo)")
                    
                    // Log missing score reasons
                    if connection.connectionScore == nil {
                        print("      ⚠️ Missing score for \(connection.connectedUser?.displayName ?? "Unknown") - using fallback sorting")
                    }
                }
                
                // Update UI on main thread after sorting is complete
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Update connections
                    self.connections = finalConnections
                    
                    // Stop loading and show the sorted connections
                    self.loadingIndicator.stopAnimating()
                    
                    // Small delay ensures smooth transition from loading to content
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.collectionView.reloadData()
                        self?.collectionView.isHidden = false
                        self?.emptyStateLabel.isHidden = true
                    }
                }
            } else {
                // No connections - show empty state only if allowed
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.connections = []
                    
                    if allowEmptyState {
                        // Show empty state - user truly has no connections
                        print("🔍 HorizontalUserListView: Showing empty state - no connections available")
                        self.loadingIndicator.stopAnimating()
                        self.collectionView.isHidden = true
                        self.emptyStateLabel.isHidden = false
                    } else {
                        // Keep loading state - this might be temporary (e.g., active connections failed but fallback is coming)
                        print("🔍 HorizontalUserListView: Keeping loading state - empty state not allowed")
                        // Keep the loading indicator running and views hidden
                    }
                }
            }
        }
    }
    
    private func useInitialConnections(_ initialConnections: [Connection]) {
        hasLoadedConnections = true
        
        print("🔍 HorizontalUserListView: Using \(initialConnections.count) preloaded connections")
        
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
                    print("Error clearing activity: \(error)")
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
}

// MARK: - UICollectionViewDataSource
extension HorizontalUserListView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return connections.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserActivityCell.reuseIdentifier, for: indexPath) as! UserActivityCell
        cell.configure(with: connections[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension HorizontalUserListView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let connection = connections[indexPath.item]
        if let user = connection.connectedUser {
            // Track the view
            NetworkManager.shared.trackConnectionView(connectionId: connection.id) { error in
                if let error = error {
                    print("Error tracking view: \(error)")
                }
            }
            
            delegate?.didSelectUser(user, connectionId: connection.id)
            
            // Clear activity notification after viewing if they had new activity or recent place
            if connection.hasNewActivity ?? false || connection.hasRecentPlace ?? false {
                // Just call clearActivityForConnection which now handles everything
                clearActivityForConnection(connection.id)
                
                // Refresh all connections after viewing to ensure UI stays in sync
                // This fixes the issue where all dots become solid after viewing one connection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.refresh()
                }
            }
        }
    }
}

// MARK: - SSEServiceDelegate
extension HorizontalUserListView {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        switch event.type {
        case .placeAdded, .circleCreated, .connectionActivity:
            handleActivityEvent(event)
        case .connectionAccepted, .connectionDeclined:
            // Connection status changed, refresh the list
            print("🔄 HorizontalUserListView: Connection status changed, refreshing")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        default:
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        print("📶 HorizontalUserListView: SSE connected")
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        print("📶 HorizontalUserListView: SSE disconnected: \(error?.localizedDescription ?? "no error")")
    }
    
    private func handleActivityEvent(_ event: SSEEvent) {
        guard let data = event.data as? [String: Any],
              let connectionId = data["connectionId"] as? String else {
            print("⚠️ HorizontalUserListView: Invalid activity event data")
            return
        }
        
        print("🔄 HorizontalUserListView: Received activity event for connection \(connectionId)")
        
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
                print("✨ HorizontalUserListView: Updated UI for connection activity")
            }
        } else {
            // Connection not in current list, refresh to get updated data
            print("🔄 HorizontalUserListView: Connection not found, refreshing list")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }
    }
}