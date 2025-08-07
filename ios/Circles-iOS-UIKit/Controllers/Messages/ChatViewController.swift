import UIKit

// MARK: - MessageCellDelegate
protocol MessageCellDelegate: AnyObject {
    func didTapProfileImage(for userId: String)
}

class ChatViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemBackground
        table.transform = CGAffineTransform(scaleX: 1, y: -1) // Invert for bottom-to-top layout
        table.keyboardDismissMode = .interactive
        return table
    }()
    
    private let messageInputContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor
        return view
    }()
    
    private let messageTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 18
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.isScrollEnabled = false
        // Fix RTI issues
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        return textView
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Type a message..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let sendButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.up.circle.fill")
        button.tintColor = Constants.Colors.primary
        button.isEnabled = false
        return button
    }()
    
    private let attachButton: UIButton = {
        let button = UIButton.iconButton(systemName: "plus.circle")
        button.tintColor = .systemGray
        return button
    }()
    
    private let loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Properties
    var conversation: Conversation?
    private let messagingManager = MessagingManager.shared
    private var messageUpdateTimer: Timer?
    private var messages: [Message] = []
    private var keyboardHeight: CGFloat = 0
    private var messageInputBottomConstraint: NSLayoutConstraint!
    private let cellIdentifier = "MessageCell"
    private var hasCompletedInitialLoad = false
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var reloadsDataOnAppear: Bool { false }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("🔍 ChatViewController: viewDidLoad called")
        if let conv = conversation {
            print("🔍 ChatViewController: Conversation loaded - ID: \(conv.id)")
            print("🔍 ChatViewController: Conversation type: \(conv.type)")
            print("🔍 ChatViewController: Conversation participants: \(conv.participants)")
        } else {
            print("❌ ChatViewController: No conversation set!")
        }
        
        setupView()
        setupTableView()
        setupMessageInput()
        setupKeyboardHandling(bottomConstraint: messageInputBottomConstraint, dismissOnTap: false)
        setupSubscribers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        markMessagesAsRead()
        
        // Refresh navigation bar in case group settings were updated
        if conversation?.type == .group {
            setupNavigationBarWithTappableTitle()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        markMessagesAsRead()
        removeKeyboardHandling()
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        messageUpdateTimer?.invalidate()
    }
    
    // MARK: - Setup
    private func setupView() {
        // Debug logging
        print("🔍 ChatViewController.setupView: conversation type = \(conversation?.type.rawValue ?? "nil")")
        print("🔍 ChatViewController.setupView: conversation name = \(conversation?.displayName ?? "nil")")
        print("🔍 ChatViewController.setupView: is group = \(conversation?.type == .group)")
        
        // For group conversations, make title tappable for settings
        if conversation?.type == .group {
            print("✅ ChatViewController: Setting up group conversation UI")
            setupNavigationBarWithTappableTitle()
            // Add settings gear icon for group conversations
            addNavigationBarButton(image: "gearshape.fill", position: .right, action: #selector(openGroupSettings))
        } else {
            print("ℹ️ ChatViewController: Setting up direct conversation UI")
            setupNavigationBar(title: conversation?.displayName ?? "Chat")
            addNavigationBarButton(image: "info.circle", position: .right, action: #selector(showConversationInfo))
        }
        
        view.addSubview(tableView)
        view.addSubview(messageInputContainer)
        
        // Add loading view
        view.addSubview(loadingView)
        loadingView.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor)
        ])
        
        // Show loading initially
        showLoading()
    }
    
    private func setupNavigationBarWithTappableTitle() {
        setupNavigationBar(title: conversation?.displayName ?? "Group Chat")
        
        // Create a button for better touch handling
        let titleButton = UIButton(type: .system)
        titleButton.frame = CGRect(x: 0, y: 0, width: 250, height: 44)
        
        // Create group avatar image view
        let avatarImageView = UIImageView()
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.backgroundColor = Constants.Colors.tertiaryBackground
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Load group avatar
        if let groupAvatar = conversation?.avatar, !groupAvatar.isEmpty {
            ImageService.shared.loadImage(from: groupAvatar) { image in
                DispatchQueue.main.async {
                    avatarImageView.image = image ?? UIImage(systemName: "person.3.fill")
                }
            }
        } else {
            avatarImageView.image = UIImage(systemName: "person.3.fill")
            avatarImageView.tintColor = Constants.Colors.label
        }
        
        // Create title label
        let titleLabel = UILabel()
        titleLabel.text = conversation?.displayName ?? "Group Chat"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        // Create chevron icon to indicate tappability
        let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.down.circle.fill"))
        chevronImageView.tintColor = .systemGray
        chevronImageView.contentMode = .scaleAspectFit
        
        // Stack view to arrange avatar, title and chevron
        let stackView = UIStackView(arrangedSubviews: [avatarImageView, titleLabel, chevronImageView])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        
        titleButton.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            // Avatar constraints
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            stackView.centerXAnchor.constraint(equalTo: titleButton.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: titleButton.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleButton.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: titleButton.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: titleButton.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: titleButton.bottomAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 20),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Add action to button
        titleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        
        // Add highlight effect
        titleButton.showsMenuAsPrimaryAction = false
        titleButton.adjustsImageWhenHighlighted = true
        
        navigationItem.titleView = titleButton
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: cellIdentifier)
        // Removed ConnectionRequestMessageCell registration - no longer needed
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: messageInputContainer.topAnchor)
        ])
    }
    
    private func setupMessageInput() {
        messageInputContainer.addSubview(attachButton)
        messageInputContainer.addSubview(messageTextView)
        messageInputContainer.addSubview(placeholderLabel)
        messageInputContainer.addSubview(sendButton)
        
        messageTextView.delegate = self
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        attachButton.addTarget(self, action: #selector(showAttachmentOptions), for: .touchUpInside)
        
        messageInputBottomConstraint = messageInputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        
        NSLayoutConstraint.activate([
            messageInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageInputBottomConstraint,
            messageInputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            attachButton.leadingAnchor.constraint(equalTo: messageInputContainer.leadingAnchor, constant: 8),
            attachButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),
            
            messageTextView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            messageTextView.topAnchor.constraint(equalTo: messageInputContainer.topAnchor, constant: 8),
            messageTextView.bottomAnchor.constraint(equalTo: messageInputContainer.bottomAnchor, constant: -8),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            messageTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: messageTextView.leadingAnchor, constant: 16),
            placeholderLabel.centerYAnchor.constraint(equalTo: messageTextView.centerYAnchor),
            
            sendButton.trailingAnchor.constraint(equalTo: messageInputContainer.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: messageInputContainer.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    
    private func setupSubscribers() {
        print("🔍 ChatViewController: setupSubscribers() called")
        
        guard let conversation = conversation else {
            print("❌ ChatViewController: setupSubscribers() - conversation is nil!")
            return
        }
        
        let conversationId = conversation.id
        
        print("✅ ChatViewController: setupSubscribers() - conversationId: \(conversationId)")
        
        // Listen for new messages notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages(_:)),
            name: Notification.Name("NewMessagesReceived"),
            object: nil
        )
        print("🔍 ChatViewController: Added observer for NewMessagesReceived")
        
        // Listen for conversation updates (e.g., avatar changes)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationUpdated(_:)),
            name: Notification.Name("ConversationUpdated"),
            object: nil
        )
        print("🔍 ChatViewController: Added observer for ConversationUpdated")
        
        // Poll for message updates (as backup)
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Commented out repetitive timer logs - uncomment for debugging
            // print("🔍 ChatViewController: Timer fired - checking for messages in conversationId: \(conversationId)")
            
            if let messages = self.messagingManager.activeMessages[conversationId] {
                // print("🔍 ChatViewController: Found \(messages.count) messages in activeMessages")
                
                // Filter out connection request messages (handled in My Network tab)
                let filteredMessages = messages.filter { $0.type != .connectionRequest }
                // print("🔍 ChatViewController: After filtering, have \(filteredMessages.count) messages")
                
                // Hide loading on initial load only (not for subsequent timer refreshes)
                if self.messages.isEmpty && !self.hasCompletedInitialLoad {
                    print("🔍 ChatViewController: Initial load complete, hiding loading (filtered messages: \(filteredMessages.count))")
                    self.hasCompletedInitialLoad = true
                    self.hideLoading()
                }
                
                if filteredMessages.count != self.messages.count {
                    // Only log significant changes, not every timer check
                    if abs(filteredMessages.count - self.messages.count) > 0 {
                        print("🔍 ChatViewController: Message count changed from \(self.messages.count) to \(filteredMessages.count)")
                    }
                    self.messages = filteredMessages
                    self.tableView.reloadData()
                    self.scrollToBottom(animated: true)
                }
            } else {
                // Only log this once, not every 2 seconds
                if !self.hasCompletedInitialLoad {
                    print("⚠️ ChatViewController: No messages found in activeMessages for conversationId: \(conversationId)")
                }
                
                // Hide loading if this is the initial load and no messages are found
                if self.messages.isEmpty && !self.hasCompletedInitialLoad {
                    print("🔍 ChatViewController: Initial load complete with no messages, hiding loading")
                    self.hasCompletedInitialLoad = true
                    self.hideLoading()
                }
            }
        }
        
        // print("🔍 ChatViewController: Message update timer scheduled")
    }
    
    @objc private func handleConversationUpdated(_ notification: Notification) {
        print("🔍 ChatViewController: handleConversationUpdated notification received")
        
        guard let userInfo = notification.userInfo,
              let updatedConversation = userInfo["conversation"] as? Conversation,
              updatedConversation.id == conversation?.id else {
            return
        }
        
        // Update our conversation reference
        self.conversation = updatedConversation
        
        // Refresh navigation bar to show updated avatar/name
        if conversation?.type == .group {
            DispatchQueue.main.async { [weak self] in
                self?.setupNavigationBarWithTappableTitle()
            }
        }
    }
    
    @objc private func handleNewMessages(_ notification: Notification) {
        print("🔍 ChatViewController: handleNewMessages notification received")
        
        guard let userInfo = notification.userInfo else {
            print("⚠️ ChatViewController: handleNewMessages - no userInfo in notification")
            return
        }
        
        guard let notificationConversationId = userInfo["conversationId"] as? String else {
            print("⚠️ ChatViewController: handleNewMessages - no conversationId in userInfo")
            return
        }
        
        print("🔍 ChatViewController: handleNewMessages - notificationConversationId: \(notificationConversationId)")
        print("🔍 ChatViewController: handleNewMessages - current conversation.id: \(conversation?.id ?? "nil")")
        
        guard notificationConversationId == conversation?.id else {
            print("⚠️ ChatViewController: handleNewMessages - conversationId mismatch, ignoring notification")
            return
        }
        
        print("✅ ChatViewController: handleNewMessages - conversationId matches, refreshing messages")
        
        // Refresh messages from MessagingManager
        if let messages = messagingManager.activeMessages[notificationConversationId] {
            print("🔍 ChatViewController: handleNewMessages - found \(messages.count) messages in activeMessages")
            
            // Filter out connection request messages (handled in My Network tab)
            let filteredMessages = messages.filter { $0.type != .connectionRequest }
            print("🔍 ChatViewController: handleNewMessages - after filtering: \(filteredMessages.count) messages")
            
            // Hide loading on initial load only (not for subsequent notifications)
            if self.messages.isEmpty && !self.hasCompletedInitialLoad {
                print("🔍 ChatViewController: handleNewMessages - initial load complete, hiding loading (filtered messages: \(filteredMessages.count))")
                self.hasCompletedInitialLoad = true
                self.hideLoading()
            }
            
            self.messages = filteredMessages
            tableView.reloadData()
            scrollToBottom(animated: true)
        } else {
            print("⚠️ ChatViewController: handleNewMessages - no messages found in activeMessages for conversationId: \(notificationConversationId)")
            
            // Hide loading if this is the initial load and no messages are found
            if self.messages.isEmpty && !self.hasCompletedInitialLoad {
                print("🔍 ChatViewController: handleNewMessages - initial load complete with no messages, hiding loading")
                self.hasCompletedInitialLoad = true
                self.hideLoading()
            }
        }
    }
    
    // MARK: - BaseViewController Implementation
    override func loadData(completion: (() -> Void)?) {
        print("🔍 ChatViewController: loadData() called")
        
        guard let conversation = conversation else {
            print("❌ ChatViewController: loadData() - conversation is nil!")
            completion?()
            return
        }
        
        let conversationId = conversation.id
        
        print("✅ ChatViewController: loadData() - conversationId: \(conversationId)")
        print("🔍 ChatViewController: Conversation details:")
        print("   - ID: \(conversationId)")
        print("   - Type: \(conversation.type)")
        print("   - Participants: \(conversation.participants)")
        print("   - Display Name: \(conversation.displayName ?? "nil")")
        print("   - Current messages count: \(messages.count)")
        
        print("🔍 ChatViewController: Calling messagingManager.loadMessages(for: \(conversationId))")
        messagingManager.loadMessages(for: conversationId)
        
        // Complete after a short delay to allow messages to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion?()
        }
    }
    
    private func showLoading() {
        loadingView.isHidden = false
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        messageInputContainer.isHidden = true
    }
    
    private func hideLoading() {
        loadingView.isHidden = true
        loadingIndicator.stopAnimating()
        tableView.isHidden = false
        messageInputContainer.isHidden = false
    }
    
    private func markMessagesAsRead() {
        guard let conversationId = conversation?.id else { return }
        
        let unreadMessageIds = messages
            .filter { !$0.isCurrentUserMessage && !$0.isRead }
            .map { $0.id }
        
        if !unreadMessageIds.isEmpty {
            messagingManager.markMessagesAsRead(conversationId: conversationId, messageIds: unreadMessageIds)
        }
    }
    
    // MARK: - Actions
    @objc private func sendMessage() {
        guard let conversationId = conversation?.id else { return }
        
        // Get text directly from text view
        let text = messageTextView.text ?? ""
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else { return }
        
        // Store the message text before clearing
        let messageToSend = trimmedText
        
        // Clear input and temporary storage
        DispatchQueue.main.async { [weak self] in
            self?.messageTextView.text = ""
            self?.textViewDidChange(self?.messageTextView ?? UITextView())
        }
        
        // Send message
        messagingManager.sendMessage(
            conversationId: conversationId,
            type: .text,
            content: messageToSend
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.showError(error)
                // Restore text on failure
                DispatchQueue.main.async {
                    self?.messageTextView.text = messageToSend
                    self?.textViewDidChange(self?.messageTextView ?? UITextView())
                }
            }
        }
    }
    
    @objc private func showAttachmentOptions() {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            (title: "Share Circle", style: .default, handler: { [weak self] in 
                _ = self?.shareCircle()
            }),
            (title: "Share Place", style: .default, handler: { [weak self] in 
                _ = self?.sharePlace()
            }),
            (title: "Share Location", style: .default, handler: { [weak self] in 
                _ = self?.shareLocation()
            })
        ]
        
        // Add group settings option for group conversations
        if conversation?.type == .group {
            actions.insert(
                (title: "Group Settings", style: .default, handler: { [weak self] in
                    self?.titleTapped()
                }),
                at: 0
            )
        }
        
        AlertPresenter.showActionSheet(
            actions: actions,
            from: self,
            sourceView: attachButton,
            sourceRect: attachButton.bounds
        )
    }
    
    @objc private func showConversationInfo() {
        // TODO: Show conversation info/settings
    }
    
    @objc private func openGroupSettings() {
        titleTapped()
    }
    
    @objc private func titleTapped() {
        print("🔍 ChatViewController: Title tapped")
        print("🔍 ChatViewController: Conversation type = \(conversation?.type.rawValue ?? "nil")")
        print("🔍 ChatViewController: Is group = \(conversation?.type == .group)")
        print("🔍 ChatViewController: Conversation ID = \(conversation?.id ?? "nil")")
        
        // Provide haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        guard let conversation = conversation else {
            print("❌ ChatViewController: No conversation available")
            return
        }
        
        guard conversation.type == .group else {
            print("❌ ChatViewController: Not a group conversation, type = \(conversation.type.rawValue)")
            return
        }
        
        print("✅ ChatViewController: Opening group settings for conversation: \(conversation.displayName)")
        let settingsVC = GroupConversationSettingsViewController(conversation: conversation)
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }
    
    
    // MARK: - Helper Methods
    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
    
    private func shareCircle() {
        // TODO: Implement circle sharing
    }
    
    private func sharePlace() {
        // TODO: Implement place sharing
    }
    
    private func shareLocation() {
        // TODO: Implement location sharing
    }
    
    @objc private func toggleNotifications() {
        guard let conversationId = conversation?.id else { return }
        
        let currentEnabled = conversation?.notificationsEnabled ?? true
        let newEnabled = !currentEnabled
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: newEnabled ? "Enabling notifications..." : "Disabling notifications...", from: self)
        
        messagingManager.toggleNotifications(for: conversationId, enabled: newEnabled) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Update the conversation object
                        if let currentUserId = AuthService.shared.getUserId() {
                            self?.conversation?.notificationSettings?[currentUserId] = newEnabled
                        }
                        
                        // Update the navigation bar button
                        let bellImage = newEnabled ? "bell.fill" : "bell.slash.fill"
                        self?.navigationItem.rightBarButtonItem?.image = UIImage(systemName: bellImage)
                        
                        // Show confirmation
                        let message = newEnabled ? "Notifications enabled for this group" : "Notifications disabled for this group"
                        self?.showSuccess(message)
                        
                    case .failure(let error):
                        self?.showError("Failed to update notification settings: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    
    private func deleteMessage(at indexPath: IndexPath) {
        let messageIndex = messages.count - 1 - indexPath.row
        guard messageIndex >= 0 && messageIndex < messages.count else { return }
        
        let message = messages[messageIndex]
        guard let conversationId = conversation?.id else { return }
        
        // Store the message for potential restoration
        let deletedMessage = message
        
        // Remove from local array immediately for better UX
        messages.remove(at: messageIndex)
        
        // Animate the deletion
        tableView.performBatchUpdates({
            tableView.deleteRows(at: [indexPath], with: .fade)
        }) { [weak self] _ in
            // Call the messaging manager to delete from backend
            self?.messagingManager.deleteMessage(messageId: deletedMessage.id, conversationId: conversationId)
        }
    }
}

// MARK: - UITableViewDataSource
extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[messages.count - 1 - indexPath.row] // Reverse order due to inverted table
        
        // All connection request messages are now filtered out, so only handle regular messages
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! MessageCell
        cell.delegate = self
        cell.configure(with: message, conversation: conversation)
        cell.transform = CGAffineTransform(scaleX: 1, y: -1) // Invert cell
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let message = messages[messages.count - 1 - indexPath.row]
        
        // Allow deletion of user's own messages OR connection request messages
        guard message.isCurrentUserMessage || message.type == .connectionRequest else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteMessage(at: indexPath)
            completionHandler(true)
        }
        
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - UITextViewDelegate
extension ChatViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        // No special handling needed
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // No special handling needed
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Only handle return key for sending messages
        if text == "\n" {
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendMessage()
                return false
            }
        }
        
        // Let UITextView handle all other text changes naturally
        return true
    }
    
    func textViewDidChange(_ textView: UITextView) {
        // Update placeholder visibility
        placeholderLabel.isHidden = !textView.text.isEmpty
        
        // Update send button state
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.tintColor = hasText ? Constants.Colors.primary : .systemGray3
        
        // Adjust text view height
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        textView.isScrollEnabled = size.height > 120
        
        // Force layout update to prevent RTI issues
        textView.layoutIfNeeded()
    }
}

// MARK: - ConnectionRequestMessageCellDelegate
extension ChatViewController: ConnectionRequestMessageCellDelegate {
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didAcceptConnectionId connectionId: String) {
        // Accept the connection request
        NetworkManager.shared.acceptConnection(connectionId) { [weak self] result in
            switch result {
            case .success:
                // Update the message to mark as handled
                if let indexPath = self?.tableView.indexPath(for: cell) {
                    let messageIndex = (self?.messages.count ?? 0) - 1 - indexPath.row
                    if messageIndex >= 0 && messageIndex < (self?.messages.count ?? 0) {
                        // Simply reload the cell - the button state will be updated based on the connection status
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                }
                
                // Show success message
                DispatchQueue.main.async {
                    self?.showSuccess("Connection request accepted")
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }
    
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didDeclineConnectionId connectionId: String) {
        // Decline the connection request
        NetworkManager.shared.declineConnection(connectionId) { [weak self] result in
            switch result {
            case .success:
                // Update the message to mark as handled
                if let indexPath = self?.tableView.indexPath(for: cell) {
                    let messageIndex = (self?.messages.count ?? 0) - 1 - indexPath.row
                    if messageIndex >= 0 && messageIndex < (self?.messages.count ?? 0) {
                        // Simply reload the cell - the button state will be updated based on the connection status
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                }
                
                // Show success message
                DispatchQueue.main.async {
                    self?.showSuccess("Connection request declined")
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }
    
    func connectionRequestCellDidTapDelete(_ cell: ConnectionRequestMessageCell) {
        // Find the index path for this cell
        if let indexPath = tableView.indexPath(for: cell) {
            // Delete the message
            deleteMessage(at: indexPath)
        }
    }
}

// MARK: - MessageCell
class MessageCell: UITableViewCell {
    
    // MARK: - Delegate
    weak var delegate: MessageCellDelegate?
    private var currentUserId: String?
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let senderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var bubbleLeadingToAvatarConstraint: NSLayoutConstraint!
    private var bubbleLeadingToContentConstraint: NSLayoutConstraint!
    private var bubbleTrailingToAvatarConstraint: NSLayoutConstraint!
    private var avatarTrailingConstraint: NSLayoutConstraint!
    private var avatarLeadingConstraint: NSLayoutConstraint!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(avatarImageView)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(senderLabel)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(timeLabel)
        
        // Add tap gesture to avatar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(tapGesture)
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        
        // Constraints for bubble with avatar on left (received messages)
        bubbleLeadingToAvatarConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8)
        bubbleLeadingToContentConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        
        // Constraints for bubble with avatar on right (sent messages in direct conversations)
        bubbleTrailingToAvatarConstraint = bubbleView.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8)
        avatarTrailingConstraint = avatarImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        avatarLeadingConstraint = avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        
        NSLayoutConstraint.activate([
            // Avatar constraints (position will be controlled dynamically)
            avatarImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            
            senderLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            senderLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            messageLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 2),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            timeLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with message: Message, conversation: Conversation?) {
        messageLabel.text = message.displayContent
        timeLabel.text = message.formattedTime
        
        // Store user ID for tap handling (only for received messages)
        if !message.isCurrentUserMessage {
            self.currentUserId = message.senderId
        } else {
            self.currentUserId = nil
        }
        
        if message.isCurrentUserMessage {
            // Sent message
            bubbleView.backgroundColor = Constants.Colors.primary
            messageLabel.textColor = .white
            timeLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            senderLabel.isHidden = true
            avatarImageView.isHidden = true
            
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
            bubbleLeadingToAvatarConstraint.isActive = false
            bubbleLeadingToContentConstraint.isActive = false
            bubbleTrailingToAvatarConstraint.isActive = false
            avatarTrailingConstraint.isActive = false
            avatarLeadingConstraint.isActive = false
            
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner]
        } else {
            // Received message
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            timeLabel.textColor = .secondaryLabel
            
            // Show sender name in group chats
            if let senderName = message.senderDetails?.displayName {
                senderLabel.text = senderName
                senderLabel.isHidden = false
            } else {
                senderLabel.isHidden = true
            }
            
            // Show avatar for both group and direct conversations
            avatarImageView.isHidden = false
            
            if conversation?.type == .group {
                // Load sender avatar if available, otherwise use group avatar
                if let senderAvatar = message.senderDetails?.profilePicture, !senderAvatar.isEmpty {
                    ImageService.shared.loadImage(from: senderAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.circle.fill")
                        }
                    }
                } else if let groupAvatar = conversation?.avatar, !groupAvatar.isEmpty {
                    ImageService.shared.loadImage(from: groupAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.3.fill")
                        }
                    }
                } else {
                    // Show initials or default avatar
                    if let senderName = message.senderDetails?.displayName {
                        avatarImageView.image = createInitialsImage(for: senderName)
                    } else {
                        avatarImageView.image = UIImage(systemName: "person.3.fill")
                    }
                }
            } else {
                // Direct conversation - load sender's avatar
                if let senderAvatar = message.senderDetails?.profilePicture, !senderAvatar.isEmpty {
                    ImageService.shared.loadImage(from: senderAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.circle.fill")
                        }
                    }
                } else {
                    // Show initials or default avatar
                    if let senderName = message.senderDetails?.displayName {
                        avatarImageView.image = createInitialsImage(for: senderName)
                    } else {
                        avatarImageView.image = UIImage(systemName: "person.circle.fill")
                    }
                }
            }
            
            // Use constraints with avatar on the left
            leadingConstraint.isActive = false
            bubbleLeadingToContentConstraint.isActive = false
            bubbleLeadingToAvatarConstraint.isActive = true
            bubbleTrailingToAvatarConstraint.isActive = false
            avatarTrailingConstraint.isActive = false
            avatarLeadingConstraint.isActive = true
            
            trailingConstraint.isActive = false
            bubbleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        // Update constraints for sender label
        if senderLabel.isHidden {
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8).isActive = true
        }
    }
    
    @objc private func avatarTapped() {
        guard let userId = currentUserId else { return }
        delegate?.didTapProfileImage(for: userId)
    }
    
    private func createInitialsImage(for name: String) -> UIImage {
        let initials = name.components(separatedBy: " ")
            .compactMap { $0.first?.uppercased() }
            .prefix(2)
            .joined()
        
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            Constants.Colors.tertiaryBackground.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: Constants.Colors.label
            ]
            
            let textSize = initials.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            initials.draw(in: textRect, withAttributes: attributes)
        }
    }
}

// MARK: - MessageCellDelegate
extension ChatViewController: MessageCellDelegate {
    func didTapProfileImage(for userId: String) {
        print("🔍 Profile image tapped for userId: \(userId)")
        
        // Check if the user is connected to navigate to their profile
        UserService.shared.fetchUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let user):
                    print("✅ Found user: \(user.displayName)")
                    self.navigateToUserProfile(user: user)
                case .failure(let error):
                    print("❌ Failed to fetch user profile: \(error)")
                    self.showError("Could not load user profile")
                }
            }
        }
    }
    
    private func navigateToUserProfile(user: User) {
        // Navigate to ProfileViewController just like in My Network tab
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}