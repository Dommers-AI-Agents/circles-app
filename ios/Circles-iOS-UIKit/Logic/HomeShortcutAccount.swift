import Foundation

/// Home Screen shortcuts and the Home tab's pinned widgets, kept on the
/// account (2026-11-01) so a reinstall or a new phone comes back with them.
/// Pure: what's saved, and what to do on the first launch of an install.
enum HomeShortcutAccount {

    static let documentId = "app_shortcuts"

    struct Document: Codable, Equatable {
        /// The app-icon menu's choices (nil = never chosen: the defaults)
        var selection: [String]?
        var pins: [HomeButtonPin]
    }

    enum FirstLaunch: Equatable {
        /// The account has choices: use them on this phone
        case adopt(Document)
        /// The account has none yet but this phone does: send them up
        case upload
        case nothing
    }

    static func firstLaunch(account: Document?, phone: Document) -> FirstLaunch {
        if let account { return account == phone ? .nothing : .adopt(account) }
        return (phone.selection != nil || !phone.pins.isEmpty) ? .upload : .nothing
    }
}
