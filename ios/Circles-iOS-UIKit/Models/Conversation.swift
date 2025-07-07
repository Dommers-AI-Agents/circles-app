import Foundation

// MARK: - Conversation Model
struct Conversation: Codable, Identifiable {
    let id: String
    let type: ConversationType
    let participants: [String]
    let name: String?
    let avatar: String?
    var lastMessage: String?
    var lastMessageTime: String?
    var lastMessageSenderId: String?
    var unreadCounts: [String: Int]?
    let createdAt: String
    let updatedAt: String
    let createdBy: String?
    
    // Populated participant details (not from database)
    var participantDetails: [User]?
    
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case participants
        case name
        case avatar
        case lastMessage
        case lastMessageTime
        case lastMessageSenderId
        case unreadCounts
        case createdAt
        case updatedAt
        case createdBy
        case participantDetails
    }
    
    // Computed properties
    var displayName: String {
        switch type {
        case .direct:
            // For direct conversations, show the other participant's name
            if let otherParticipant = participantDetails?.first {
                return otherParticipant.displayName
            }
            return "Unknown User"
        case .group:
            // For group conversations, use the conversation name
            return name ?? "Group Chat"
        case .system:
            // For system conversations (connection requests)
            return "Connection Request"
        }
    }
    
    var displayAvatar: String? {
        switch type {
        case .direct:
            // For direct conversations, show the other participant's avatar
            return participantDetails?.first?.profilePicture
        case .group:
            // For group conversations, use the conversation avatar
            return avatar
        case .system:
            // For system conversations, no avatar
            return nil
        }
    }
    
    var unreadCount: Int {
        guard let currentUserId = AuthService.shared.getUserId() else { return 0 }
        return unreadCounts?[currentUserId] ?? 0
    }
    
    var hasUnreadMessages: Bool {
        return unreadCount > 0
    }
    
    var formattedLastMessageTime: String? {
        guard let lastMessageTime = lastMessageTime else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: lastMessageTime) {
            return DateFormatter.conversationTime(from: date)
        }
        
        return nil
    }
}

// MARK: - Conversation Type
enum ConversationType: String, Codable {
    case direct = "direct"
    case group = "group"
    case system = "system"
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static func conversationTime(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}