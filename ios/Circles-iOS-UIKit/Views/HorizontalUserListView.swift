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
        
        // Use the regular connections endpoint that works
        NetworkManager.shared.fetchConnections { [weak self] connections, error in
            self?.loadingIndicator.stopAnimating()
            
            if let connections = connections, !connections.isEmpty {
                // Filter for accepted connections only
                let acceptedConnections = connections.filter { $0.status == .accepted }
                
                // Debug: Log connection data
                for conn in acceptedConnections {
                    print("Connection: \(conn.connectedUser?.displayName ?? "Unknown") - Places: \(conn.totalPlaces ?? -1), Views: \(conn.viewCount ?? 0), Status: \(conn.status.rawValue)")
                }
                
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
            // Update UI immediately
            if let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? UserActivityCell {
                cell.configure(with: connections[index])
            }
            
            // Clear on server
            NetworkManager.shared.clearConnectionActivity(connectionId: connectionId) { error in
                if let error = error {
                    print("Error clearing activity: \(error)")
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
            
            // Clear activity notification after viewing if they had new activity
            if connection.hasNewActivity ?? false {
                clearActivityForConnection(connection.id)
            }
        }
    }
}