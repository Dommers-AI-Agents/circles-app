import UIKit

class ConversationsListViewController: UIViewController {
    
    // MARK: - SSE Integration
    private var sseConnected = false
    
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
    
    private let groupMessageButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "person.2.fill", withConfiguration: config), for: .normal)
        button.setTitle("Group", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        button.tintColor = .systemBlue
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 16)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
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
    
    /// What the tab shows before there are any conversations
    private lazy var emptyStateView: MessagesStarterView = {
        let view = MessagesStarterView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.delegate = self
        return view
    }()
    private var starterLoadedAt: Date?
    
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
        Logger.debug("🔍 ConversationsListViewController: viewDidLoad called")
        setupView()
        setupTableView()
        setupNewMessageButton()

        // Push/notification taps land here with a conversation id — open it
        // (retrying once, since the list may still be loading on cold start)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenConversationById(_:)),
            name: .openConversationById,
            object: nil
        )
        setupSubscribers()
        checkForNewSuggestions()
        setupSSE()
        
        // Don't load conversations here - let viewWillAppear handle it
        // This prevents duplicate loading when the tab is first opened
        
        // Check if user needs notification prompt for messages
        NotificationPromptManager.shared.checkAndPromptIfNeeded(in: self, context: .messages)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Logger.debug("🔍 ConversationsListViewController: viewWillAppear called")
        Logger.debug("🔍 ConversationsListViewController: Auth token available: \(AuthService.shared.getToken() != nil)")
        Logger.debug("🔍 ConversationsListViewController: Initial load complete: \(isInitialLoadComplete)")
        
        // Notify MessagingManager that Messages tab is active
        messagingManager.setMessagesTabActive(true)
        
        // Always load conversations if we have a token
        if AuthService.shared.getToken() != nil {
            Logger.debug("🔍 ConversationsListViewController: Token exists, ensuring initialized and loading conversations")
            messagingManager.ensureInitialized()
            
            // Show loading indicator on first load
            if !isInitialLoadComplete {
                Logger.debug("🔍 ConversationsListViewController: First load - showing loading indicator")
                showLoadingIndicator()
            }
            
            // Start timing the conversation load
            let loadStartTime = Date()
            
            messagingManager.loadConversations()
            messagingManager.updateUnreadCount()
            
            // Mark initial load as complete after a short delay
            if !isInitialLoadComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    let loadDuration = Date().timeIntervalSince(loadStartTime)
                    Logger.debug("🔍 ConversationsListViewController: Initial load completed in \(loadDuration) seconds")
                    self.isInitialLoadComplete = true
                    self.hideLoadingIndicator()
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
        // viewWillDisappear stops the poll; start it again, and show what we
        // already know instead of waiting for it
        startPollingTimer()
        updateEmptyState()
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
        headerContainer.addSubview(groupMessageButton)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(newMessageButton)
        
        // Add button targets
        suggestionsButton.addTarget(self, action: #selector(suggestionsButtonTapped), for: .touchUpInside)
        groupMessageButton.addTarget(self, action: #selector(groupMessageButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
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
            
            // Group message button
            groupMessageButton.leadingAnchor.constraint(equalTo: suggestionsButton.trailingAnchor, constant: 8),
            groupMessageButton.centerYAnchor.constraint(equalTo: suggestionsButton.centerYAnchor),
            groupMessageButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
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
    
    private func setupNewMessageButton() {
        newMessageButton.addTarget(self, action: #selector(newMessageTapped), for: .touchUpInside)
    }
    
    private func setupSubscribers() {
        // Listen for new messages notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages),
            name: .newMessagesReceived,
            object: nil
        )
        
        // Listen for conversations update notification (when messages are marked as read)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationsUpdate),
            name: .conversationsUpdated,
            object: nil
        )
        
        // Listen for conversation deleted notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationDeleted),
            name: .conversationDeleted,
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
            
            // Always update empty state and UI, even if loading
            let conversations = self.messagingManager.conversations
            Logger.debug("🔍 ConversationsListViewController: Polling update - \(conversations.count) conversations")
            
            // If we've been loading for more than 10 seconds, force hide loading
            if self.messagingManager.isLoadingConversations && self.isInitialLoadComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    if self.messagingManager.isLoadingConversations {
                        Logger.debug("⚠️ ConversationsListViewController: Force hiding loading after timeout")
                        self.hideLoadingIndicator()
                    }
                }
            }
            
            // Always reload and update empty state
            self.tableView.reloadData()
            self.updateEmptyState()
            self.tableView.refreshControl?.endRefreshing()
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
            
            Logger.debug("🔍 ConversationsListViewController: Conversations updated, reloading table")
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }
    
    @objc private func handleConversationDeleted(notification: Notification) {
        Logger.debug("🔍 ConversationsListViewController: Received ConversationDeleted notification")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Force refresh conversations from messaging manager to ensure deleted conversation is removed
            self.messagingManager.loadConversations(forceRefresh: true)
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }
    
    // MARK: - Data Loading
    private func loadConversations() {
        Logger.debug("🔍 ConversationsListViewController: Loading conversations...")
        messagingManager.ensureInitialized()  // Ensure messaging is initialized
        messagingManager.loadConversations()
    }
    
    @objc func refreshConversations() {
        Logger.debug("🔍 ConversationsListViewController: Pull to refresh triggered")
        messagingManager.loadConversations(forceRefresh: true)
    }
    
    // MARK: - Actions
    @objc private func newMessageTapped() {
        Logger.debug("🔍 ConversationsListViewController: New message button tapped")
        let selectConnectionVC = SelectConnectionViewController()
        selectConnectionVC.delegate = self
        let navController = UINavigationController(rootViewController: selectConnectionVC)
        present(navController, animated: true)
    }
    
    // MARK: - Empty State
    private func updateEmptyState() {
        let conversations = messagingManager.conversations
        
        // Hide loading indicator if we're not actively loading
        if !messagingManager.isLoadingConversations && isInitialLoadComplete {
            hideLoadingIndicator()
        }
        
        // Only once the list is known to be empty — never during the first load
        let shouldShowEmptyState = conversations.isEmpty && messagingManager.hasLoadedConversations
        emptyStateView.isHidden = !shouldShowEmptyState
        tableView.isHidden = shouldShowEmptyState
        
        if shouldShowEmptyState {
            hideLoadingIndicator()
            loadStarterContent()
        } else {
            tableView.reloadData()
        }
    }
    
    /// Fills the starter screen: connections (which wording), the places
    /// people sent them, and people they may know. At most once a minute —
    /// the poll calls updateEmptyState every 5 seconds.
    private func loadStarterContent(force: Bool = false) {
        if !force, let loadedAt = starterLoadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        starterLoadedAt = Date()
        
        NetworkManager.shared.getConnections { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let connections) = result {
                    self?.emptyStateView.setHasConnections(!connections.isEmpty)
                }
            }
        }
        SuggestionService.shared.fetchReceivedSuggestions { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let suggestions) = result {
                    self?.emptyStateView.setSuggestions(suggestions)
                }
            }
        }
        ContactsService.shared.fetchSuggestedUsers(limit: 5) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let people) = result {
                    self?.emptyStateView.setPeople(people)
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func suggestionsButtonTapped() {
        let suggestionsVC = SuggestionsViewController()
        navigationController?.pushViewController(suggestionsVC, animated: true)
    }
    
    @objc private func groupMessageButtonTapped() {
        let groupSelectionVC = GroupConnectionSelectionViewController()
        groupSelectionVC.delegate = self
        let navController = UINavigationController(rootViewController: groupSelectionVC)
        present(navController, animated: true)
    }
    
    private func checkForNewSuggestions() {
        SuggestionService.shared.getUnreadSuggestionsCount { [weak self] count in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if count > 0 {
                    self.suggestionsBadge.text = "\(count)"
                    self.suggestionsBadge.isHidden = false
                } else {
                    self.suggestionsBadge.isHidden = true
                }
            }
        }
    }
    
    
    // MARK: - Navigation
    @objc private func handleOpenConversationById(_ note: Notification) {
        guard let conversationId = note.object as? String else { return }
        openConversation(withId: conversationId, retriesLeft: 3)
    }

    private func openConversation(withId conversationId: String, retriesLeft: Int) {
        if let conversation = messagingManager.conversations.first(where: { $0.id == conversationId }) {
            showConversation(conversation)
        } else if retriesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.openConversation(withId: conversationId, retriesLeft: retriesLeft - 1)
            }
        }
    }

    private func showConversation(_ conversation: Conversation) {
        Logger.debug("🔍 ConversationsListViewController: showConversation called")
        Logger.debug("🔍 Conversation details: id=\(conversation.id)")
        Logger.debug("🔍 Conversation participants: \(conversation.participants)")
        Logger.debug("🔍 Conversation type: \(conversation.type)")
        Logger.debug("🔍 Conversation displayName: \(conversation.displayName)")
        
        // Validate conversation has required data
        guard !conversation.id.isEmpty else {
            Logger.debug("❌ ConversationsListViewController: Invalid conversation - missing ID")
            AlertPresenter.showError(title: "Error", message: "Unable to open conversation. Please try again.", from: self)
            return
        }
        
        // Immediately mark conversation as read locally for instant UI feedback
        messagingManager.markConversationAsReadLocally(conversation.id)
        
        // Show a brief loading indicator before navigation
        var loadingAlert: UIAlertController!
        loadingAlert = AlertPresenter.showLoading(message: "Opening conversation...", from: self) { [weak self] in
            guard let self = self else { return }
            Logger.debug("🔍 ConversationsListViewController: Creating ChatViewController")
            
            // Create and configure the chat view controller
            let chatVC = ChatViewController()
            chatVC.conversation = conversation
            
            // Navigate after a brief delay to show loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Logger.debug("🔍 ConversationsListViewController: Navigating to ChatViewController")
                loadingAlert.dismiss(animated: false) {
                    self.navigationController?.pushViewController(chatVC, animated: true)
                    Logger.debug("✅ ConversationsListViewController: Navigation to chat completed")
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
            Logger.debug("⚠️ ConversationsListViewController: Could not get conversation ID from cell")
            return
        }
        
        // Find the conversation by ID instead of index to avoid race conditions
        guard let conversation = messagingManager.conversations.first(where: { $0.id == conversationId }) else {
            Logger.debug("⚠️ ConversationsListViewController: Could not find conversation with ID: \(conversationId)")
            return
        }
        
        Logger.debug("✅ ConversationsListViewController: Selected conversation: \(conversation.displayName)")
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
            AlertPresenter.showConfirmation(
                title: "Delete Conversation",
                message: "Are you sure you want to delete this conversation? This action cannot be undone.",
                confirmTitle: "Delete",
                isDestructive: true,
                from: self,
                onConfirm: {
                // Delete the conversation
                self.messagingManager.deleteConversation(conversation.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            // Force update empty state after deletion
                            self.updateEmptyState()
                            completion(true)
                        case .failure(let error):
                            // Show error alert
                            AlertPresenter.showError(title: "Error", message: "Failed to delete conversation: \(error.localizedDescription)", from: self)
                            completion(false)
                        }
                    }
                }
            }, onCancel: {
                completion(false)
            })
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
            Logger.debug("Error: No current user ID")
            return
        }
        
        // Use the IDNormalizer to get the correct normalized user ID
        guard let otherUserId = IDNormalizer.getOtherUserId(from: connection, currentUserId: currentUserId) else {
            Logger.debug("❌ ConversationsListViewController: Could not determine other user ID")
            return
        }
        let connectionName = connection.connectedUser?.displayName ?? "User"
        
        Logger.debug("🔍 ConversationsListViewController: Creating conversation with user: \(otherUserId) (normalized)")
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Creating conversation with \(connectionName)...", from: self)
        
        // Track completion state for timeout handling
        var isCompleted = false
        
        // Set a timeout of 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if !isCompleted {
                Logger.debug("⚠️ ConversationsListViewController: Conversation creation timed out")
                loadingAlert.dismiss(animated: true) {
                    AlertPresenter.showError(title: "Connection Timeout", message: "Unable to create conversation. Please check your internet connection and try again.", from: self)
                }
            }
        }
        
        // Create or get conversation with selected connection
        messagingManager.createOrGetDirectConversation(with: otherUserId) { [weak self] result in
            isCompleted = true
            
            DispatchQueue.main.async {
                Logger.debug("🔍 ConversationsListViewController: Conversation creation result: \(result)")
                
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let conversation):
                        Logger.debug("✅ ConversationsListViewController: Successfully created/retrieved conversation")
                        Logger.debug("🔍 Conversation ID: \(conversation.id)")
                        Logger.debug("🔍 Conversation participants: \(conversation.participants)")
                        Logger.debug("🔍 Conversation type: \(conversation.type)")
                        
                        // The MessagingManager.createOrGetDirectConversation already adds the conversation to the list
                        // Just ensure the UI is updated
                        Logger.debug("🔍 Updating UI to show new conversation")
                        self?.tableView.reloadData()
                        self?.updateEmptyState()
                        
                        // Small delay to ensure UI updates before navigation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            Logger.debug("🔍 Navigating to conversation after delay")
                            self?.showConversation(conversation)
                        }
                    case .failure(let error):
                        Logger.debug("❌ ConversationsListViewController: Error creating conversation: \(error)")
                        
                        // Extract error details and show alert
                        var errorMessage = "Failed to create conversation"
                        
                        if case APIError.httpError(let statusCode, let data) = error {
                            if statusCode == 400 {
                                errorMessage = "Cannot create conversation with this user"
                            }
                            
                            if let data = data,
                               let serverMessage = String(data: data, encoding: .utf8) {
                                Logger.debug("Server error details: \(serverMessage)")
                                if serverMessage.contains("yourself") {
                                    errorMessage = "Cannot create conversation with yourself"
                                } else if let message = APIError.serverMessage(from: data) {
                                    errorMessage = message
                                }
                            }
                        } else if case APIError.noInternet = error {
                            errorMessage = "No internet connection. Please check your connection and try again."
                        } else if case APIError.requestFailed(let underlyingError) = error,
                                  let urlError = underlyingError as? URLError,
                                  urlError.code == .timedOut {
                            errorMessage = "Request timed out. Please try again."
                        }
                        
                        // Show alert
                        if let self { AlertPresenter.showError(title: "Error", message: errorMessage, from: self) }
                    }
                }
            }
        }
    }
}

// MARK: - SSE Setup
extension ConversationsListViewController {
    private func setupSSE() {
        SSEService.shared.addDelegate(self)
    }
}

// MARK: - SSEServiceDelegate
extension ConversationsListViewController: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        Logger.debug("📡 Conversations: Received SSE event: \(event.type)")
        
        switch event.type {
        case .newMessage:
            // New message received
            handleNewMessage(event.data)
            
        case .newSuggestion:
            // New suggestion received
            handleNewSuggestion(event.data)
            
        default:
            break
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        Logger.debug("📡 Conversations: SSE connected")
        sseConnected = true
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        Logger.debug("📡 Conversations: SSE disconnected")
        sseConnected = false
    }
    
    // MARK: - Event Handlers
    private func handleNewMessage(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Force refresh conversations to show new message
            self?.messagingManager.loadConversations(forceRefresh: true)
            
            // Show visual feedback
            self?.showNewMessageBanner(data)
            
            // Update badge count
            self?.messagingManager.updateUnreadCount()
        }
    }
    
    private func handleNewSuggestion(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            // Refresh suggestions count
            self?.checkForNewSuggestions()
        }
    }
    
    private func showNewMessageBanner(_ data: [String: Any]) {
        // Create a banner notification
        let banner = UIView()
        banner.backgroundColor = Constants.Colors.primary
        banner.layer.cornerRadius = 8
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        let senderName = data["senderName"] as? String ?? "Someone"
        label.text = "New message from \(senderName)"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        banner.addSubview(label)
        view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            banner.heightAnchor.constraint(equalToConstant: 44),
            
            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
        
        // Animate in
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: -20)
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            banner.alpha = 1
            banner.transform = .identity
        }
        
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3, animations: {
                banner.alpha = 0
                banner.transform = CGAffineTransform(translationX: 0, y: -20)
            }) { _ in
                banner.removeFromSuperview()
            }
        }
    }
}

// MARK: - GroupConnectionSelectionViewControllerDelegate
extension ConversationsListViewController: GroupConnectionSelectionViewControllerDelegate {
    func didSelectConnections(_ connections: [Connection], groupName: String?) {
        // Create loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Creating group...", from: self)
        
        // Get participant IDs
        let participantIds = connections.compactMap { connection in
            IDNormalizer.getOtherUserId(from: connection, currentUserId: AuthService.shared.getUserId() ?? "")
        }
        
        // Create group conversation
        messagingManager.createGroupConversation(
            participantIds: participantIds,
            name: groupName
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let conversation):
                        // Reload conversations and navigate to the new group
                        self?.messagingManager.loadConversations()
                        self?.tableView.reloadData()
                        self?.updateEmptyState()
                        
                        // Navigate to the conversation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self?.showConversation(conversation)
                        }
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - MessagesStarterViewDelegate
extension ConversationsListViewController: MessagesStarterViewDelegate {
    func messagesStarterDidTapSuggestions(_ view: MessagesStarterView) {
        AnalyticsService.shared.logEvent("empty_messages_suggestion", parameters: [:])
        suggestionsButtonTapped()
    }
    
    func messagesStarter(_ view: MessagesStarterView, didSelectUser user: User) {
        navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
    }
    
    /// Same as the suggested-people overlay: follow, then ask to connect
    func messagesStarter(_ view: MessagesStarterView, didTapConnect user: User, button: UIButton) {
        AnalyticsService.shared.logEvent("empty_messages_connect", parameters: [:])
        button.setTitle("Requested", for: .normal)
        button.setStyle(.following)
        button.isEnabled = false
        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            if case .success(let response) = result {
                AuthService.shared.recordFollowChange(userId: user.id, isFollowing: true)
                PiggyBankDepositView.play(credit: response.piggyBank)
            }
            NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
                guard case .failure(let error) = result else { return }
                DispatchQueue.main.async {
                    button.setTitle("Connect", for: .normal)
                    button.setStyle(.primary)
                    button.isEnabled = true
                    if let self { AlertPresenter.showError(error, from: self) }
                }
            }
        }
    }
    
    func messagesStarterDidTapInvite(_ view: MessagesStarterView) {
        AnalyticsService.shared.logEvent("empty_messages_invite", parameters: [:])
        let share = UIActivityViewController(activityItems: NetworkManager.shared.shareConnectionInvite(),
                                             applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        present(share, animated: true)
    }
    
    func messagesStarterDidTapFindPeople(_ view: MessagesStarterView) {
        AnalyticsService.shared.logEvent("empty_messages_find_people", parameters: [:])
        tabBarController?.selectedIndex = 1
    }
}
