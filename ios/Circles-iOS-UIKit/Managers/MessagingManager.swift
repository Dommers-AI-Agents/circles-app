import Foundation

class MessagingManager {
    static let shared = MessagingManager()
    
    private(set) var conversations: [Conversation] = []
    private(set) var activeMessages: [String: [Message]] = [:] // conversationId: messages
    private(set) var unreadCount: Int = 0
    private(set) var isLoadingConversations = false
    private(set) var isLoadingMessages = false
    private(set) var error: String?
    
    private let messagingService = MessagingService.shared
    private var authObserverId = "MessagingManager"
    private var messagePollingTimer: Timer?
    private var isMessagesTabActive = false
    
    private init() {
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        // Listen for authentication changes
        // print("🔍 MessagingManager: Setting up auth listener")
        AuthService.shared.addAuthStateListener(id: authObserverId) { [weak self] isAuthenticated in
            // print("🔍 MessagingManager: Auth state changed to: \(isAuthenticated)")
            if isAuthenticated {
                self?.startMessaging()
            } else {
                self?.stopMessaging()
            }
        }
    }
    
    // MARK: - Messaging Lifecycle
    
    private func startMessaging() {
        // print("🔍 MessagingManager: startMessaging called")
        loadConversations()
        startMessagePolling()
        updateUnreadCount()
    }
    
    // Public method to force initialization when we know we're authenticated
    func ensureInitialized() {
        // print("🔍 MessagingManager: ensureInitialized called")
        // print("🔍 MessagingManager: Has token = \(AuthService.shared.getToken() != nil)")
        
        // If we have a token but messaging hasn't started, start it now
        if AuthService.shared.getToken() != nil && messagePollingTimer == nil {
            // print("🔍 MessagingManager: Token exists but messaging not started, starting now")
            startMessaging()
        }
    }
    
    private func stopMessaging() {
        stopMessagePolling()
        clearData()
    }
    
    private func clearData() {
        conversations = []
        activeMessages = [:]
        unreadCount = 0
    }
    
    // MARK: - Tab Management
    
    func setMessagesTabActive(_ isActive: Bool) {
        // print("🔍 MessagingManager: Messages tab active: \(isActive)")
        isMessagesTabActive = isActive
        updatePollingInterval()
        
        // Force refresh when tab becomes active
        if isActive {
            loadConversations()
            updateUnreadCount()
        }
    }
    
    // MARK: - Polling (temporary until real-time is implemented)
    
    private func startMessagePolling() {
        updatePollingInterval()
    }
    
    private func updatePollingInterval() {
        // Stop existing timer
        messagePollingTimer?.invalidate()
        
        // Set interval based on whether Messages tab is active
        let interval: TimeInterval = isMessagesTabActive ? 5.0 : 10.0
        
        // Start new timer with appropriate interval
        messagePollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Refresh both conversations list and active messages
            self?.loadConversations()
            self?.refreshActiveConversations()
            self?.updateUnreadCount()
        }
    }
    
    private func stopMessagePolling() {
        messagePollingTimer?.invalidate()
        messagePollingTimer = nil
    }
    
    private func refreshActiveConversations() {
        // Refresh messages for active conversations
        for conversationId in activeMessages.keys {
            messagingService.fetchMessages(conversationId: conversationId, limit: 50, before: nil) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let messages):
                        // Check if there are new messages
                        let oldCount = self?.activeMessages[conversationId]?.count ?? 0
                        let newCount = messages.count
                        
                        // Update messages
                        self?.activeMessages[conversationId] = messages
                        
                        // Post notification if there are new messages
                        if newCount > oldCount {
                            NotificationCenter.default.post(
                                name: Notification.Name("NewMessagesReceived"),
                                object: nil,
                                userInfo: ["conversationId": conversationId]
                            )
                        }
                    case .failure(let error):
                        // print("⚠️ MessagingManager: Failed to refresh messages for conversation \(conversationId): \(error)")
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Conversations
    
    func loadConversations() {
        // print("🔍 MessagingManager: loadConversations called")
        // print("🔍 MessagingManager: Has auth token = \(AuthService.shared.getToken() != nil)")
        
        // Skip auth check if we have a token - this is a workaround for auth state detection issues
        guard AuthService.shared.getToken() != nil else {
            // print("⚠️ MessagingManager: No auth token, skipping conversation load")
            return
        }
        
        // Don't load if already loading
        guard !isLoadingConversations else {
            // print("🔍 MessagingManager: Already loading conversations, skipping duplicate request")
            return
        }
        
        isLoadingConversations = true
        
        messagingService.fetchConversations { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingConversations = false
                
                switch result {
                case .success(let conversations):
                    // print("🔍 MessagingManager: Fetched \(conversations.count) conversations successfully")
                    self?.conversations = conversations.sorted { conv1, conv2 in
                        // Sort by last message time, most recent first
                        let time1 = conv1.lastMessageTime ?? conv1.createdAt
                        let time2 = conv2.lastMessageTime ?? conv2.createdAt
                        return time1 > time2
                    }
                case .failure(let error):
                    // print("⚠️ MessagingManager: Failed to fetch conversations: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func createOrGetDirectConversation(with userId: String, completion: @escaping (Result<Conversation, Error>) -> Void) {
        messagingService.getOrCreateDirectConversation(with: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let conversation):
                    // Add to conversations if not already present
                    if !(self?.conversations.contains(where: { $0.id == conversation.id }) ?? false) {
                        self?.conversations.insert(conversation, at: 0)
                    }
                    completion(.success(conversation))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Messages
    
    func loadMessages(for conversationId: String, limit: Int = 50, before: String? = nil, showLoading: Bool = true) {
        if showLoading {
            isLoadingMessages = true
        }
        
        messagingService.fetchMessages(conversationId: conversationId, limit: limit, before: before) { [weak self] result in
            DispatchQueue.main.async {
                if showLoading {
                    self?.isLoadingMessages = false
                }
                
                switch result {
                case .success(let messages):
                    if before == nil {
                        // Initial load or refresh
                        self?.activeMessages[conversationId] = messages
                    } else {
                        // Pagination - append older messages
                        var existingMessages = self?.activeMessages[conversationId] ?? []
                        existingMessages.append(contentsOf: messages)
                        self?.activeMessages[conversationId] = existingMessages
                    }
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func sendMessage(
        conversationId: String,
        type: MessageType,
        content: String? = nil,
        mediaUrl: String? = nil,
        metadata: [String: Any]? = nil,
        completion: @escaping (Result<Message, Error>) -> Void
    ) {
        messagingService.sendMessage(
            conversationId: conversationId,
            type: type,
            content: content,
            mediaUrl: mediaUrl,
            metadata: metadata
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    // Add message to active messages
                    var messages = self?.activeMessages[conversationId] ?? []
                    messages.append(message)
                    self?.activeMessages[conversationId] = messages
                    
                    // Update conversation's last message
                    if let index = self?.conversations.firstIndex(where: { $0.id == conversationId }) {
                        var conversation = self?.conversations[index]
                        conversation?.lastMessage = message.displayContent
                        conversation?.lastMessageTime = message.createdAt
                        conversation?.lastMessageSenderId = message.senderId
                        
                        if let updatedConversation = conversation {
                            self?.conversations[index] = updatedConversation
                            
                            // Move to top of list
                            self?.conversations.remove(at: index)
                            self?.conversations.insert(updatedConversation, at: 0)
                        }
                    }
                    
                    completion(.success(message))
                case .failure(let error):
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    func markMessagesAsRead(conversationId: String, messageIds: [String]) {
        messagingService.markMessagesAsRead(conversationId: conversationId, messageIds: messageIds) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    // Update local unread count
                    if let index = self?.conversations.firstIndex(where: { $0.id == conversationId }) {
                        var conversation = self?.conversations[index]
                        if let currentUserId = AuthService.shared.getUserId() {
                            conversation?.unreadCounts?[currentUserId] = 0
                        }
                        
                        if let updatedConversation = conversation {
                            self?.conversations[index] = updatedConversation
                        }
                    }
                    
                    // Update global unread count
                    self?.updateUnreadCount()
                }
            }
        }
    }
    
    // MARK: - Unread Count
    
    func updateUnreadCount() {
        messagingService.getUnreadCount { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let response) = result {
                    let oldCount = self?.unreadCount ?? 0
                    self?.unreadCount = response.totalUnread
                    
                    // Post notification if count changed
                    if oldCount != response.totalUnread {
                        NotificationCenter.default.post(
                            name: Notification.Name("UnreadMessagesCountChanged"),
                            object: nil
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func getMessages(for conversationId: String) -> [Message] {
        return activeMessages[conversationId] ?? []
    }
    
    func getConversation(by id: String) -> Conversation? {
        return conversations.first { $0.id == id }
    }
    
    func deleteMessage(messageId: String, conversationId: String) {
        messagingService.deleteMessage(messageId: messageId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    // Update local messages
                    if var messages = self?.activeMessages[conversationId] {
                        // Remove the deleted message from the array
                        messages.removeAll { $0.id == messageId }
                        self?.activeMessages[conversationId] = messages
                    }
                }
            }
        }
    }
    
    func editMessage(messageId: String, conversationId: String, newContent: String, completion: @escaping (Result<Message, Error>) -> Void) {
        messagingService.editMessage(messageId: messageId, content: newContent) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedMessage):
                    // Update local messages
                    if var messages = self?.activeMessages[conversationId] {
                        if let index = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[index] = updatedMessage
                            self?.activeMessages[conversationId] = messages
                        }
                    }
                    completion(.success(updatedMessage))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func deleteConversation(_ conversationId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        messagingService.deleteConversation(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove conversation from local array
                    self?.conversations.removeAll { $0.id == conversationId }
                    
                    // Remove messages for this conversation
                    self?.activeMessages.removeValue(forKey: conversationId)
                    
                    // Update unread count
                    self?.updateUnreadCount()
                    
                    completion(.success(()))
                    
                case .failure(let error):
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
}