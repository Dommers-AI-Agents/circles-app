import Foundation

/// The map's people dropdown, ranked by the map you're looking at (Wes,
/// 2026-11-07): people with places in the current view come first, most
/// places first; everyone else keeps the home row's order below them.
/// Counts come from places already loaded on the phone, with no extra fetch.
enum MapPeopleInView {
    /// How many places each person has in view, keyed by normalized user id.
    /// A place is counted once even if it was loaded twice.
    static func counts(_ places: [Place],
                       author: (Place) -> String?,
                       isInView: (Place) -> Bool) -> [String: Int] {
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for place in places where seen.insert(place.id).inserted && isInView(place) {
            guard let who = IDNormalizer.normalize(author(place)) else { continue }
            counts[who, default: 0] += 1
        }
        return counts
    }

    /// People with places in view first, most first; ties and everyone with
    /// none keep their incoming order.
    static func ordered<Person>(_ people: [Person], id: (Person) -> String, counts: [String: Int]) -> [Person] {
        people.enumerated()
            .map { (offset: $0.offset, person: $0.element, count: count(for: id($0.element), in: counts)) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.offset < $1.offset }
            .map { $0.person }
    }

    static func count(for personId: String, in counts: [String: Int]) -> Int {
        IDNormalizer.normalize(personId).flatMap { counts[$0] } ?? 0
    }

    /// The row's subtitle: "12 places here", or nil with none in view.
    static func subtitle(count: Int) -> String? {
        switch count {
        case 0: return nil
        case 1: return "1 place here"
        default: return "\(count) places here"
        }
    }
}
