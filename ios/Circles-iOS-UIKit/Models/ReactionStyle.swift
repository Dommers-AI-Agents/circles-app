import UIKit

// MARK: - LinkedIn-Style Reaction System
enum ReactionStyle: String, CaseIterable {
    case like = "👍"
    case love = "❤️"
    case celebrate = "🎉"
    case support = "💪"
    case insightful = "💡"
    case funny = "😆"
    
    // Display title for each reaction
    var title: String {
        switch self {
        case .like: return "Like"
        case .love: return "Love"
        case .celebrate: return "Celebrate"
        case .support: return "Support"
        case .insightful: return "Insightful"
        case .funny: return "Funny"
        }
    }
    
    // Background color for reaction pills (LinkedIn-style)
    var backgroundColor: UIColor {
        switch self {
        case .like:
            return UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // LinkedIn blue
        case .love:
            return UIColor(red: 0.957, green: 0.263, blue: 0.212, alpha: 1.0) // Red
        case .celebrate:
            return UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0) // Green
        case .support:
            return UIColor(red: 0.612, green: 0.153, blue: 0.69, alpha: 1.0) // Purple
        case .insightful:
            return UIColor(red: 1.0, green: 0.757, blue: 0.027, alpha: 1.0) // Yellow/Orange
        case .funny:
            return UIColor(red: 1.0, green: 0.596, blue: 0.0, alpha: 1.0) // Orange
        }
    }
    
    // Tint color for icons when selected
    var tintColor: UIColor {
        switch self {
        case .insightful, .funny:
            return .black // Dark text on light backgrounds
        default:
            return .white // White text on dark backgrounds
        }
    }
    
    // Initialize from emoji string
    init?(emoji: String) {
        guard let style = ReactionStyle.allCases.first(where: { $0.rawValue == emoji }) else {
            return nil
        }
        self = style
    }
}

// MARK: - Activity Reaction User Model
struct ActivityReactionUser: Codable {
    let id: String
    let displayName: String
    let profilePicture: String?
}

// MARK: - Reaction Summary Model
struct ReactionSummary: Codable {
    let emoji: String
    let count: Int
    let users: [ActivityReactionUser]? // Optional list of users who reacted
    
    var style: ReactionStyle? {
        return ReactionStyle(emoji: emoji)
    }
}

// MARK: - Reaction Pill View Configuration
struct ReactionPillConfiguration {
    let emoji: String
    let count: Int
    let isUserReaction: Bool
    
    var style: ReactionStyle? {
        return ReactionStyle(emoji: emoji)
    }
    
    var displayText: String {
        if count > 1 {
            return "\(emoji) \(count)"
        }
        return emoji
    }
}

// MARK: - Reaction Animation Settings
struct ReactionAnimationSettings {
    static let pickerAppearDuration: TimeInterval = 0.3
    static let pickerDismissDuration: TimeInterval = 0.2
    static let selectionScaleDuration: TimeInterval = 0.15
    static let selectionScale: CGFloat = 1.3
    static let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light
    static let selectionHapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium
}

// MARK: - Quick Comment Suggestions
enum QuickCommentSuggestion {
    case checkIn
    case placeAdded
    case circleCreated
    case general
    
    var suggestions: [String] {
        switch self {
        case .checkIn:
            return ["Looks fun!", "Enjoy!", "Great choice!", "Have a great time!"]
        case .placeAdded:
            return ["Love this place!", "Thanks for sharing!", "Added to my list!", "Great recommendation!"]
        case .circleCreated:
            return ["Following!", "Great collection!", "Can't wait to explore!", "Awesome circle!"]
        case .general:
            return ["Thanks for sharing!", "Love this!", "Great post!", "Interesting!"]
        }
    }
    
    static func suggestions(for activityType: ActivityType) -> [String] {
        switch activityType {
        case .checkIn:
            return QuickCommentSuggestion.checkIn.suggestions
        case .placeAdded, .placeLiked:
            return QuickCommentSuggestion.placeAdded.suggestions
        case .circleCreated:
            return QuickCommentSuggestion.circleCreated.suggestions
        default:
            return QuickCommentSuggestion.general.suggestions
        }
    }
}