import Foundation

/// What the home tour tells the server about each bubble (Wes, 2026-11-12:
/// a new user's first night left no trace beyond "tutorial not completed";
/// now every showing and every button is one event, so we can see where a
/// person stops). Same shape as the next-step chip events the server
/// already takes (POST /api/next-steps/events); `tourLast` on the server is
/// the one field that answers "where did they bail".
enum TourTelemetry {
    enum Action: String {
        case shown, next, back, skip, video, done
        case learnMore = "learn_more"
        case keepGoing = "keep_going"
    }

    static let surface = "home_tour"
    /// The step id of the "That's the basics — keep going?" card
    static let keepGoingStep = "tour_keep_going"

    /// One event, as the server reads it
    static func event(step: String, action: Action) -> [String: String] {
        ["step": step, "surface": surface, "kind": action.rawValue]
    }
}
