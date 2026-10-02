import Foundation

/// Your check-in numbers, as GET /check-ins/me/summary returns them.
struct CheckInSummary: Decodable, Equatable {
    struct Friend: Decodable, Equatable {
        let userId: String
        let displayName: String
        let profilePicture: String?
        let placeName: String?
    }
    let total: Int
    let thisMonth: Int
    let places: Int
    let weekStreak: Int
    let checkedInThisWeek: Bool
    let lastPlaceName: String?
    let friendsOut: [Friend]
}

/// Words for the top of the Check In screen: why check in, right now.
enum CheckInHeaderCopy {

    static func headline(_ s: CheckInSummary?) -> String {
        guard let s else { return "Where are you right now?" }
        if s.total == 0 { return "Your first check-in 📍" }
        if s.weekStreak > 0 && !s.checkedInThisWeek {
            return "Keep your \(s.weekStreak)-week streak alive 🔥"
        }
        if s.weekStreak >= 2 { return "\(s.weekStreak) weeks in a row 🔥" }
        return "Where are you right now?"
    }

    /// The reason, every time: your people hear, you earn
    static func reason(_ s: CheckInSummary?) -> String {
        if let s, s.total == 0 {
            return "Let your people know where you are, start your map of everywhere you've been, and earn ½ FavCoin 🌵."
        }
        return "Let your people know where you are and earn ½ FavCoin 🌵 for each place, once a day."
    }

    /// "Brittany is out at Muraya" / "Brittany and 2 others are out right now"
    static func friendsLine(_ friends: [CheckInSummary.Friend]) -> String? {
        guard let first = friends.first else { return nil }
        let name = first.displayName.split(separator: " ").first.map(String.init) ?? first.displayName
        if friends.count == 1 {
            if let place = first.placeName, !place.isEmpty { return "\(name) is out at \(place)" }
            return "\(name) is out right now"
        }
        let others = friends.count - 1
        return "\(name) and \(others) other\(others == 1 ? "" : "s") are out right now"
    }

    /// The three tiles (value, caption); none before the first check-in
    static func tiles(_ s: CheckInSummary?) -> [(value: String, caption: String)] {
        guard let s, s.total > 0 else { return [] }
        return [
            ("🔥 \(s.weekStreak)", "week streak"),
            ("\(s.total)", s.total == 1 ? "check-in" : "check-ins"),
            ("\(s.places)", s.places == 1 ? "place" : "places")
        ]
    }
}
