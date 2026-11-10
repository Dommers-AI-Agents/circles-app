import Foundation

/// The generic "Join FavCircles" sticker code (coasters, flyers, the App Clip
/// card). It is not a store: scanning it takes the person into FavCircles —
/// the first run or Add Place — with no rewards wording and no store page
/// (Wes, 2026-11-09: "the FavCircles virtual store is just a demo"). The
/// server answers the same code with kind 'generic'; this lets the app know
/// before asking, so no "Checking rewards…" ever shows for it.
enum GenericJoinCode {
    static let code = "JOINUS"

    static func matches(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.code
    }
}
