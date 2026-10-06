import Foundation
import ActivityKit

// Shared by the app and the Circles-Widget extension: an event on the lock
// screen and Dynamic Island. The server keeps it current by push
// (backend eventLiveActivityService.contentState — keys must match).

@available(iOS 16.1, *)
struct EventActivityAttributes: ActivityAttributes {
    let eventId: String
    let name: String
    let emoji: String

    struct ContentState: Codable, Hashable {
        var members: Int
        var photos: Int
        var headline: String          // the newest thing ("📸 Sal added 3 photos")
        var rollCall: String?         // "Roll call: 5 of 8 here"
        var song: String?             // top unplayed request
        var challenges: String?       // "4 photo challenges"
        var ended: Bool
    }
}

enum EventLiveLinks {
    /// Opens the event in the Events widget.
    static func open(_ eventId: String) -> URL {
        URL(string: "https://api.favcircles.com/app/widget/events?event=\(eventId)")!
    }
}
