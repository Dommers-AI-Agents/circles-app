import UIKit

class ConversationsListViewController: UIViewController {
    
    // MARK: - UI Elements
    private let headerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let suggestionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Suggestions", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        button.tintColor = .systemBlue
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let suggestionsBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = .systemRed
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "message.circle")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Messages Yet"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emptyDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Start a conversation with your connections"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let newMessageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 28
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 4
        return button
    }()
    
    // MARK: - Properties
    private let messagingManager = MessagingManager.shared
    private var conversationUpdateTimer: Timer?
    private let cellIdentifier = "ConversationCell"
    private var isInitialLoadComplete = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        print("🔍 ConversationsListViewController: viewDidLoad called")
        setupView()
        setupTableView()
        setupEmptyState()
        setupNewMessageButton()
        setupSubscribers()
        checkForNewSuggestions()
        
        // Don't load conversations here - let viewWillAppear handle it
        // This prevents duplicate loading when the tab is first opened
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("🔍 ConversationsListViewController: viewWillAppear called")
        print("🔍 ConversationsListViewController: Auth token available: \(AuthService.shared.getToken() != nil)")
        print("🔍 ConversationsListViewController: Initial load complete: \(isInitialLoadComplete)")
        
        // Notify MessagingManager that Messages tab is active
        messagingManager.setMessagesTabActive(true)
        
        // Always load conversations if we have a token
        if AuthService.shared.getToken() != nil {
            print("🔍 ConversationsListViewController: Token exists, ensuring initialized and loading conversations")
            messagingManager.ensureInitialized()
            
            // Show loading indicator on first load
            if !isInitialLoadComplete {
                showLoadingIndicator()
            }
            
            messagingManager.loadConversations()
            messagingManager.updateUnreadCount()
            
            // Mark initial load as complete after a short delay
            if !isInitialLoadComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.isInitialLoadComplete = true
                    self?.hideLoadingIndicator()
                }
            } else {
                // If returning from chat, immediately reload table to show updated read status
                // The local state should already be correct from markConversationAsReadLocally
                DispatchQueue.main.async { [weak self] in
                    self?.tableView.reloadData()
                }
            }
        }
        
        checkForNewSuggestions()
    }
    
    private func showLoadingIndicator() {
        // Show a loading state in the table view
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
        tableView.tableHeaderView = activityIndicator
    }
    
    private func hideLoadingIndicator() {
        tableView.tableHeaderView = nil
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        conversationUpdateTimer?.invalidate()
        conversationUpdateTimer = nil
        
        // Notify MessagingManager that Messages tab is no longer active
        messagingManager.setMessagesTabActive(false)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        conversationUpdateTimer?.invalidate()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Messages"
        
        view.addSubview(headerContainer)
        headerContainer.addSubview(suggestionsButton)
        headerContainer.addSubview(suggestionsBadge)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(newMessageButton)
        
        // Add button target
        suggestionsButton.addTarget(self, action: #selector(suggestionsButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Suggestions button
            suggestionsButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            suggestionsButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            suggestionsButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Suggestions badge
            suggestionsBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            suggestionsBadge.heightAnchor.constraint(equalToConstant: 20),
            suggestionsBadge.leadingAnchor.constraint(equalTo: suggestionsButton.trailingAnchor, constant: -12),
            suggestionsBadge.bottomAnchor.constraint(equalTo: suggestionsButton.topAnchor, constant: 8),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            
            newMessageButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            newMessageButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            newMessageButton.widthAnchor.constraint(equalToConstant: 56),
            newMessageButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ConversationCell.self, forCellReuseIdentifier: cellIdentifier)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshConversations), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyTitleLabel)
        emptyStateView.addSubview(emptyDescriptionLabel)
        
        NSLayoutConstraint.activate([
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 80),
            emptyImageView.heightAnchor.constraint(equalToConstant: 80),
            
            emptyTitleLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 24),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            emptyDescriptionLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptyDescriptionLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyDescriptionLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyDescriptionLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    private func setupNewMessageButton() {
        newMessageButton.addTarget(self, action: #selector(newMessageTapped), for: .touchUpInside)
    }
    
    private func setupSubscribers() {
        // Listen for new messages notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages),
            name: Notification.Name("NewMessagesReceived"),
            object: nil
        )
        
        // Listen for conversations update notification (when messages are marked as read)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationsUpdate),
            name: Notification.Name("ConversationsUpdated"),
            object: nil
        )
        
        // Start polling timer only after initial data load
        // Using 5 second interval for better performance
        startPollingTimer()
    }
    
    private func startPollingTimer() {
        // Cancel any existing timer
        conversationUpdateTimer?.invalidate()
        
        // Poll for conversation updates every 5 seconds (reduced from 2 seconds)
        conversationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Only update if we have conversations and not currently loading
            if !self.messagingManager.isLoadingConversations {
                let conversations = self.messagingManager.conversations
                print("🔍 ConversationsListViewController: Polling update - \(conversations.count) conversations")
                
                // Disable interaction during reload to prevent selection issues
                self.tableView.isUserInteractionEnabled = false
                self.tableView.reloadData()
                self.updateEmptyState()
                self.tableView.refreshControl?.endRefreshing()
                
                // Re-enable interaction after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tableView.isUserInteractionEnabled = true
                }
            }
        }
    }
    
    @objc private func handleNewMessages() {
        // Reload conversations when new messages arrive
        messagingManager.loadConversations()
    }
    
    @objc private func handleConversationsUpdate() {
        // Update the table view immediately when conversations are updated (e.g., messages marked as read)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("🔍 ConversationsListViewController: Conversations updated, reloading table")
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }
    
    // MARK: - Data Loading
    private func loadConversations() {
        print("🔍 ConversationsListViewController: Loading conversations...")
        messagingManager.ensureInitialized()  // Ensure messaging is initialized
        messagingManager.loadConversations()
    }
    
    @objc private func refreshConversations() {
        print("🔍 ConversationsListViewController: Pull to refresh triggered")
        messagingManager.loadConversations(forceRefresh: true)
    }
    
    // MARK: - Actions
    @objc private func newMessageTapped() {
        let selectConnectionVC = SelectConnectionViewController()
        selectConnectionVC.delegate = self
        let navController = UINavigationController(rootViewController: selectConnectionVC)
        present(navController, animated: true)
    }
    
    // MARK: - Empty State
    private func updateEmptyState() {
        let hasConversations = !messagingManager.conversations.isEmpty
        print("🔍 ConversationsListViewController: updateEmptyState - hasConversations: \(hasConversations)")
        emptyStateView.isHidden = hasConversations
        tableView.isHidden = !hasConversations
    }
    
    // MARK: - Actions
    @objc private func suggestionsButtonTapped() {
        let suggestionsVC = SuggestionsViewController()
        navigationController?.pushViewController(suggestionsVC, animated: true)
    }
    
    private func checkForNewSuggestions() {
        SuggestionService.shared.getUnreadSuggestionsCount { [weak self] count in
            DispatchQueue.main.async {
                if count > 0 {
                    self?.suggestionsBadge.text = "\(count)"
                    self?.suggestionsBadge.isHidden = false
                } else {
                    self?.suggestionsBadge.isHidden = true
                }
            }
        }
    }
    
    
    // MARK: - Navigation
    private func showConversation(_ conversation: Conversation) {
        // Immediately mark conversation as read locally for instant UI feedback
        messagingManager.markConversationAsReadLocally(conversation.id)
        
        // Show a brief loading indicator before navigation
        let loadingAlert = UIAlertController(title: nil, message: "Loading...", preferredStyle: .alert)
        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
        ])
        
        present(loadingAlert, animated: true) { [weak self] in
            // Create and configure the chat view controller
            let chatVC = ChatViewController()
            chatVC.conversation = conversation
            
            // Navigate after a brief delay to show loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadingAlert.dismiss(animated: false) {
                    self?.navigationController?.pushViewController(chatVC, animated: true)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension ConversationsListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messagingManager.conversations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! ConversationCell
        let conversation = messagingManager.conversations[indexPath.row]
        cell.configure(with: conversation)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ConversationsListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Get the cell to retrieve the conversation ID for stable selection
        guard let cell = tableView.cellForRow(at: indexPath) as? ConversationCell,
              let conversationId = cell.conversationId else {
            print("⚠️ ConversationsListViewController: Could not get conversation ID from cell")
            return
        }
        
        // Find the conversation by ID instead of index to avoid race conditions
        guard let conversation = messagingManager.conversations.first(where: { $0.id == conversationId }) else {
            print("⚠️ ConversationsListViewController: Could not find conversation with ID: \(conversationId)")
            return
        }
        
        print("✅ ConversationsListViewController: Selected conversation: \(conversation.displayName)")
        showConversation(conversation)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else {
                completion(false)
                return
            }
            
            let conversation = self.messagingManager.conversations[indexPath.row]
            
            // Show confirmation alert
            let alert = UIAlertController(
                title: "Delete Conversation",
                message: "Are you sure you want to delete this conversation? This action cannot be undone.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completion(false)
            })
            
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                // Delete the conversation
                self.messagingManager.deleteConversation(conversation.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            // The table will reload automatically due to the subscription
                            completion(true)
                        case .failure(let error):
                            // Show error alert
                            let errorAlert = UIAlertController(
                                title: "Error",
                                message: "Failed to delete conversation: \(error.localizedDescription)",
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(errorAlert, animated: true)
                            completion(false)
                        }
                    }
                }
            })
            
            self.present(alert, animated: true)
        }
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - SelectConnectionViewControllerDelegate
extension ConversationsListViewController: SelectConnectionViewControllerDelegate {
    func didSelectConnection(_ connection: Connection) {
        // Get the current user ID to determine the other user
        guard let currentUserId = AuthService.shared.getUserId() else {
            print("Error: No current user ID")
            return
        }
        
        // Use the otherUserId helper to get the correct user ID
        let otherUserId = connection.otherUserId(currentUserId: currentUserId)
        
        // Create or get conversation with selected connection
        messagingManager.createOrGetDirectConversation(with: otherUserId) { [weak self] result in
            switch result {
            case .success(let conversation):
                self?.showConversation(conversation)
            case .failure(let error):
                print("Error creating conversation: \(error)")
                
                // Extract error details and show alert
                var errorMessage = "Failed to create conversation"
                
                if case APIError.httpError(let statusCode, let data) = error {
                    if statusCode == 400 {
                        errorMessage = "Cannot create conversation with this user"
                    }
                    
                    if let data = data,
                       let serverMessage = String(data: data, encoding: .utf8) {
                        print("Server error details: \(serverMessage)")
                        if serverMessage.contains("yourself") {
                            errorMessage = "Cannot create conversation with yourself"
                        } else if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let message = jsonData["message"] as? String {
                            errorMessage = message
                        }
                    }
                }
                
                // Show alert
                let alert = UIAlertController(
                    title: "Error",
                    message: errorMessage,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
        }
    }
}

// MARK: - ConversationCell
class ConversationCell: UITableViewCell {
    
    // Store the conversation ID for stable selection
    private(set) var conversationId: String?
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let unreadBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        avatarImageView.backgroundColor = .systemGray5
        nameLabel.text = nil
        messageLabel.text = nil
        timeLabel.text = nil
        unreadBadge.isHidden = true
        messageLabel.font = .systemFont(ofSize: 14)
    }
    
    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(unreadBadge)
        
        avatarImageView.layer.cornerRadius = 28
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 56),
            avatarImageView.heightAnchor.constraint(equalToConstant: 56),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -8),
            
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            
            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            unreadBadge.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with conversation: Conversation) {
        // Store the conversation ID for stable selection
        self.conversationId = conversation.id
        
        nameLabel.text = conversation.displayName
        messageLabel.text = conversation.lastMessage ?? "No messages yet"
        timeLabel.text = conversation.formattedLastMessageTime ?? ""
        
        // Log unread count for debugging
        print("📱 ConversationCell: \(conversation.displayName) - unreadCount: \(conversation.unreadCount), hasUnread: \(conversation.hasUnreadMessages)")
        
        // Configure avatar
        if let avatarURL = conversation.displayAvatar {
            // Set placeholder while loading
            avatarImageView.image = UIImage(systemName: conversation.type == .direct ? "person.circle.fill" : "person.2.circle.fill")
            avatarImageView.tintColor = .systemGray3
            
            // Load image from URL
            ImageService.shared.loadImage(from: avatarURL) { [weak self] image in
                DispatchQueue.main.async {
                    if let image = image {
                        self?.avatarImageView.image = image
                        self?.avatarImageView.tintColor = nil
                    }
                }
            }
        } else {
            avatarImageView.image = UIImage(systemName: conversation.type == .direct ? "person.circle.fill" : "person.2.circle.fill")
            avatarImageView.tintColor = .systemGray3
        }
        
        // Configure unread badge
        if conversation.hasUnreadMessages {
            unreadBadge.isHidden = false
            unreadBadge.text = "\(conversation.unreadCount)"
            messageLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        } else {
            unreadBadge.isHidden = true
            messageLabel.font = .systemFont(ofSize: 14)
        }
    }
}