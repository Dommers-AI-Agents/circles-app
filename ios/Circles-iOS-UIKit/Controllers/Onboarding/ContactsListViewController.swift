import UIKit

class ContactsListViewController: BaseViewController {
    
    // MARK: - Properties
    var onComplete: (() -> Void)?
    
    private var matchedUsers: [User] = []
    private var invitableContacts: [Contact] = []
    private var selectedUserIds: Set<String> = []
    private var inviteSelections: Set<String> = []
    
    private enum Section: Int, CaseIterable {
        case onCircles
        case inviteContacts
        
        var title: String {
            switch self {
            case .onCircles: return "Friends on Circles"
            case .inviteContacts: return "Invite to Circles"
            }
        }
    }
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let bottomContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let selectionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var connectButton = UIButton.primaryButton(title: "Connect")
    private lazy var skipButton = UIButton.secondaryButton(title: "Skip")
    
    // MARK: - BaseViewController Overrides
    override var enablesPullToRefresh: Bool { false }
    override var emptyStateMessage: String? { "No contacts found" }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupActions()
        updateSelectionUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func loadData(completion: (() -> Void)? = nil) {
        syncContacts(completion: completion)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Find Friends"
        view.backgroundColor = Constants.Colors.background
        
        // Add table view
        view.addSubview(tableView)
        view.addSubview(bottomContainerView)
        
        // Add bottom container elements
        bottomContainerView.addSubview(selectionLabel)
        bottomContainerView.addSubview(connectButton)
        bottomContainerView.addSubview(skipButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Table view
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomContainerView.topAnchor),
            
            // Bottom container
            bottomContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Selection label
            selectionLabel.topAnchor.constraint(equalTo: bottomContainerView.topAnchor, constant: 12),
            selectionLabel.leadingAnchor.constraint(equalTo: bottomContainerView.leadingAnchor, constant: 20),
            selectionLabel.trailingAnchor.constraint(equalTo: bottomContainerView.trailingAnchor, constant: -20),
            
            // Buttons
            connectButton.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 12),
            connectButton.leadingAnchor.constraint(equalTo: bottomContainerView.leadingAnchor, constant: 20),
            connectButton.trailingAnchor.constraint(equalTo: bottomContainerView.trailingAnchor, constant: -20),
            connectButton.heightAnchor.constraint(equalToConstant: 50),
            
            skipButton.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 8),
            skipButton.leadingAnchor.constraint(equalTo: bottomContainerView.leadingAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: bottomContainerView.trailingAnchor, constant: -20),
            skipButton.heightAnchor.constraint(equalToConstant: 44),
            skipButton.bottomAnchor.constraint(equalTo: bottomContainerView.bottomAnchor, constant: -12)
        ])
        
        // Style skip button
        skipButton.backgroundColor = .clear
        skipButton.setTitleColor(Constants.Colors.secondaryLabel, for: .normal)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ContactUserCell.self, forCellReuseIdentifier: "ContactUserCell")
        tableView.register(InviteContactCell.self, forCellReuseIdentifier: "InviteContactCell")
    }
    
    private func setupActions() {
        connectButton.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Data Loading
    private func syncContacts(completion: (() -> Void)? = nil) {
        ContactsService.shared.syncContactsWithBackend { [weak self] result in
            switch result {
            case .success(let response):
                self?.matchedUsers = response.matchedUsers
                self?.loadInvitableContacts()
                self?.tableView.reloadData()
                completion?()
                
            case .failure(let error):
                self?.showError(error)
                completion?()
            }
        }
    }
    
    private func loadInvitableContacts() {
        ContactsService.shared.fetchContacts { [weak self] result in
            switch result {
            case .success(let contacts):
                // Filter out contacts that are already matched users
                let matchedEmails = Set(self?.matchedUsers.map { $0.email.lowercased() } ?? [])
                
                self?.invitableContacts = contacts.filter { contact in
                    // Check if any email matches
                    let hasMatchingEmail = contact.emails.contains { email in
                        matchedEmails.contains(email.lowercased())
                    }
                    return !hasMatchingEmail
                }
                
                self?.tableView.reloadData()
                
            case .failure(let error):
                Logger.error("Failed to load contacts: \(error)")
            }
        }
    }
    
    // MARK: - Actions
    @objc private func connectButtonTapped() {
        guard !selectedUserIds.isEmpty || !inviteSelections.isEmpty else { return }
        
        showLoadingState()
        connectButton.isEnabled = false
        
        let group = DispatchGroup()
        var hasErrors = false
        
        // Follow and send connection requests
        if !selectedUserIds.isEmpty {
            group.enter()
            ContactsService.shared.followMultipleUsers(Array(selectedUserIds)) { _ in
                group.leave()
            }
            
            group.enter()
            ContactsService.shared.sendMultipleConnectionRequests(Array(selectedUserIds)) { result in
                if case .failure = result {
                    hasErrors = true
                }
                group.leave()
            }
        }
        
        // Send invitations
        if !inviteSelections.isEmpty {
            group.enter()
            sendInvitations { success in
                if !success {
                    hasErrors = true
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.hideLoadingState()
            self?.connectButton.isEnabled = true
            
            if hasErrors {
                self?.showError("Some actions failed, but we'll continue")
            }
            
            // Show success and complete
            self?.showSuccess("Connected with \(self?.selectedUserIds.count ?? 0) friends!") {
                self?.onComplete?()
            }
        }
    }
    
    @objc private func skipButtonTapped() {
        onComplete?()
    }
    
    private func sendInvitations(completion: @escaping (Bool) -> Void) {
        let invites: [InviteContactsRequest.Invite] = inviteSelections.compactMap { contactId in
            guard let contact = invitableContacts.first(where: { $0.id == contactId }) else { return nil }
            
            // Prefer email over SMS
            if let email = contact.emails.first {
                return InviteContactsRequest.Invite(
                    type: "email",
                    email: email,
                    phoneNumber: nil,
                    contactName: contact.name
                )
            } else if let phone = contact.phoneNumbers.first {
                return InviteContactsRequest.Invite(
                    type: "sms",
                    email: nil,
                    phoneNumber: phone,
                    contactName: contact.name
                )
            }
            
            return nil
        }
        
        guard !invites.isEmpty else {
            completion(true)
            return
        }
        
        ContactsService.shared.inviteContacts(invites) { result in
            switch result {
            case .success:
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }
    
    private func updateSelectionUI() {
        let totalSelected = selectedUserIds.count + inviteSelections.count
        
        if totalSelected == 0 {
            selectionLabel.text = "Select friends to connect with"
            connectButton.isEnabled = false
            connectButton.alpha = 0.5
        } else {
            selectionLabel.text = "\(totalSelected) selected"
            connectButton.isEnabled = true
            connectButton.alpha = 1.0
            
            // Update button title
            if inviteSelections.isEmpty {
                connectButton.setTitle("Connect (\(selectedUserIds.count))", for: .normal)
            } else if selectedUserIds.isEmpty {
                connectButton.setTitle("Send Invites (\(inviteSelections.count))", for: .normal)
            } else {
                connectButton.setTitle("Connect & Invite (\(totalSelected))", for: .normal)
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension ContactsListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        var count = 0
        if !matchedUsers.isEmpty { count += 1 }
        if !invitableContacts.isEmpty { count += 1 }
        return count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 && !matchedUsers.isEmpty {
            return matchedUsers.count
        } else {
            return invitableContacts.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && !matchedUsers.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactUserCell", for: indexPath) as! ContactUserCell
            let user = matchedUsers[indexPath.row]
            let isSelected = selectedUserIds.contains(user.id)
            cell.configure(with: user, isSelected: isSelected)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "InviteContactCell", for: indexPath) as! InviteContactCell
            let contact = invitableContacts[indexPath.row]
            let isSelected = inviteSelections.contains(contact.id)
            cell.configure(with: contact, isSelected: isSelected)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 && !matchedUsers.isEmpty {
            return Section.onCircles.title
        } else if !invitableContacts.isEmpty {
            return Section.inviteContacts.title
        }
        return nil
    }
}

// MARK: - UITableViewDelegate
extension ContactsListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 && !matchedUsers.isEmpty {
            let user = matchedUsers[indexPath.row]
            if selectedUserIds.contains(user.id) {
                selectedUserIds.remove(user.id)
            } else {
                selectedUserIds.insert(user.id)
            }
        } else {
            let contact = invitableContacts[indexPath.row]
            if inviteSelections.contains(contact.id) {
                inviteSelections.remove(contact.id)
            } else {
                inviteSelections.insert(contact.id)
            }
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
        updateSelectionUI()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - Contact User Cell
class ContactUserCell: UITableViewCell {
    private let containerView = UIView()
    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkmarkImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Container
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)
        
        // Profile image
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.layer.cornerRadius = 24
        profileImageView.clipsToBounds = true
        profileImageView.backgroundColor = Constants.Colors.lightGray
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(profileImageView)
        
        // Name label
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(nameLabel)
        
        // Detail label
        detailLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailLabel)
        
        // Checkmark
        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = Constants.Colors.primary
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(checkmarkImageView)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -12),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            checkmarkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with user: User, isSelected: Bool) {
        nameLabel.text = user.displayName
        
        // Show connections count or connection status
        if let connectionsCount = user.connectionsCount, connectionsCount > 0 {
            detailLabel.text = "\(connectionsCount) connections"
        } else if user.connectionStatus == "pending" {
            detailLabel.text = "Connection pending"
        } else if user.connectionStatus == "accepted" {
            detailLabel.text = "Already connected"
        } else {
            detailLabel.text = user.email
        }
        
        // Load profile image
        if let urlString = user.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak profileImageView] image in
                DispatchQueue.main.async {
                    profileImageView?.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        profileImageView?.tintColor = Constants.Colors.lightGray
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.lightGray
        }
        
        // Update selection state
        checkmarkImageView.isHidden = !isSelected
        containerView.layer.borderWidth = isSelected ? 2 : 0
        containerView.layer.borderColor = Constants.Colors.primary.cgColor
    }
}

// MARK: - Invite Contact Cell
class InviteContactCell: UITableViewCell {
    private let containerView = UIView()
    private let initialsLabel = UILabel()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let inviteButton = UIButton()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Container
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)
        
        // Initials circle
        let initialsContainer = UIView()
        initialsContainer.backgroundColor = Constants.Colors.lightGray
        initialsContainer.layer.cornerRadius = 24
        initialsContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(initialsContainer)
        
        // Initials label
        initialsLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        initialsLabel.textColor = Constants.Colors.label
        initialsLabel.textAlignment = .center
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        initialsContainer.addSubview(initialsLabel)
        
        // Name label
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(nameLabel)
        
        // Detail label
        detailLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailLabel)
        
        // Invite button
        inviteButton.setTitle("Invite", for: .normal)
        inviteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        inviteButton.layer.cornerRadius = 6
        inviteButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(inviteButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            initialsContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            initialsContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            initialsContainer.widthAnchor.constraint(equalToConstant: 48),
            initialsContainer.heightAnchor.constraint(equalToConstant: 48),
            
            initialsLabel.centerXAnchor.constraint(equalTo: initialsContainer.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: initialsContainer.centerYAnchor),
            
            nameLabel.leadingAnchor.constraint(equalTo: initialsContainer.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: initialsContainer.topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: inviteButton.leadingAnchor, constant: -12),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            inviteButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            inviteButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            inviteButton.widthAnchor.constraint(equalToConstant: 70),
            inviteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    func configure(with contact: Contact, isSelected: Bool) {
        nameLabel.text = contact.name
        
        // Show email or phone
        if let email = contact.emails.first {
            detailLabel.text = email
        } else if let phone = contact.phoneNumbers.first {
            detailLabel.text = phone
        }
        
        // Set initials
        let initials = contact.name.split(separator: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .prefix(2)
            .joined()
            .uppercased()
        initialsLabel.text = initials.isEmpty ? "?" : initials
        
        // Update selection state
        if isSelected {
            inviteButton.setTitle("Selected", for: .normal)
            inviteButton.backgroundColor = Constants.Colors.primary
            inviteButton.setTitleColor(.white, for: .normal)
            containerView.layer.borderWidth = 2
            containerView.layer.borderColor = Constants.Colors.primary.cgColor
        } else {
            inviteButton.setTitle("Invite", for: .normal)
            inviteButton.backgroundColor = Constants.Colors.lightGray
            inviteButton.setTitleColor(Constants.Colors.primary, for: .normal)
            containerView.layer.borderWidth = 0
        }
    }
}