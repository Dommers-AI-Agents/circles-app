import Foundation

class ConversationService {
    static let shared = ConversationService()
    
    private init() {}
    
    // Get count of unread messages
    func getUnreadMessageCount(completion: @escaping (Int) -> Void) {
        // Use MessagingService to get unread count
        MessagingService.shared.getUnreadCount { result in
            switch result {
            case .success(let response):
                completion(response.totalUnread)
            case .failure:
                completion(0)
            }
        }
    }
}