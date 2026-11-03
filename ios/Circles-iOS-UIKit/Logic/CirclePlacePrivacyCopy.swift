import Foundation

/// What the app says after a circle's privacy changes, when some of the
/// owner's places in it set their own (Wes, 2026-11-03: a place's privacy
/// always wins, so ask whether to bring them along). Pure, tested.
enum CirclePlacePrivacyCopy {
    static func title(count: Int, tierTitle: String) -> String {
        count == 1 ? "Make the 1 place \(tierTitle) too?" : "Make all \(count) places \(tierTitle) too?"
    }

    static func message(count: Int) -> String {
        let places = count == 1 ? "1 place in this circle has" : "\(count) places in this circle have"
        return "\(places) its own privacy, which wins over the circle's. Match them to the circle, or keep their own settings."
            .replacingOccurrences(of: "have its own", with: "have their own")
    }

    static func confirm(tierTitle: String) -> String { "Make them \(tierTitle)" }
    static let keep = "Keep their own"
}
