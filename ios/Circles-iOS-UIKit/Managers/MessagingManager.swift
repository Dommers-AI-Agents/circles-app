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
    
    // Cache properties
    private var conversationsCache: [Conversation]?
    private var conversationsCacheTime: Date?
    private let cacheValidityDuration: TimeInterval = 30 // 30 seconds cache
    
    // Track conversations marked as read locally to prevent server overwrite
    private var locallyMarkedAsRead: Set<String> = []
    
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
        // Message polling disabled - using SSE for real-time updates
        // startMessagePolling()
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
        conversationsCache = nil
        conversationsCacheTime = nil
    }
    
    // MARK: - Tab Management
    
    func setMessagesTabActive(_ isActive: Bool) {
        // print("🔍 MessagingManager: Messages tab active: \(isActive)")
        isMessagesTabActive = isActive
        updatePollingInterval()
        
        // Force refresh when tab becomes active
        if isActive {
            loadConversations(forceRefresh: true)
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
                            // Invalidate conversation cache when new messages arrive
                            self?.conversationsCache = nil
                            self?.conversationsCacheTime = nil
                            
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
    
    func loadConversations(forceRefresh: Bool = false) {
        // print("🔍 MessagingManager: loadConversations called (forceRefresh: \(forceRefresh))")
        // print("🔍 MessagingManager: Has auth token = \(AuthService.shared.getToken() != nil)")
        
        // Skip auth check if we have a token - this is a workaround for auth state detection issues
        guard AuthService.shared.getToken() != nil else {
            // print("⚠️ MessagingManager: No auth token, skipping conversation load")
            return
        }
        
        // Check cache validity unless force refresh is requested
        if !forceRefresh, let cachedConversations = conversationsCache, let cacheTime = conversationsCacheTime {
            let cacheAge = Date().timeIntervalSince(cacheTime)
            if cacheAge < cacheValidityDuration {
                // Using cached conversations
                self.conversations = cachedConversations
                return
            }
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
                case .success(let fetchedConversations):
                    // print("🔍 MessagingManager: Fetched \(fetchedConversations.count) conversations successfully")
                    
                    // Preserve locally marked as read status
                    var updatedConversations = fetchedConversations
                    if let currentUserId = AuthService.shared.getUserId() {
                        for i in 0..<updatedConversations.count {
                            let conversationId = updatedConversations[i].id
                            if self?.locallyMarkedAsRead.contains(conversationId) == true {
                                // Preserve the local read status
                                updatedConversations[i].unreadCounts?[currentUserId] = 0
                                print("🔍 MessagingManager: Preserving local read status for conversation \(conversationId)")
                            }
                        }
                    }
                    
                    let sortedConversations = updatedConversations.sorted { conv1, conv2 in
                        // Sort by last message time, most recent first
                        let time1 = conv1.lastMessageTime ?? conv1.createdAt
                        let time2 = conv2.lastMessageTime ?? conv2.createdAt
                        return time1 > time2
                    }
                    
                    // Update cache
                    self?.conversationsCache = sortedConversations
                    self?.conversationsCacheTime = Date()
                    
                    self?.conversations = sortedConversations
                case .failure(let error):
                    // print("⚠️ MessagingManager: Failed to fetch conversations: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    
    // MARK: - Messages
    
    func loadMessages(for conversationId: String, limit: Int = 50, before: String? = nil, showLoading: Bool = true) {
        print("🔍 MessagingManager: loadMessages called for conversationId: \(conversationId)")
        print("🔍 MessagingManager: limit: \(limit), before: \(before ?? "nil"), showLoading: \(showLoading)")
        
        if showLoading {
            isLoadingMessages = true
        }
        
        print("🔍 MessagingManager: Calling messagingService.fetchMessages...")
        messagingService.fetchMessages(conversationId: conversationId, limit: limit, before: before) { [weak self] result in
            DispatchQueue.main.async {
                if showLoading {
                    self?.isLoadingMessages = false
                }
                
                switch result {
                case .success(let messages):
                    print("✅ MessagingManager: Successfully fetched \(messages.count) messages for conversationId: \(conversationId)")
                    
                    if before == nil {
                        // Initial load or refresh
                        print("🔍 MessagingManager: Initial load - storing \(messages.count) messages")
                        self?.activeMessages[conversationId] = messages
                    } else {
                        // Pagination - append older messages
                        var existingMessages = self?.activeMessages[conversationId] ?? []
                        print("🔍 MessagingManager: Pagination - appending \(messages.count) messages to existing \(existingMessages.count)")
                        existingMessages.append(contentsOf: messages)
                        self?.activeMessages[conversationId] = existingMessages
                    }
                    
                    // Post notification that new messages were received
                    print("🔍 MessagingManager: Posting NewMessagesReceived notification")
                    NotificationCenter.default.post(
                        name: Notification.Name("NewMessagesReceived"),
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                    
                case .failure(let error):
                    print("❌ MessagingManager: Failed to fetch messages: \(error.localizedDescription)")
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
                            
                            // Update cache with the reordered conversations
                            self?.conversationsCache = self?.conversations
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
                            // Update cache with the modified conversation
                            self?.conversationsCache = self?.conversations
                            
                            // Remove from locally marked set since it's now synced with server
                            self?.locallyMarkedAsRead.remove(conversationId)
                            
                            // Post notification that conversations have been updated
                            NotificationCenter.default.post(
                                name: Notification.Name("ConversationsUpdated"),
                                object: nil,
                                userInfo: ["conversationId": conversationId]
                            )
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
                        // Invalidate cache when unread count changes
                        self?.conversationsCache = nil
                        self?.conversationsCacheTime = nil
                        
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
    
    // Mark conversation as read locally (optimistic update)
    func markConversationAsReadLocally(_ conversationId: String) {
        guard let currentUserId = AuthService.shared.getUserId(),
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else { 
            print("⚠️ MessagingManager: Could not find conversation or user ID")
            return 
        }
        
        var conversation = conversations[index]
        let previousUnreadCount = conversation.unreadCounts?[currentUserId] ?? 0
        
        print("🔍 MessagingManager: Marking conversation \(conversationId) as read locally. Previous unread count: \(previousUnreadCount)")
        
        // Only update if there were unread messages
        if previousUnreadCount > 0 {
            // Update the conversation's unread count
            conversation.unreadCounts?[currentUserId] = 0
            conversations[index] = conversation
            
            // Track this conversation as locally marked read
            locallyMarkedAsRead.insert(conversationId)
            
            // Update cache with new data
            conversationsCache = conversations
            conversationsCacheTime = Date() // Reset cache time
            
            print("✅ MessagingManager: Updated conversation unread count to 0 and cache")
            
            // Update global unread count
            unreadCount = max(0, unreadCount - previousUnreadCount)
            
            // Post notifications
            NotificationCenter.default.post(
                name: Notification.Name("UnreadMessagesCountChanged"),
                object: nil
            )
            
            NotificationCenter.default.post(
                name: Notification.Name("ConversationsUpdated"),
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
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
    
    // MARK: - Create or Get Direct Conversation
    
    func createOrGetDirectConversation(with userId: String, completion: @escaping (Result<Conversation, Error>) -> Void) {
        print("🔍 MessagingManager: createOrGetDirectConversation called with userId: \(userId)")
        
        messagingService.getOrCreateDirectConversation(with: userId) { [weak self] result in
            DispatchQueue.main.async {
                print("🔍 MessagingManager: Received response from getOrCreateDirectConversation")
                
                switch result {
                case .success(let conversation):
                    print("✅ MessagingManager: Successfully got/created conversation: \(conversation.id)")
                    
                    // Add to conversations if not already present
                    if let existingIndex = self?.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        print("🔍 MessagingManager: Updating existing conversation in list")
                        self?.conversations[existingIndex] = conversation
                    } else {
                        print("🔍 MessagingManager: Adding new conversation to list")
                        self?.conversations.insert(conversation, at: 0)
                    }
                    
                    // Update cache to include the new/updated conversation
                    self?.conversationsCache = self?.conversations
                    self?.conversationsCacheTime = Date()
                    
                    completion(.success(conversation))
                case .failure(let error):
                    print("❌ MessagingManager: Failed to create/get conversation: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }
    
}