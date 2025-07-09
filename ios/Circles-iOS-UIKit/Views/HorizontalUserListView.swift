import UIKit

protocol HorizontalUserListViewDelegate: AnyObject {
    func didSelectUser(_ user: User, connectionId: String)
}

class HorizontalUserListView: UIView {
    
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
        loadActiveConnections()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        
        // Use the regular connections endpoint that works
        NetworkManager.shared.fetchConnections { [weak self] connections, error in
            self?.loadingIndicator.stopAnimating()
            self?.hasLoadedConnections = true
            
            if let connections = connections, !connections.isEmpty {
                // Filter for accepted connections only
                let acceptedConnections = connections.filter { $0.status == .accepted }
                
                
                // Sort connections by activity (places, view count, recent activity)
                let sortedConnections = acceptedConnections.sorted { (a, b) in
                    // Get values with defaults
                    let aViewCount = a.viewCount ?? 0
                    let bViewCount = b.viewCount ?? 0
                    let aPlaces = a.totalPlaces ?? 0
                    let bPlaces = b.totalPlaces ?? 0
                    let aRecent = a.hasRecentPlace ?? false
                    let bRecent = b.hasRecentPlace ?? false
                    
                    // If user has viewed connections, prioritize by view count
                    if aViewCount > 0 || bViewCount > 0 {
                        // First priority: view count (only if at least one has been viewed)
                        if aViewCount != bViewCount {
                            return aViewCount > bViewCount
                        }
                    }
                    
                    // Default priority when no views: total places
                    if aPlaces != bPlaces {
                        return aPlaces > bPlaces
                    }
                    
                    // Third priority: recent place activity
                    if aRecent != bRecent {
                        return aRecent
                    }
                    
                    // Default: alphabetical by name
                    let aName = a.connectedUser?.displayName ?? ""
                    let bName = b.connectedUser?.displayName ?? ""
                    return aName < bName
                }
                
                // Take top 10 for horizontal display
                self?.connections = Array(sortedConnections.prefix(10))
                self?.collectionView.reloadData()
                self?.collectionView.isHidden = false
                self?.emptyStateLabel.isHidden = true
            } else {
                self?.collectionView.isHidden = true
                // Only show empty state if we've actually loaded connections
                self?.emptyStateLabel.isHidden = false
            }
        }
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