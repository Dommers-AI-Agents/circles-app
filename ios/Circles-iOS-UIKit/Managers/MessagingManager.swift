import Foundation
import Combine

class MessagingManager: ObservableObject {
    static let shared = MessagingManager()
    
    @Published var conversations: [Conversation] = []
    @Published var activeMessages: [String: [Message]] = [:] // conversationId: messages
    @Published var unreadCount: Int = 0
    @Published var isLoadingConversations = false
    @Published var isLoadingMessages = false
    @Published var error: String?
    
    private let messagingService = MessagingService.shared
    private var cancellables = Set<AnyCancellable>()
    private var messagePollingTimer: Timer?
    
    private init() {
        setupSubscribers()
    }
    
    private func setupSubscribers() {
        // Listen for authentication changes
        AuthManager.shared.$isAuthenticated
            .sink { [weak self] isAuthenticated in
                if isAuthenticated {
                    self?.startMessaging()
                } else {
                    self?.stopMessaging()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Messaging Lifecycle
    
    private func startMessaging() {
        // Temporarily disable messaging features until backend is deployed
        // loadConversations()
        // startMessagePolling()
        // updateUnreadCount()
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
    
    // MARK: - Polling (temporary until real-time is implemented)
    
    private func startMessagePolling() {
        // Poll for new messages every 5 seconds
        messagePollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
            loadMessages(for: conversationId, showLoading: false)
        }
    }
    
    // MARK: - Conversations
    
    func loadConversations() {
        isLoadingConversations = true
        
        messagingService.fetchConversations { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingConversations = false
                
                switch result {
                case .success(let conversations):
                    self?.conversations = conversations.sorted { conv1, conv2 in
                        // Sort by last message time, most recent first
                        let time1 = conv1.lastMessageTime ?? conv1.createdAt
                        let time2 = conv2.lastMessageTime ?? conv2.createdAt
                        return time1 > time2
                    }
                case .failure(let error):
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
                    self?.unreadCount = response.totalUnread
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
}