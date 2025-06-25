import Foundation

class MessagingService {
    static let shared = MessagingService()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - Conversations
    
    func fetchConversations(completion: @escaping (Result<[Conversation], Error>) -> Void) {
        apiService.request(
            endpoint: "messages/conversations",
            method: .get,
            requiresAuth: true
        ) { (result: Result<ConversationsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.conversations))
            case .failure(let error):
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
    
    // MARK: - Helper Methods
    
    func getOrCreateDirectConversation(
        with userId: String,
        completion: @escaping (Result<Conversation, Error>) -> Void
    ) {
        guard let currentUserId = AuthService.shared.getUserId() else {
            completion(.failure(NSError(domain: "MessagingService", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        // Create a direct conversation (backend will return existing if one exists)
        createConversation(
            type: .direct,
            participants: [currentUserId, userId],
            completion: completion
        )
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