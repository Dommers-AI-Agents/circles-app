import Foundation

class MessagingService {
    static let shared = MessagingService()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - Helper Methods
    
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Conversations
    
    func fetchConversations(completion: @escaping (Result<[Conversation], Error>) -> Void) {
        // print("🔍 MessagingService: fetchConversations called")
        // print("🔐 MessagingService: Auth token available: \(AuthService.shared.getToken() != nil)")
        // print("🔐 MessagingService: Auth token value: \(AuthService.shared.getToken()?.prefix(20) ?? "nil")...")
        // print("🔍 MessagingService: Making API request to messages/conversations")
        
        apiService.request(
            endpoint: "messages/conversations",
            method: .get,
            requiresAuth: true
        ) { (result: Result<ConversationsResponse, APIError>) in
            switch result {
            case .success(let response):
                // print("✅ MessagingService: Successfully fetched \(response.conversations.count) conversations")
                // print("🔍 MessagingService: Response: \(response)")
                completion(.success(response.conversations))
            case .failure(let error):
                // print("❌ MessagingService: Failed to fetch conversations: \(error.localizedDescription)")
                // print("❌ MessagingService: Error details: \(error)")
                // print("❌ MessagingService: Error type: \(type(of: error))")
                if case let APIError.httpError(statusCode, data) = error {
                    // print("❌ MessagingService: HTTP error - Status: \(statusCode)")
                    if let data = data, let message = String(data: data, encoding: .utf8) {
                        // print("❌ MessagingService: Error message: \(message)")
                    }
                } else if case APIError.noInternet = error {
                    // print("❌ MessagingService: No internet connection")
                } else if case APIError.unauthorized = error {
                    // print("❌ MessagingService: Unauthorized - auth token may be invalid")
                } else if case APIError.serverError = error {
                    // print("❌ MessagingService: Server error")
                }
                completion(.failure(error))
            }
        }
    }
    
    func createConversation(
        type: ConversationType,
        participants: [String],
        name: String? = nil,
        avatar: String? = nil,
        completion: @escaping (Result<Conversation, Error>) -> Void
    ) {
        var body: [String: Any] = [
            "type": type.rawValue,
            "participants": participants
        ]
        
        if let name = name {
            body["name"] = name
        }
        
        if let avatar = avatar {
            body["avatar"] = avatar
        }
        
        apiService.request(
            endpoint: "messages/conversations",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<ConversationResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.conversation))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Messages
    
    func fetchMessages(
        conversationId: String,
        limit: Int = 50,
        before: String? = nil,
        completion: @escaping (Result<[Message], Error>) -> Void
    ) {
        print("🔍 MessagingService: fetchMessages called")
        print("🔍 MessagingService: conversationId: \(conversationId)")
        print("🔍 MessagingService: limit: \(limit), before: \(before ?? "nil")")
        
        var endpoint = "messages/conversations/\(conversationId)/messages?limit=\(limit)"
        if let before = before {
            endpoint += "&before=\(before)"
        }
        
        print("🔍 MessagingService: Making API request to endpoint: \(endpoint)")
        print("🔐 MessagingService: Auth token available: \(AuthService.shared.getToken() != nil)")
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { (result: Result<MessagesResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ MessagingService: Successfully fetched \(response.messages.count) messages")
                for (index, message) in response.messages.prefix(3).enumerated() {
                    print("   Message \(index): \(message.type.rawValue) - \(message.displayContent)")
                }
                completion(.success(response.messages))
            case .failure(let error):
                print("❌ MessagingService: Failed to fetch messages: \(error.localizedDescription)")
                if case let APIError.httpError(statusCode, data) = error {
                    print("❌ MessagingService: HTTP error - Status: \(statusCode)")
                    if let data = data, let message = String(data: data, encoding: .utf8) {
                        print("❌ MessagingService: Error response: \(message)")
                    }
                }
                completion(.failure(error))
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
        var body: [String: Any] = ["type": type.rawValue]
        
        if let content = content {
            body["content"] = content
        }
        
        if let mediaUrl = mediaUrl {
            body["mediaUrl"] = mediaUrl
        }
        
        if let metadata = metadata {
            body["metadata"] = metadata
        }
        
        apiService.request(
            endpoint: "messages/conversations/\(conversationId)/messages",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<MessageResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.message))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func editMessage(
        messageId: String,
        content: String,
        completion: @escaping (Result<Message, Error>) -> Void
    ) {
        let body: [String: Any] = ["content": content]
        
        apiService.request(
            endpoint: "messages/\(messageId)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<MessageResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.message))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteMessage(
        messageId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        apiService.request(
            endpoint: "messages/\(messageId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func markMessagesAsRead(
        conversationId: String,
        messageIds: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let body: [String: Any] = ["messageIds": messageIds]
        
        apiService.request(
            endpoint: "messages/conversations/\(conversationId)/read",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getUnreadCount(completion: @escaping (Result<UnreadCountResponse, Error>) -> Void) {
        apiService.request(
            endpoint: "messages/unread-count",
            method: .get,
            requiresAuth: true
        ) { (result: Result<UnreadCountResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteConversation(
        conversationId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        apiService.request(
            endpoint: "messages/conversations/\(conversationId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func getOrCreateDirectConversation(
        with userId: String,
        completion: @escaping (Result<Conversation, Error>) -> Void
    ) {
        // Normalize the user ID before sending to backend
        let normalizedUserId = IDNormalizer.normalize(userId) ?? userId
        
        print("🔍 MessagingService: getOrCreateDirectConversation called")
        print("🔍 MessagingService: Original userId: \(userId)")
        print("🔍 MessagingService: Normalized userId: \(normalizedUserId)")
        print("🔍 MessagingService: Making POST request to: messages/conversations/direct/\(normalizedUserId)")
        
        apiService.request(
            endpoint: "messages/conversations/direct/\(normalizedUserId)",
            method: .post,
            requiresAuth: true
        ) { (result: Result<ConversationResponse, APIError>) in
            print("🔍 MessagingService: Received response from API")
            
            switch result {
            case .success(let response):
                print("✅ MessagingService: Successfully got/created conversation with ID: \(response.conversation.id)")
                completion(.success(response.conversation))
            case .failure(let error):
                print("❌ MessagingService: Failed to get/create conversation: \(error)")
                
                // Log more details about the error
                if case APIError.httpError(let statusCode, let data) = error {
                    print("❌ MessagingService: HTTP Error - Status Code: \(statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("❌ MessagingService: Error Details: \(errorString)")
                    }
                }
                
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Response Models

struct ConversationsResponse: Codable {
    let success: Bool
    let conversations: [Conversation]
}

struct ConversationResponse: Codable {
    let success: Bool
    let conversation: Conversation
}

struct MessagesResponse: Codable {
    let success: Bool
    let messages: [Message]
}

struct MessageResponse: Codable {
    let success: Bool
    let message: Message
}

struct UnreadCountResponse: Codable {
    let success: Bool
    let totalUnread: Int
    let unreadByConversation: [String: Int]
}