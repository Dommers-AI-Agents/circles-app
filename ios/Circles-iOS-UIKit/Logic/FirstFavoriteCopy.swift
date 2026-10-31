import Foundation

/// Words for the personal first run (Wes, 2026-10-31): a new user's first
/// step is saving the one place near them they love most, and what follows
/// (people, rewards, the photo offer, the Home card) is about that place.
/// Pure so the wording is tested.
enum FirstFavoriteCopy {
    static let headline = "What's the one place near you that you love most?"
    static let subheadline = "Your coffee shop, the restaurant you keep going back to, the park you walk in. It starts your map."
    static let searchPlaceholder = "Search a place you love…"

    /// Quick picks: the chip's label and what it searches for nearby.
    struct Chip: Equatable {
        let title: String
        let query: String
    }

    static let chips: [Chip] = [
        Chip(title: "☕️ Coffee", query: "Coffee"),
        Chip(title: "🍽️ Restaurant", query: "Restaurant"),
        Chip(title: "🍸 Bar", query: "Bar"),
        Chip(title: "🥐 Bakery", query: "Bakery"),
        Chip(title: "🥞 Brunch", query: "Brunch"),
        Chip(title: "🌳 Park", query: "Park"),
        Chip(title: "💪 Gym", query: "Gym")
    ]

    static func confirmTitle(placeName: String) -> String {
        "Save \(placeName) as your first favorite?"
    }

    static func savedTitle(placeName: String) -> String {
        "\(placeName) is on your map 🎉"
    }

    /// "1 person also loves X" / "3 people also love X"; nil for nobody.
    static func saversLine(count: Int, placeName: String) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 person also loves \(placeName)" : "\(count) people also love \(placeName)"
    }

    /// Header for the fallback list when nobody else has the place yet.
    static func fallbackPeopleHeader(cityName: String?) -> String {
        if let city = cityName?.trimmingCharacters(in: .whitespaces), !city.isEmpty {
            return "People mapping \(city)"
        }
        return "Maps worth exploring"
    }

    /// Said only when the store's rewards are live for this person; stores
    /// not on the program are never mentioned (rule 2026-10-30).
    static func rewardsLine(placeName: String, rewardsLive: Bool, isOwner: Bool) -> String? {
        guard rewardsLive, !isOwner else { return nil }
        return "\(placeName) has FavCircles Rewards. Scan the QR code at the register when you visit."
    }

    static func photoMapHeadline(placeName: String?) -> String {
        guard let name = placeName, !name.isEmpty else { return "Fill your map from your photos" }
        return "Add more places like \(name)"
    }

    static func photoMapSubheadline(placeName: String?) -> String {
        guard let name = placeName, !name.isEmpty else {
            return "The places you've already been are in your camera roll. We'll put them on your map."
        }
        return "Straight from your photos. The places you've been near \(name) and beyond are already in your camera roll."
    }

    /// The Home card once they have places of their own but fewer than the
    /// quick-start goal; nil means the generic "Start your map" card.
    static func homeCard(firstPlaceName: String?, ownPlaceCount: Int, goal: Int) -> (title: String, body: String)? {
        guard let name = firstPlaceName, !name.isEmpty, ownPlaceCount >= 1, ownPlaceCount < goal else { return nil }
        let remaining = goal - ownPlaceCount
        let more = remaining == 1 ? "one more place" : "\(remaining == 2 ? "two" : String(remaining)) more places"
        return ("Keep building your map 🗺️", "You saved \(name). Add \(more) you love.")
    }
}
