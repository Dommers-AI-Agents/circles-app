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
        
        loadActiveConnections()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        SSEService.shared.removeDelegate(self)
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
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
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
        emptyStateLabel.isHidden = true // Hide empty state while loading
        
        // Use the active connections endpoint with message sorting
        NetworkManager.shared.fetchActiveConnections { [weak self] connections, error in
            self?.loadingIndicator.stopAnimating()
            self?.hasLoadedConnections = true
            
            print("🔍 HorizontalUserListView: Received \(connections?.count ?? 0) connections from NetworkManager")
            if let error = error {
                print("❌ HorizontalUserListView: Error loading connections: \(error)")
            }
            
            if let connections = connections, !connections.isEmpty {
                // Filter for accepted connections only
                let acceptedConnections = connections.filter { $0.status == .accepted }
                print("🔍 HorizontalUserListView: Filtered to \(acceptedConnections.count) accepted connections")
                
                
                // Sort connections by activity - messages first, then recent activity
                let sortedConnections = acceptedConnections.sorted { (a, b) in
                    // First priority: recent messages (most recent first)
                    if let aMessageTime = a.lastMessageAt, let bMessageTime = b.lastMessageAt {
                        return aMessageTime > bMessageTime
                    } else if a.lastMessageAt != nil {
                        return true // a has messages, b doesn't - a comes first
                    } else if b.lastMessageAt != nil {
                        return false // b has messages, a doesn't - b comes first
                    }
                    
                    // Second priority: recent activity (places or circles)
                    let aHasActivity = (a.hasRecentPlace ?? false) || (a.hasNewActivity ?? false)
                    let bHasActivity = (b.hasRecentPlace ?? false) || (b.hasNewActivity ?? false)
                    if aHasActivity != bHasActivity {
                        return aHasActivity
                    }
                    
                    // Third priority: view count (only if user has viewed them)
                    let aViewCount = a.viewCount ?? 0
                    let bViewCount = b.viewCount ?? 0
                    if (aViewCount > 0 || bViewCount > 0) && aViewCount != bViewCount {
                        return aViewCount > bViewCount
                    }
                    
                    // Fourth priority: total places count
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
                
                // Take top 10 for horizontal display
                self?.connections = Array(sortedConnections.prefix(10))
                print("🔍 HorizontalUserListView: Final connections to display: \(self?.connections.count ?? 0)")
                for connection in self?.connections ?? [] {
                    let messageInfo = connection.lastMessageAt != nil ? " | Last message: \(connection.lastMessageAt!)" : " | No messages"
                    let activityInfo = (connection.hasRecentPlace ?? false) ? " | Recent place" : ""
                    print("   - \(connection.connectedUser?.displayName ?? "Unknown") (status: \(connection.status.rawValue))\(messageInfo)\(activityInfo)")
                }
                self?.collectionView.reloadData()
                self?.collectionView.isHidden = false
                self?.emptyStateLabel.isHidden = true
            } else {
                // No real connections - show fake profiles for onboarding
                print("🔍 HorizontalUserListView: No connections found, showing fake profiles")
                self?.connections = self?.createFakeConnections() ?? []
                self?.collectionView.reloadData()
                self?.collectionView.isHidden = false
                self?.emptyStateLabel.isHidden = true
            }
        }
    }
    
    // MARK: - Fake Connections for Onboarding
    private func createFakeConnections() -> [Connection] {
        // Create fake user profiles
        let brittanyUser = User(
            id: "brittany-demo",
            email: "brittany.demo@favcircles.com",
            displayName: "Brittany Demo",
            profilePicture: "https://ui-avatars.com/api/?name=BD&background=FF6B6B&color=fff&size=200&font-size=0.4&bold=true",
            bio: "Discover the best fashion, beauty, and lifestyle spots in your area",
            location: "New York, NY",
            friends: nil,
            friendRequests: nil,
            isFakeProfile: true
        )
        
        let wesleyUser = User(
            id: "wesley-demo",
            email: "wesley.demo@favcircles.com",
            displayName: "Wesley Demo",
            profilePicture: "https://ui-avatars.com/api/?name=WD&background=4ECDC4&color=fff&size=200&font-size=0.4&bold=true",
            bio: "Food enthusiast and travel lover sharing hidden gems",
            location: "San Francisco, CA",
            friends: nil,
            friendRequests: nil,
            isFakeProfile: true
        )
        
        let salvatoreUser = User(
            id: "salvatore-demo",
            email: "salvatore.demo@favcircles.com",
            displayName: "Salvatore Demo",
            profilePicture: "https://ui-avatars.com/api/?name=SD&background=45B7D1&color=fff&size=200&font-size=0.4&bold=true",
            bio: "Local expert curating the best neighborhood spots",
            location: "Chicago, IL",
            friends: nil,
            friendRequests: nil,
            isFakeProfile: true
        )
        
        // Create fake connections
        let currentUserId = AuthService.shared.currentUser?.id ?? ""
        let fakeConnections = [
            Connection(
                id: "fake-1",
                userId: currentUserId,
                connectedUserId: brittanyUser.id,
                connectedUser: brittanyUser,
                status: .accepted,
                sharedCircles: nil,
                lastInteractionAt: nil,
                interactionCount: nil,
                lastAccessedCircles: nil,
                recentActivity: nil,
                hasNewActivity: false,
                viewCount: 0,
                lastViewedAt: nil,
                totalPlaces: 42,
                hasRecentPlace: true,
                lastMessageAt: nil,
                lastMessageSenderId: nil,
                hasRecentMessage: false,
                createdAt: Date(),
                acceptedAt: Date(),
                updatedAt: Date()
            ),
            Connection(
                id: "fake-2",
                userId: currentUserId,
                connectedUserId: wesleyUser.id,
                connectedUser: wesleyUser,
                status: .accepted,
                sharedCircles: nil,
                lastInteractionAt: nil,
                interactionCount: nil,
                lastAccessedCircles: nil,
                recentActivity: nil,
                hasNewActivity: false,
                viewCount: 0,
                lastViewedAt: nil,
                totalPlaces: 67,
                hasRecentPlace: true,
                lastMessageAt: nil,
                lastMessageSenderId: nil,
                hasRecentMessage: false,
                createdAt: Date(),
                acceptedAt: Date(),
                updatedAt: Date()
            ),
            Connection(
                id: "fake-3",
                userId: currentUserId,
                connectedUserId: salvatoreUser.id,
                connectedUser: salvatoreUser,
                status: .accepted,
                sharedCircles: nil,
                lastInteractionAt: nil,
                interactionCount: nil,
                lastAccessedCircles: nil,
                recentActivity: nil,
                hasNewActivity: false,
                viewCount: 0,
                lastViewedAt: nil,
                totalPlaces: 89,
                hasRecentPlace: true,
                lastMessageAt: nil,
                lastMessageSenderId: nil,
                hasRecentMessage: false,
                createdAt: Date(),
                acceptedAt: Date(),
                updatedAt: Date()
            )
        ]
        
        return fakeConnections
    }
    
    // MARK: - Public Methods
    func refresh() {
        loadActiveConnections()
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
        // Add one extra cell for "Find More" button if showing fake connections
        let showingFakeConnections = connections.first?.id.hasPrefix("fake-") ?? false
        return showingFakeConnections ? connections.count + 1 : connections.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserActivityCell.reuseIdentifier, for: indexPath) as! UserActivityCell
        
        let showingFakeConnections = connections.first?.id.hasPrefix("fake-") ?? false
        
        if showingFakeConnections && indexPath.item == connections.count {
            // Configure as "Find More" button
            cell.configureAsButton(title: "Find More", icon: "plus.circle.fill")
        } else {
            cell.configure(with: connections[indexPath.item])
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension HorizontalUserListView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let showingFakeConnections = connections.first?.id.hasPrefix("fake-") ?? false
        
        if showingFakeConnections && indexPath.item == connections.count {
            // Handle "Find More" button tap - navigate to My Network tab
            if let tabBarController = self.window?.rootViewController as? CirclesTabBarController {
                tabBarController.selectedIndex = 1 // My Network tab
            }
            return
        }
        
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