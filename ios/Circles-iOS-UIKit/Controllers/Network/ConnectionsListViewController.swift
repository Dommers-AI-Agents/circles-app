import UIKit

class ConnectionsListViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No Connections Yet\n\nStart building your network by inviting people to connect with you." }
    
    // MARK: - Properties
    private var connections: [Connection] = []
    private var pendingConnections: [Connection] = []
    private let cellIdentifier = "ConnectionCell"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        loadConnections()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadConnections()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ConnectionCell.self, forCellReuseIdentifier: cellIdentifier)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshConnections), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    
    // MARK: - Data Loading
    func loadConnections() {
        NetworkManager.shared.loadConnections()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.tableView.refreshControl?.endRefreshing()
            
            // Get connections from NetworkManager
            self?.connections = NetworkManager.shared.connections
            self?.pendingConnections = NetworkManager.shared.pendingConnections
            self?.tableView.reloadData()
            
            if self?.connections.isEmpty == true && self?.pendingConnections.isEmpty == true {
                self?.showEmptyState()
            } else {
                self?.hideEmptyState()
            }
        }
    }
    
    @objc private func refreshConnections() {
        loadConnections()
    }
    
    
    // MARK: - Navigation
    private func showConnectionDetail(_ connection: Connection) {
        // Use ProfileViewController for viewing connection profiles
        guard let connectedUser = connection.connectedUser else { return }
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: connectedUser)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension ConnectionsListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return connections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! ConnectionCell
        let connection = connections[indexPath.row]
        
        cell.configure(with: connection)
        cell.delegate = self
        cell.indexPath = indexPath
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ConnectionsListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let connection = connections[indexPath.row]
        showConnectionDetail(connection)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - ConnectionCellDelegate
extension ConnectionsListViewController: ConnectionCellDelegate {
    func connectionCell(_ cell: ConnectionCell, didTapViewButton connection: Connection) {
        showConnectionDetail(connection)
    }
    
    func connectionCell(_ cell: ConnectionCell, didTapRemoveButton connection: Connection) {
        let alert = UIAlertController(
            title: "Remove Connection",
            message: "Are you sure you want to remove \(connection.connectedUser?.displayName ?? "this user") from your connections?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            // Show loading
            let loadingAlert = UIAlertController(title: "Removing...", message: nil, preferredStyle: .alert)
            self?.present(loadingAlert, animated: true)
            
            NetworkManager.shared.removeConnection(connectionId: connection.id) { error in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        if let error = error {
                            // Handle error case
                            let errorAlert = UIAlertController(
                                title: "Error",
                                message: error.localizedDescription,
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self?.present(errorAlert, animated: true)
                        } else {
                            // Handle success case - reload connections
                            self?.loadConnections()
                            
                            let successAlert = UIAlertController(
                                title: "Connection Removed",
                                message: "You are no longer connected with \(connection.connectedUser?.displayName ?? "this user").",
                                preferredStyle: .alert
                            )
                            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self?.present(successAlert, animated: true)
                        }
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - ConnectionCell
protocol ConnectionCellDelegate: AnyObject {
    func connectionCell(_ cell: ConnectionCell, didTapViewButton connection: Connection)
    func connectionCell(_ cell: ConnectionCell, didTapRemoveButton connection: Connection)
}

class ConnectionCell: UITableViewCell {
    weak var delegate: ConnectionCellDelegate?
    var indexPath: IndexPath?
    private var connection: Connection?
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let viewButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("View", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = Constants.Colors.primary
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 6
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.setTitleColor(.systemRed, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = .systemBackground
        selectionStyle = .none
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(viewButton)
        contentView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: viewButton.leadingAnchor, constant: -8),
            
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            emailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailLabel.trailingAnchor.constraint(lessThanOrEqualTo: viewButton.leadingAnchor, constant: -8),
            
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.widthAnchor.constraint(equalToConstant: 70),
            removeButton.heightAnchor.constraint(equalToConstant: 32),
            
            viewButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            viewButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            viewButton.widthAnchor.constraint(equalToConstant: 60),
            viewButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        viewButton.addTarget(self, action: #selector(viewButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
    }
    
    func configure(with connection: Connection) {
        self.connection = connection
        nameLabel.text = connection.connectedUser?.displayName ?? "Unknown User"
        emailLabel.text = connection.connectedUser?.email ?? ""
        
        // Set profile image
        if let profilePicture = connection.connectedUser?.profilePicture {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = .systemGray3
        }
    }
    
    @objc private func viewButtonTapped() {
        guard let connection = connection else { return }
        delegate?.connectionCell(self, didTapViewButton: connection)
    }
    
    @objc private func removeButtonTapped() {
        guard let connection = connection else { return }
        delegate?.connectionCell(self, didTapRemoveButton: connection)
    }
}