import Foundation

/// A store's new post, as a card for Instagram (Wes, 2026-11-09: owners pay
/// Later/Hootsuite to post the same special twice). Pure — no UIKit.
enum StorePost: Equatable {
    case offer(title: String, pointsCost: Int)
    case announcement(title: String, message: String, eventStart: Date?)
}

enum StorePostCopy {
    /// The big line on the card
    static func headline(_ post: StorePost) -> String {
        switch post {
        case .offer(let title, _): return title
        case .announcement(let title, _, _): return title
        }
    }

    /// The line under it: what the points buy, the event's day, or the message
    static func detail(_ post: StorePost, storeName: String, calendar: Calendar = .current) -> String {
        switch post {
        case .offer(_, let pointsCost):
            return "\(pointsCost) points at \(storeName) in FavCircles"
        case .announcement(_, let message, let eventStart):
            if let eventStart {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "EEEE, MMM d · h:mm a"
                return formatter.string(from: eventStart)
            }
            return message
        }
    }

    /// The last line: an offer is earned; news and events are followed
    static func footer(_ post: StorePost) -> String {
        switch post {
        case .offer: return "Earn it with FavCircles · favcircles.com"
        case .announcement: return "Follow us on FavCircles · favcircles.com"
        }
    }

    // The sheet after a new post is saved
    static func sheetTitle(_ post: StorePost) -> String {
        switch post {
        case .offer: return "Offer posted"
        case .announcement(_, _, let eventStart): return eventStart == nil ? "Announcement posted" : "Event posted"
        }
    }
    static func sheetMessage(alertedLine: String?) -> String {
        (alertedLine ?? "It's on your place page and in the Locals tab.") + " Share it on Instagram too?"
    }
    static let shareStory = "Share to Instagram story"
    static let sharePost = "Share as a post"
    static let notNow = "Not now"
    static let instagramMissing = "Instagram isn't installed on this phone. The post image is in the share sheet instead."
}
