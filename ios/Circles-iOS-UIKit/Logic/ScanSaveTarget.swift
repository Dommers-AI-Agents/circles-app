import Foundation

/// Where a scanned place goes, without asking first (Wes, 2026-11-16: Jason
/// scanned the Windmill QR to save it and the first thing he saw was "pick a
/// circle"). The App Clip's rule, now the app's too: a place someone showed
/// you goes to Want to Try; a store you're standing in goes to Favorite Local
/// Spots. Shown, never silent: the sheet says where, and the done alert
/// offers "Move to another list". Never the last-used circle (the 2026-10-27
/// "moved places" lesson). Pure.
enum ScanSaveTarget {
    enum Kind {
        /// A place QR (/q/<code>): a friend or a store showing you a place
        case placeQR
        /// A store's window sticker (/s/<code>): you're at the store
        case storeSticker
    }

    /// The circle the save lands in, or nil only when there are no circles at all
    static func pick<C: SystemCircleFlagged>(_ kind: Kind, from circles: [C]) -> C? {
        let order: [SystemCircleKind] = kind == .placeQR ? [.wantToTry, .favoriteLocal] : [.favoriteLocal, .wantToTry]
        for starter in order {
            if let circle = SystemCircles.first(starter, in: circles) { return circle }
        }
        return circles.first
    }
}
