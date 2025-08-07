import UIKit
import MessageUI
import Contacts

class FindContactsViewController: BaseViewController {
    
    // MARK: - Properties
    private var allContacts: [Contact] = []
    private var matchedUsers: [User] = []
    private var nonMatchedContacts: [Contact] = []
    private var selectedContacts = Set<String>() // Contact IDs to invite
    private var selectedUsers = Set<String>() // User IDs to connect with
    private var isLoadingOnCircles = true
    private var isLoadingContacts = true
    private var contactsPermissionStatus: CNAuthorizationStatus = .notDetermined
    private var hasLoadedContactData = false
    
    // MARK: - UI Elements
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let items = ["On Circles", "Invite to Circles"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private lazy var actionButton = UIButton.primaryButton(title: "Connect")
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private lazy var grantAccessButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Grant Contact Access")
        button.isHidden = true
        button.addTarget(self, action: #selector(grantAccessTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var sendSingleInviteButton: UIButton = {
        let button = UIButton.primaryButton(title: "Send Invite via SMS")
        button.isHidden = true
        button.addTarget(self, action: #selector(sendSingleInviteTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        setupUI()
        setupTableView()
        loadContacts()
    }
    
    // MARK: - Setup
    private func configureNavigationBar() {
        title = "Add People you know"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        // Add SMS invite button to right side
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "message"),
            style: .plain,
            target: self,
            action: #selector(sendSingleInviteTapped)
        )
    }
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(grantAccessButton)
        view.addSubview(sendSingleInviteButton)
        view.addSubview(actionButton)
        view.addSubview(loadingIndicator)
        
        // Show UI chrome immediately, only hide table content
        tableView.alpha = 0
        loadingIndicator.startAnimating()
        
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            grantAccessButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grantAccessButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 20),
            grantAccessButton.widthAnchor.constraint(equalToConstant: 200),
            grantAccessButton.heightAnchor.constraint(equalToConstant: 44),
            
            sendSingleInviteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sendSingleInviteButton.topAnchor.constraint(equalTo: grantAccessButton.bottomAnchor, constant: 12),
            sendSingleInviteButton.widthAnchor.constraint(equalToConstant: 200),
            sendSingleInviteButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Setup bottom button constraints separately to handle dual button layout
        var actionButtonConstraints = [
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            actionButton.heightAnchor.constraint(equalToConstant: 50),
            tableView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16)
        ]
        NSLayoutConstraint.activate(actionButtonConstraints)
        
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        
        updateActionButton()
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FindContactsUserCell.self, forCellReuseIdentifier: "FindContactsUserCell")
        tableView.register(ContactCell.self, forCellReuseIdentifier: "ContactCell")
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        loadContacts()
        completion?()
    }
    
    private func loadContacts() {
        // Check contacts permission first
        contactsPermissionStatus = ContactsService.shared.checkContactsPermission()
        
        if contactsPermissionStatus != .authorized {
            // Show permission UI
            loadingIndicator.stopAnimating()
            showContactPermissionUI()
            return
        }
        
        ContactsService.shared.syncContactsWithBackend { [weak self] result in
            guard let self = self else { return }
            
            self.hasLoadedContactData = true
            self.loadingIndicator.stopAnimating()
            
            switch result {
            case .success(let response):
                // Filter out already connected users from the "On Circles" tab
                self.matchedUsers = response.matchedUsers.filter { user in
                    // Keep users who are not connected or have a pending request
                    return user.connectionStatus != "accepted"
                }
                self.processContacts(response)
                self.tableView.reloadData()
                
                // Show content with animation
                UIView.animate(withDuration: 0.3) {
                    self.tableView.alpha = 1
                }
                
                // Update empty states
                self.updateEmptyState()
                
            case .failure(let error):
                self.showError(error)
                // Still show the table even on error
                UIView.animate(withDuration: 0.3) {
                    self.tableView.alpha = 1
                }
                self.updateEmptyState()
            }
        }
    }
    
    private func processContacts(_ response: SyncContactsResponse) {
        // Get all contacts first
        ContactsService.shared.fetchContacts { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let contacts):
                self.allContacts = contacts
                
                // Create a set of matched emails and phone numbers
                var matchedIdentifiers = Set<String>()
                for user in response.matchedUsers {
                    if let email = user.email {
                        matchedIdentifiers.insert(email.lowercased())
                    }
                    if let phone = user.phoneNumber {
                        matchedIdentifiers.insert(ContactsService.normalizePhoneNumber(phone) ?? phone)
                    }
                }
                
                // Filter out non-matched contacts
                self.nonMatchedContacts = contacts.filter { contact in
                    let hasMatchedEmail = contact.emails.contains { email in
                        matchedIdentifiers.contains(email.lowercased())
                    }
                    let hasMatchedPhone = contact.phoneNumbers.contains { phone in
                        if let normalized = ContactsService.normalizePhoneNumber(phone) {
                            return matchedIdentifiers.contains(normalized)
                        }
                        return false
                    }
                    return !hasMatchedEmail && !hasMatchedPhone
                }
                
                self.tableView.reloadData()
                self.updateEmptyState()
                
            case .failure(let error):
                Logger.error("Failed to fetch contacts: \(error)")
            }
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func segmentChanged() {
        selectedContacts.removeAll()
        selectedUsers.removeAll()
        tableView.reloadData()
        updateActionButton()
        updateEmptyState()
    }
    
    @objc private func actionButtonTapped() {
        if segmentedControl.selectedSegmentIndex == 0 {
            // Connect with selected users
            connectWithUsers()
        } else {
            // Invite selected contacts
            inviteContacts()
        }
    }
    
    private func connectWithUsers() {
        guard !selectedUsers.isEmpty else { return }
        
        let loading = AlertPresenter.showLoading(from: self)
        actionButton.isEnabled = false
        
        let userIds = Array(selectedUsers)
        var successCount = 0
        var failureCount = 0
        
        // Send connection requests
        ContactsService.shared.sendMultipleConnectionRequests(userIds) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let results):
                for (_, success) in results {
                    if success {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                }
                
                // Also follow the users
                ContactsService.shared.followMultipleUsers(userIds) { _ in
                    loading.dismiss(animated: true)
                    self.actionButton.isEnabled = true
                    
                    if successCount > 0 {
                        self.showSuccess("Sent \(successCount) connection request\(successCount == 1 ? "" : "s")")
                        
                        // Refresh connections
                        NetworkManager.shared.loadConnections()
                        
                        // Dismiss after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.dismiss(animated: true)
                        }
                    } else if failureCount > 0 {
                        self.showError("Some users are already connected or have pending requests")
                    } else {
                        self.showError("Failed to send connection requests")
                    }
                }
                
            case .failure(let error):
                loading.dismiss(animated: true)
                self.actionButton.isEnabled = true
                
                // Check if it's an API error with specific message
                if let apiError = error as? APIError,
                   case .httpError(let statusCode, let data) = apiError,
                   statusCode == 400,
                   let data = data,
                   let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    
                    // Show more user-friendly messages
                    if errorResponse.message.contains("already") {
                        self.showError("You are already following this user")
                    } else if errorResponse.message.contains("pending") {
                        self.showError("You have a pending connection request with this user")
                    } else {
                        self.showError(errorResponse.message)
                    }
                } else {
                    self.showError("Failed to send connection requests")
                }
            }
        }
    }
    
    private func inviteContacts() {
        guard !selectedContacts.isEmpty else { return }
        
        // Prepare invites
        var invites: [InviteContactsRequest.Invite] = []
        
        for contactId in selectedContacts {
            guard let contact = nonMatchedContacts.first(where: { $0.id == contactId }) else { continue }
            
            // Prefer SMS over email for invitations
            if let phone = contact.phoneNumbers.first {
                invites.append(InviteContactsRequest.Invite(
                    type: "sms",
                    email: nil,
                    phoneNumber: phone,
                    contactName: contact.name
                ))
            } else if let email = contact.emails.first {
                invites.append(InviteContactsRequest.Invite(
                    type: "email",
                    email: email,
                    phoneNumber: nil,
                    contactName: contact.name
                ))
            }
        }
        
        // For SMS invites, we'll use the native message composer
        let smsInvites = invites.filter { $0.type == "sms" }
        if !smsInvites.isEmpty {
            sendSMSInvites(smsInvites)
        }
        
        // Send email invites through backend
        let emailInvites = invites.filter { $0.type == "email" }
        if !emailInvites.isEmpty {
            sendEmailInvites(emailInvites)
        }
    }
    
    private func sendSMSInvites(_ invites: [InviteContactsRequest.Invite]) {
        guard MFMessageComposeViewController.canSendText() else {
            showError("SMS is not available on this device")
            return
        }
        
        let messageVC = MFMessageComposeViewController()
        messageVC.messageComposeDelegate = self
        
        // Add recipients
        let recipients = invites.compactMap { $0.phoneNumber }
        messageVC.recipients = recipients
        
        // Set message body
        let userName = AuthService.shared.currentUser?.displayName ?? "A friend"
        messageVC.body = "\(userName) invited you to join Circles - the app for sharing your favorite places! Download: https://circles-app.com/download"
        
        present(messageVC, animated: true)
    }
    
    private func sendEmailInvites(_ invites: [InviteContactsRequest.Invite]) {
        let loading = AlertPresenter.showLoading(from: self)
        
        ContactsService.shared.inviteContacts(invites) { [weak self] result in
            guard let self = self else { return }
            
            loading.dismiss(animated: true)
            
            switch result {
            case .success(let response):
                if response.sentCount > 0 {
                    self.showSuccess("Sent \(response.sentCount) invitation\(response.sentCount == 1 ? "" : "s")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.dismiss(animated: true)
                    }
                }
                
            case .failure(let error):
                self.showError(error)
            }
        }
    }
    
    private func updateActionButton() {
        if segmentedControl.selectedSegmentIndex == 0 {
            let count = selectedUsers.count
            actionButton.isEnabled = count > 0
            actionButton.setTitle(count > 0 ? "Connect with \(count)" : "Connect", for: .normal)
        } else {
            let count = selectedContacts.count
            actionButton.isEnabled = count > 0
            actionButton.setTitle(count > 0 ? "Invite \(count)" : "Invite", for: .normal)
        }
    }
    
    // MARK: - Empty State Management
    
    private func updateEmptyState() {
        if segmentedControl.selectedSegmentIndex == 0 {
            // On Circles tab
            let isEmpty = matchedUsers.isEmpty
            tableView.isHidden = isEmpty
            
            if isEmpty {
                emptyStateLabel.text = "No contacts found on Circles yet.\nTry the Invite tab to bring your friends!"
                emptyStateLabel.isHidden = false
                grantAccessButton.isHidden = true
                sendSingleInviteButton.isHidden = true
            } else {
                emptyStateLabel.isHidden = true
                grantAccessButton.isHidden = true
                sendSingleInviteButton.isHidden = true
            }
        } else {
            // Invite to Circles tab
            let isEmpty = nonMatchedContacts.isEmpty
            tableView.isHidden = isEmpty
            
            if isEmpty && hasLoadedContactData {
                if contactsPermissionStatus != .authorized {
                    showContactPermissionUI()
                } else {
                    emptyStateLabel.text = "All your contacts are already on Circles!"
                    emptyStateLabel.isHidden = false
                    grantAccessButton.isHidden = true
                    sendSingleInviteButton.isHidden = true
                }
            } else {
                emptyStateLabel.isHidden = true
                grantAccessButton.isHidden = true
                sendSingleInviteButton.isHidden = true
            }
        }
    }
    
    private func showContactPermissionUI() {
        tableView.isHidden = true
        emptyStateLabel.text = "Grant access to your contacts to find friends on Circles and send invites."
        emptyStateLabel.isHidden = false
        
        if contactsPermissionStatus == .denied {
            grantAccessButton.setTitle("Open Settings", for: .normal)
        } else {
            grantAccessButton.setTitle("Grant Contact Access", for: .normal)
        }
        
        grantAccessButton.isHidden = false
        sendSingleInviteButton.isHidden = false
    }
    
    @objc private func grantAccessTapped() {
        if contactsPermissionStatus == .denied {
            // Open settings
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        } else {
            // Request permission
            ContactsService.shared.requestContactsPermission { [weak self] granted in
                if granted {
                    self?.loadContacts()
                } else {
                    self?.showError("Contact access is required to find friends on Circles")
                }
            }
        }
    }
    
    @objc private func sendSingleInviteTapped() {
        // Create a simple SMS invite
        guard MFMessageComposeViewController.canSendText() else {
            showError("SMS is not available on this device")
            return
        }
        
        let messageVC = MFMessageComposeViewController()
        messageVC.messageComposeDelegate = self
        
        // Set message body with invite link
        let userName = AuthService.shared.currentUser?.displayName ?? "A friend"
        let userId = AuthService.shared.currentUser?.id ?? ""
        let inviteLink = "https://circles-app.com/join?inviter=\(userId)"
        messageVC.body = "\(userName) invited you to join Circles - the app for sharing your favorite places!\n\nJoin using this link and we'll automatically connect: \(inviteLink)"
        
        present(messageVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension FindContactsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if segmentedControl.selectedSegmentIndex == 0 {
            return matchedUsers.count
        } else {
            return nonMatchedContacts.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentedControl.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "FindContactsUserCell", for: indexPath) as! FindContactsUserCell
            let user = matchedUsers[indexPath.row]
            cell.configure(with: user)
            cell.showSelectionCheckmark = selectedUsers.contains(user.id)
            
            // Since we're filtering out connected users, all should be selectable
            cell.isUserInteractionEnabled = true
            cell.alpha = 1.0
            
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactCell", for: indexPath) as! ContactCell
            let contact = nonMatchedContacts[indexPath.row]
            cell.configure(with: contact)
            cell.showSelectionCheckmark = selectedContacts.contains(contact.id)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension FindContactsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if segmentedControl.selectedSegmentIndex == 0 {
            let user = matchedUsers[indexPath.row]
            
            // Skip if already connected
            if user.connectionStatus == "accepted" || user.connectionStatus == "pending" {
                return
            }
            
            if selectedUsers.contains(user.id) {
                selectedUsers.remove(user.id)
            } else {
                selectedUsers.insert(user.id)
            }
        } else {
            let contact = nonMatchedContacts[indexPath.row]
            if selectedContacts.contains(contact.id) {
                selectedContacts.remove(contact.id)
            } else {
                selectedContacts.insert(contact.id)
            }
        }
        
        tableView.reloadRows(at: [indexPath], with: .none)
        updateActionButton()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - MFMessageComposeViewControllerDelegate
extension FindContactsViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true) {
            switch result {
            case .sent:
                self.showSuccess("Invitations sent!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.dismiss(animated: true)
                }
            case .cancelled:
                break
            case .failed:
                self.showError("Failed to send invitations")
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Cell Classes
class FindContactsUserCell: UITableViewCell {
    static let reuseIdentifier = "FindContactsUserCell"
    
    var showSelectionCheckmark = false {
        didSet {
            checkmarkImageView.isHidden = !showSelectionCheckmark
        }
    }
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
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
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(profileImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(detailLabel)
        containerView.addSubview(statusLabel)
        containerView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -8),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),
            
            statusLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: detailLabel.centerYAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            checkmarkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with user: User) {
        nameLabel.text = user.displayName
        
        // Show places and circles count
        let placesText = "\(user.placesCount ?? 0) place\(user.placesCount == 1 ? "" : "s")"
        let circlesText = "\(user.circlesCount ?? 0) circle\(user.circlesCount == 1 ? "" : "s")"
        detailLabel.text = "\(placesText) • \(circlesText)"
        
        // Show connection status
        if user.connectionStatus == "accepted" {
            statusLabel.text = "Connected"
            statusLabel.textColor = .systemGreen
        } else if user.connectionStatus == "pending" {
            statusLabel.text = "Pending"
            statusLabel.textColor = .systemOrange
        } else {
            statusLabel.text = ""
        }
        
        // Load profile image
        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                self?.profileImageView.image = image
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.secondaryLabel
        }
    }
}

class ContactCell: UITableViewCell {
    static let reuseIdentifier = "ContactCell"
    
    var showSelectionCheckmark = false {
        didSet {
            checkmarkImageView.isHidden = !showSelectionCheckmark
        }
    }
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let initialsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = Constants.Colors.primary
        label.layer.cornerRadius = 20
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
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
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(initialsLabel)
        containerView.addSubview(nameLabel)
        containerView.addSubview(detailLabel)
        containerView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            initialsLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            initialsLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            initialsLabel.widthAnchor.constraint(equalToConstant: 40),
            initialsLabel.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: initialsLabel.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -8),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            checkmarkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with contact: Contact) {
        nameLabel.text = contact.name
        
        // Show email or phone as detail
        if let email = contact.emails.first {
            detailLabel.text = email
        } else if let phone = contact.phoneNumbers.first {
            detailLabel.text = phone
        } else {
            detailLabel.text = ""
        }
        
        // Set initials
        let names = contact.name.components(separatedBy: " ")
        let initials = names.compactMap { $0.first }.prefix(2).map { String($0) }.joined()
        initialsLabel.text = initials.uppercased()
    }
}

// Add extension for phone number normalization
extension ContactsService {
    static func normalizePhoneNumber(_ phone: String) -> String? {
        guard !phone.isEmpty else { return nil }
        
        // Remove all non-numeric characters
        let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Handle US numbers (assume US if 10 digits without country code)
        if cleaned.count == 10 {
            return "+1\(cleaned)"
        }
        
        // Add + if missing for international numbers
        if cleaned.count > 10 && !phone.hasPrefix("+") {
            return "+\(cleaned)"
        }
        
        return cleaned.isEmpty ? nil : cleaned
    }
}