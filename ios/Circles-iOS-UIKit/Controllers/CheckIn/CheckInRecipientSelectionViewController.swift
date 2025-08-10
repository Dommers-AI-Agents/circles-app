import UIKit

protocol CheckInRecipientSelectionDelegate: AnyObject {
    func didCompleteCheckIn()
}

class CheckInRecipientSelectionViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: CheckInRecipientSelectionDelegate?
    var checkInData: [String: Any] = [:]
    
    private var groups: [Conversation] = []
    private var connections: [Connection] = []
    private var selectedGroups: Set<String> = []
    private var selectedUsers: Set<String> = []
    private var currentTab = 0 // 0 = Groups, 1 = People
    
    // MARK: - Configuration
    override var showsLoadingIndicator: Bool { true }
    
    // MARK: - UI Elements
    private let stepIndicatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let stepLabel: UILabel = {
        let label = UILabel()
        label.text = "Step 3 of 3: Who to Notify"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.progressTintColor = Constants.Colors.primary
        progress.trackTintColor = Constants.Colors.lightGray
        progress.setProgress(1.0, animated: false)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Select groups or people to notify about your check-in"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let recipientTabBar: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Groups", "People"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let recipientTableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.background
        table.allowsMultipleSelection = true
        return table
    }()
    
    private let selectedCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0 selected"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var checkInButton = UIButton.primaryButton(title: "Check In")
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Clear any pending API requests
        APIService.shared.clearPendingRequestsForEndpoint("messages/conversations")
        APIService.shared.clearPendingRequestsForEndpoint("users/me/friends")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Select Recipients"
        view.backgroundColor = Constants.Colors.background
        
        // Add subviews
        view.addSubview(stepIndicatorView)
        stepIndicatorView.addSubview(stepLabel)
        stepIndicatorView.addSubview(progressView)
        
        view.addSubview(instructionLabel)
        view.addSubview(recipientTabBar)
        view.addSubview(recipientTableView)
        view.addSubview(selectedCountLabel)
        view.addSubview(checkInButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Step indicator
            stepIndicatorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stepIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stepIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stepIndicatorView.heightAnchor.constraint(equalToConstant: 80),
            
            stepLabel.topAnchor.constraint(equalTo: stepIndicatorView.topAnchor, constant: 16),
            stepLabel.leadingAnchor.constraint(equalTo: stepIndicatorView.leadingAnchor, constant: 16),
            
            progressView.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: stepIndicatorView.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: stepIndicatorView.trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            // Content
            instructionLabel.topAnchor.constraint(equalTo: stepIndicatorView.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            
            recipientTabBar.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            recipientTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recipientTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            recipientTableView.topAnchor.constraint(equalTo: recipientTabBar.bottomAnchor, constant: 16),
            recipientTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recipientTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            recipientTableView.bottomAnchor.constraint(equalTo: selectedCountLabel.topAnchor, constant: -8),
            
            selectedCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            selectedCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            selectedCountLabel.bottomAnchor.constraint(equalTo: checkInButton.topAnchor, constant: -16),
            
            checkInButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            checkInButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            checkInButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            checkInButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Setup table view
        recipientTableView.delegate = self
        recipientTableView.dataSource = self
        recipientTableView.register(RecipientCell.self, forCellReuseIdentifier: "RecipientCell")
        
        // Setup actions
        recipientTabBar.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        checkInButton.addTarget(self, action: #selector(checkInButtonTapped), for: .touchUpInside)
        
        // Initially disable check-in button
        updateCheckInButton()
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        // Load both groups and connections
        let group = DispatchGroup()
        
        // Load groups
        group.enter()
        MessagingService.shared.fetchConversations { [weak self] (result: Result<[Conversation], Error>) in
            switch result {
            case .success(let conversations):
                self?.groups = conversations.filter { $0.type == .group }
            case .failure(let error):
                print("Failed to load groups: \(error)")
            }
            group.leave()
        }
        
        // Load connections (friends)
        group.enter()
        NetworkManager.shared.fetchConnections { [weak self] connections, error in
            if let connections = connections {
                let acceptedConnections = connections.filter { $0.status == .accepted }
                self?.connections = acceptedConnections
            } else if let error = error {
                print("Failed to load connections: \(error)")
            }
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.recipientTableView.reloadData()
            completion?()
        }
    }
    
    // MARK: - Actions
    @objc private func tabChanged() {
        currentTab = recipientTabBar.selectedSegmentIndex
        recipientTableView.reloadData()
    }
    
    @objc private func checkInButtonTapped() {
        // Check if user selected individuals not in a group
        if currentTab == 1 && selectedUsers.count > 1 {
            checkForExistingGroup()
        } else {
            createCheckIn()
        }
    }
    
    private func checkForExistingGroup() {
        // Check if selected users are already in a group together
        let sortedUsers = Array(selectedUsers).sorted()
        
        for group in groups {
            let groupParticipants = group.participants.filter { $0 != AuthService.shared.getUserId() }.sorted()
            if groupParticipants == sortedUsers {
                // Found existing group
                showExistingGroupPrompt(group: group)
                return
            }
        }
        
        // No existing group found
        showCreateGroupPrompt()
    }
    
    private func showExistingGroupPrompt(group: Conversation) {
        let alert = UIAlertController(
            title: "Existing Group Found",
            message: "These people are already in the group '\(group.name ?? "Unnamed Group")'. Would you like to notify the group instead?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Notify Group", style: .default) { [weak self] _ in
            self?.selectedGroups = [group.id]
            self?.selectedUsers = []
            self?.createCheckIn()
        })
        
        alert.addAction(UIAlertAction(title: "Notify Individually", style: .default) { [weak self] _ in
            self?.createCheckIn()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showCreateGroupPrompt() {
        let alert = UIAlertController(
            title: "Create Group Chat?",
            message: "Would you like to create a group chat with these \(selectedUsers.count) people?",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Group name (optional)"
        }
        
        alert.addAction(UIAlertAction(title: "Create & Notify", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let groupName = alert.textFields?.first?.text
            self.createGroupAndCheckIn(name: groupName)
        })
        
        alert.addAction(UIAlertAction(title: "Notify Individually", style: .default) { [weak self] _ in
            self?.createCheckIn()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func createGroupAndCheckIn(name: String?) {
        let loadingAlert = showLoading(message: "Creating group...")
        
        let participants = Array(selectedUsers) + [AuthService.shared.getUserId() ?? ""]
        
        MessagingService.shared.createConversation(
            type: .group,
            participants: participants,
            name: name
        ) { [weak self] result in
            loadingAlert.dismiss(animated: true) {
                switch result {
                case .success(let conversation):
                    self?.selectedGroups = [conversation.id]
                    self?.selectedUsers = []
                    self?.createCheckIn()
                    
                case .failure(let error):
                    self?.showError("Failed to create group: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createCheckIn() {
        let loadingAlert = showLoading(message: "Creating check-in...")
        
        // Add notification settings to check-in data
        checkInData["notifiedGroups"] = Array(selectedGroups)
        checkInData["notifiedUsers"] = Array(selectedUsers)
        
        APIService.shared.createCheckIn(checkInData) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        self?.showSuccess("Check-in created successfully!") {
                            self?.delegate?.didCompleteCheckIn()
                        }
                        
                    case .failure(let error):
                        self?.showError("Failed to create check-in: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func updateCheckInButton() {
        let hasSelection = !selectedGroups.isEmpty || !selectedUsers.isEmpty
        checkInButton.isEnabled = hasSelection
        checkInButton.alpha = hasSelection ? 1.0 : 0.6
        
        // Update count label
        let totalCount = selectedGroups.count + selectedUsers.count
        if totalCount == 0 {
            selectedCountLabel.text = "No recipients selected"
            selectedCountLabel.textColor = Constants.Colors.danger
        } else if currentTab == 0 {
            selectedCountLabel.text = "\(selectedGroups.count) group\(selectedGroups.count == 1 ? "" : "s") selected"
            selectedCountLabel.textColor = Constants.Colors.primary
        } else {
            selectedCountLabel.text = "\(selectedUsers.count) \(selectedUsers.count == 1 ? "person" : "people") selected"
            selectedCountLabel.textColor = Constants.Colors.primary
        }
    }
}

// MARK: - UITableViewDataSource
extension CheckInRecipientSelectionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentTab == 0 ? groups.count : connections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RecipientCell", for: indexPath) as! RecipientCell
        
        if currentTab == 0 {
            // Groups
            let group = groups[indexPath.row]
            cell.configure(with: group)
            cell.isChecked = selectedGroups.contains(group.id)
        } else {
            // People
            let connection = connections[indexPath.row]
            if let connectedUser = connection.connectedUser {
                cell.configure(with: connectedUser)
                cell.isChecked = selectedUsers.contains(connectedUser.id)
            }
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension CheckInRecipientSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if currentTab == 0 {
            // Toggle group selection
            let group = groups[indexPath.row]
            if selectedGroups.contains(group.id) {
                selectedGroups.remove(group.id)
            } else {
                selectedGroups.insert(group.id)
            }
        } else {
            // Toggle user selection
            let connection = connections[indexPath.row]
            if let connectedUser = connection.connectedUser {
                if selectedUsers.contains(connectedUser.id) {
                    selectedUsers.remove(connectedUser.id)
                } else {
                    selectedUsers.insert(connectedUser.id)
                }
            }
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
        updateCheckInButton()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - RecipientCell
class RecipientCell: UITableViewCell {
    
    var isChecked: Bool = false {
        didSet {
            checkmarkImageView.isHidden = !isChecked
            backgroundColor = isChecked ? Constants.Colors.primary.withAlphaComponent(0.1) : Constants.Colors.background
        }
    }
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
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
        selectionStyle = .none
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 50),
            profileImageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -12),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with group: Conversation) {
        nameLabel.text = group.name ?? "Unnamed Group"
        subtitleLabel.text = "\(group.participants.count) members"
        
        // Set group icon
        profileImageView.image = UIImage(systemName: "person.2.fill")
        profileImageView.tintColor = Constants.Colors.primary
    }
    
    func configure(with user: User) {
        nameLabel.text = user.displayName
        subtitleLabel.text = user.bio ?? user.email
        
        // Load profile image
        if let profilePicture = user.profilePicture {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        self?.profileImageView.tintColor = Constants.Colors.secondaryLabel
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.secondaryLabel
        }
    }
}