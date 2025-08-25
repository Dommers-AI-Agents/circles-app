import UIKit

protocol AddParticipantsDelegate: AnyObject {
    func addParticipants(_ controller: AddParticipantsViewController, didSelectUsers users: [User])
}

class AddParticipantsViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: AddParticipantsDelegate?
    private var existingParticipantIds: Set<String> = []
    private var connections: [User] = []
    private var filteredConnections: [User] = []
    private var selectedUsers: Set<String> = []
    private var isSearching = false
    
    // MARK: - UI Elements
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search connections"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UserSelectionCell.self, forCellReuseIdentifier: "UserSelectionCell")
        tableView.separatorStyle = .singleLine
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()
    
    private lazy var addButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: "Add", style: .done, target: self, action: #selector(addButtonTapped))
        button.isEnabled = false
        return button
    }()
    
    // MARK: - Initialization
    init(existingParticipantIds: [String]) {
        self.existingParticipantIds = Set(existingParticipantIds)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add Participants"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
        navigationItem.rightBarButtonItem = addButton
        
        setupUI()
        loadConnections()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(searchBar)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        loadConnections(completion: completion)
    }
    
    private func loadConnections(completion: (() -> Void)? = nil) {
        NetworkManager.shared.fetchConnections { [weak self] connections, error in
            guard let self = self else { 
                completion?()
                return 
            }
            
            DispatchQueue.main.async {
                if let error = error {
                    self.showError("Failed to load connections: \(error.localizedDescription)")
                    completion?()
                    return
                }
                
                if let allConnections = connections {
                    // Extract connected users from connections and filter
                    let connectedUsers = allConnections.compactMap { connection -> User? in
                        // Only include accepted connections
                        guard connection.status == .accepted,
                              let connectedUser = connection.connectedUser,
                              !self.existingParticipantIds.contains(connectedUser.id) else {
                            return nil
                        }
                        return connectedUser
                    }
                    
                    self.connections = connectedUsers
                    self.filteredConnections = self.connections
                    self.tableView.reloadData()
                    
                    // Show empty state if no connections available
                    if self.connections.isEmpty {
                        self.showEmptyState()
                    }
                }
                completion?()
            }
        }
    }
    
    private func showEmptyState() {
        let emptyLabel = UILabel()
        emptyLabel.text = "No connections available to add"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont.systemFont(ofSize: 16)
        tableView.backgroundView = emptyLabel
    }
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addButtonTapped() {
        let selectedUsersList = connections.filter { selectedUsers.contains($0.id) }
        delegate?.addParticipants(self, didSelectUsers: selectedUsersList)
    }
    
    private func updateAddButtonState() {
        addButton.isEnabled = !selectedUsers.isEmpty
        
        // Update button title to show count
        if selectedUsers.count > 0 {
            addButton.title = "Add (\(selectedUsers.count))"
        } else {
            addButton.title = "Add"
        }
    }
    
    // MARK: - Search
    private func filterConnections(with searchText: String) {
        if searchText.isEmpty {
            filteredConnections = connections
            isSearching = false
        } else {
            isSearching = true
            filteredConnections = connections.filter { user in
                user.displayName.localizedCaseInsensitiveContains(searchText) ||
                (user.email?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource
extension AddParticipantsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredConnections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserSelectionCell", for: indexPath) as! UserSelectionCell
        let user = filteredConnections[indexPath.row]
        let isSelected = selectedUsers.contains(user.id)
        cell.configure(with: user, isSelected: isSelected)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AddParticipantsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let user = filteredConnections[indexPath.row]
        
        if selectedUsers.contains(user.id) {
            selectedUsers.remove(user.id)
        } else {
            selectedUsers.insert(user.id)
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
        updateAddButtonState()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UISearchBarDelegate
extension AddParticipantsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filterConnections(with: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UserSelectionCell
private class UserSelectionCell: UITableViewCell {
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -12),
            
            emailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            emailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with user: User, isSelected: Bool) {
        nameLabel.text = user.displayName
        emailLabel.text = user.email ?? ""
        checkmarkImageView.isHidden = !isSelected
        
        // Load profile image
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.lightGray
        }
    }
}