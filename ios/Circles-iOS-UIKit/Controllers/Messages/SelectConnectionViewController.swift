import UIKit

protocol SelectConnectionViewControllerDelegate: AnyObject {
    func didSelectConnection(_ connection: Connection)
}

class SelectConnectionViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .singleLine
        table.backgroundColor = .systemBackground
        return table
    }()
    
    private let searchController = UISearchController(searchResultsController: nil)
    
    // MARK: - Properties
    weak var delegate: SelectConnectionViewControllerDelegate?
    private var connections: [Connection] = []
    private var filteredConnections: [Connection] = []
    private let cellIdentifier = "ConnectionCell"
    
    private var isSearching: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var emptyStateMessage: String? { "No connections available" }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupSearchController()
        setupTableView()
    }
    
    // MARK: - Setup
    private func setupView() {
        setupNavigationBar(title: "New Message")
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search connections"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
    }
    
    // MARK: - BaseViewController Implementation
    override func loadData(completion: (() -> Void)?) {
        // Get connections from NetworkManager
        connections = NetworkManager.shared.connections
        filteredConnections = connections
        
        // Update empty state
        if connections.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
        
        tableView.reloadData()
        completion?()
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Helper Methods
    private func filterConnections(with searchText: String) {
        filteredConnections = connections.filter { connection in
            let displayName = connection.connectedUser?.displayName ?? ""
            let email = connection.connectedUser?.email ?? ""
            return displayName.lowercased().contains(searchText.lowercased()) ||
                   email.lowercased().contains(searchText.lowercased())
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource
extension SelectConnectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filteredConnections.count : connections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        
        let connection = isSearching ? filteredConnections[indexPath.row] : connections[indexPath.row]
        
        var configuration = cell.defaultContentConfiguration()
        configuration.text = connection.connectedUser?.displayName ?? "Unknown User"
        configuration.secondaryText = connection.connectedUser?.email ?? ""
        configuration.image = UIImage(systemName: "person.circle.fill")
        configuration.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = configuration
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension SelectConnectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let connection = isSearching ? filteredConnections[indexPath.row] : connections[indexPath.row]
        delegate?.didSelectConnection(connection)
        dismiss(animated: true)
    }
}

// MARK: - UISearchResultsUpdating
extension SelectConnectionViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        if let searchText = searchController.searchBar.text {
            filterConnections(with: searchText)
        }
    }
}