import UIKit

protocol GroupConnectionSelectionViewControllerDelegate: AnyObject {
    func didSelectConnections(_ connections: [Connection], groupName: String?)
}

class GroupConnectionSelectionViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let groupNameContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let groupNameLabel: UILabel = {
        let label = UILabel()
        label.text = "Group Name"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let groupNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter group name (optional)"
        textField.font = .systemFont(ofSize: 16)
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .singleLine
        table.backgroundColor = .systemBackground
        return table
    }()
    
    private let searchController = UISearchController(searchResultsController: nil)
    
    private let bottomToolbar: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let selectedCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0 selected"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var createButton = UIButton.primaryButton(title: "Create Group")
    
    // MARK: - Properties
    weak var delegate: GroupConnectionSelectionViewControllerDelegate?
    private var connections: [Connection] = []
    private var filteredConnections: [Connection] = []
    private var selectedConnections: Set<String> = [] // Store connection IDs
    private let cellIdentifier = "GroupConnectionCell"
    
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
        updateCreateButtonState()
    }
    
    // MARK: - Setup
    private func setupView() {
        setupNavigationBar(title: "New Group Message")
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        view.addSubview(groupNameContainer)
        groupNameContainer.addSubview(groupNameLabel)
        groupNameContainer.addSubview(groupNameTextField)
        view.addSubview(tableView)
        view.addSubview(bottomToolbar)
        bottomToolbar.addSubview(selectedCountLabel)
        bottomToolbar.addSubview(createButton)
        
        createButton.isEnabled = false
        createButton.addTarget(self, action: #selector(createButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Group name container
            groupNameContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            groupNameContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            groupNameContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Group name label
            groupNameLabel.topAnchor.constraint(equalTo: groupNameContainer.topAnchor, constant: 12),
            groupNameLabel.leadingAnchor.constraint(equalTo: groupNameContainer.leadingAnchor, constant: 16),
            
            // Group name text field
            groupNameTextField.topAnchor.constraint(equalTo: groupNameLabel.bottomAnchor, constant: 8),
            groupNameTextField.leadingAnchor.constraint(equalTo: groupNameContainer.leadingAnchor, constant: 16),
            groupNameTextField.trailingAnchor.constraint(equalTo: groupNameContainer.trailingAnchor, constant: -16),
            groupNameTextField.bottomAnchor.constraint(equalTo: groupNameContainer.bottomAnchor, constant: -12),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: groupNameContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            
            // Bottom toolbar
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 80),
            
            // Selected count label
            selectedCountLabel.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 16),
            selectedCountLabel.centerYAnchor.constraint(equalTo: bottomToolbar.centerYAnchor),
            
            // Create button
            createButton.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor, constant: -16),
            createButton.centerYAnchor.constraint(equalTo: bottomToolbar.centerYAnchor),
            createButton.widthAnchor.constraint(equalToConstant: 120),
            createButton.heightAnchor.constraint(equalToConstant: 44)
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
        tableView.allowsMultipleSelection = true
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
    
    @objc private func createButtonTapped() {
        // Get selected connections
        let selected = connections.filter { connection in
            selectedConnections.contains(connection.id)
        }
        
        // Get group name
        let groupName = groupNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Dismiss and notify delegate
        dismiss(animated: true) { [weak self] in
            self?.delegate?.didSelectConnections(selected, groupName: groupName)
        }
    }
    
    // MARK: - Helper Methods
    private func filterConnections(with searchText: String) {
        if searchText.isEmpty {
            filteredConnections = connections
        } else {
            filteredConnections = connections.filter { connection in
                let displayName = connection.connectedUser?.displayName ?? ""
                return displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        tableView.reloadData()
    }
    
    private func updateCreateButtonState() {
        let selectedCount = selectedConnections.count
        selectedCountLabel.text = "\(selectedCount) selected"
        createButton.isEnabled = selectedCount >= 2
    }
}

// MARK: - UITableViewDataSource
extension GroupConnectionSelectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filteredConnections.count : connections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        
        let connection = isSearching ? filteredConnections[indexPath.row] : connections[indexPath.row]
        let user = connection.connectedUser
        
        cell.textLabel?.text = user?.displayName ?? "Unknown User"
        
        // Configure selection state
        if selectedConnections.contains(connection.id) {
            cell.accessoryType = .checkmark
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            cell.accessoryType = .none
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension GroupConnectionSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let connection = isSearching ? filteredConnections[indexPath.row] : connections[indexPath.row]
        selectedConnections.insert(connection.id)
        
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
        }
        
        updateCreateButtonState()
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let connection = isSearching ? filteredConnections[indexPath.row] : connections[indexPath.row]
        selectedConnections.remove(connection.id)
        
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .none
        }
        
        updateCreateButtonState()
    }
}

// MARK: - UISearchResultsUpdating
extension GroupConnectionSelectionViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterConnections(with: searchController.searchBar.text ?? "")
    }
}