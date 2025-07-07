import Foundation

// MARK: - Message Model
struct Message: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    var content: String?
    let mediaUrl: String?
    let metadata: [String: Any]?
    let readBy: [String]
    let deliveredTo: [String]?
    var editedAt: String?
    var deletedAt: String?
    let createdAt: String
    
    // Populated sender details (not from database)
    var senderDetails: User?
    
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case conversationId
        case senderId
        case type
        case content
        case mediaUrl
        case metadata
        case readBy
        case deliveredTo
        case editedAt
        case deletedAt
        case createdAt
        case senderDetails
    }
    
    // Custom encoding/decoding to handle metadata as [String: Any]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        senderId = try container.decode(String.self, forKey: .senderId)
        type = try container.decode(MessageType.self, forKey: .type)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        readBy = try container.decode([String].self, forKey: .readBy)
        deliveredTo = try container.decodeIfPresent([String].self, forKey: .deliveredTo)
        editedAt = try container.decodeIfPresent(String.self, forKey: .editedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        senderDetails = try container.decodeIfPresent(User.self, forKey: .senderDetails)
        
        // Decode metadata as dictionary
        if let metadataData = try? container.decode(Data.self, forKey: .metadata),
           let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
            metadata = metadataDict
        } else {
            metadata = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encode(readBy, forKey: .readBy)
        try container.encodeIfPresent(deliveredTo, forKey: .deliveredTo)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(senderDetails, forKey: .senderDetails)
        
        // Encode metadata as data
        if let metadata = metadata,
           let metadataData = try? JSONSerialization.data(withJSONObject: metadata) {
            try container.encode(metadataData, forKey: .metadata)
        }
    }
    
    // Computed properties
    var isCurrentUserMessage: Bool {
        return senderId == AuthService.shared.getUserId()
    }
    
    var isRead: Bool {
        guard let currentUserId = AuthService.shared.getUserId() else { return false }
        return readBy.contains(currentUserId) || isCurrentUserMessage
    }
    
    var isEdited: Bool {
        return editedAt != nil
    }
    
    var isDeleted: Bool {
        return deletedAt != nil
    }
    
    var displayContent: String {
        if isDeleted {
            return "[Message deleted]"
        }
        
        switch type {
        case .text:
            return content ?? ""
        case .image:
            return "📷 Photo"
        case .location:
            return "📍 Location"
        case .circleShare:
            return "🔵 Shared a circle"
        case .placeShare:
            return "📍 Shared a place"
        case .connectionRequest:
            return "🤝 Connection request"
        }
    }
    
    var formattedTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: createdAt) {
            return DateFormatter.messageTime(from: date)
        }
        
        return ""
    }
}

// MARK: - Message Type
enum MessageType: String, Codable {
    case text = "text"
    case image = "image"
    case location = "location"
    case circleShare = "circle_share"
    case placeShare = "place_share"
    case connectionRequest = "connection_request"
}

// MARK: - Date Formatter Extension
extension DateFormatter {
    static func messageTime(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "Yesterday h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message Request Models
struct SendMessageRequest: Encodable {
    let type: MessageType
    let content: String?
    let mediaUrl: String?
    let metadata: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case mediaUrl
        case metadata
    }
    
    init(type: MessageType, content: String? = nil, mediaUrl: String? = nil, metadata: [String: Any]? = nil) {
        self.type = type
        self.content = content
        self.mediaUrl = mediaUrl
        self.metadata = metadata
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        
        if let metadata = metadata {
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            try container.encode(metadataData, forKey: .metadata)
        }
    }
}