import Foundation

class MessagingService {
    static let shared = MessagingService()
    private let apiService = APIService.shared
    
    private init() {}
    
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
        var endpoint = "messages/conversations/\(conversationId)/messages?limit=\(limit)"
        if let before = before {
            endpoint += "&before=\(before)"
        }
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { (result: Result<MessagesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.messages))
            case .failure(let error):
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
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
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
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
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
        apiService.request(
            endpoint: "messages/conversations/direct/\(userId)",
            method: .post,
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