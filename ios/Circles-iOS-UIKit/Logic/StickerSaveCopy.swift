import Foundation

/// What a store's window sticker says when it offers to save the store, and
/// after (2026-11-16: it goes in a named list, no picker first). Pure.
enum StickerSaveCopy {

    /// The offer: "Build your map! Save Sal's to your map — it goes in your
    /// Favorite Local Spots list, and you can move it any time."
    static func offer(storeName: String, listName: String?, bonus: Int = 0) -> String {
        let earn = bonus > 0 ? " and earn \(bonus) more points here" : ""
        guard let listName else {
            return "Build your map! Save \(storeName) to one of your circles (your lists of places)\(earn)."
        }
        return "Build your map! Save \(storeName) to your map\(earn) — it goes in your \(listName) list, and you can move it any time."
    }

    /// After the save: "Saved to Favorite Local Spots." / "Place saved to your circle!"
    static func saved(listName: String?) -> String {
        listName.map { "Saved to \($0)." } ?? "Place saved to your circle!"
    }

    /// The alert's extra action, when a place was just saved somewhere movable
    static let moveButton = "Move to another list"

    /// The picker's title when there is nowhere to save without asking
    static func pickerTitle(storeName: String) -> String {
        "Pick a circle (a list) for \(storeName)"
    }
}
