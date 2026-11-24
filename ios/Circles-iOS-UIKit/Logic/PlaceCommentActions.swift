import Foundation

/// What someone may do with a comment on a place (Wes, 2026-11-24: "Is there
/// a way to delete or modify your comments of a place?"). The server decides
/// (`services/placeCommentRules.js`); this is the same rule, so the app only
/// offers what will be accepted.
///
/// Comments belong to the venue, and everyone who saved it has their own save.
/// So "the place's owner" means the save the comment was written on: saving
/// the same venue gives no say over what other people wrote.
enum PlaceCommentAction: Equatable {
    case edit, delete

    var title: String { self == .edit ? "Edit" : "Delete" }
}

enum PlaceCommentActions {
    /// - Parameters:
    ///   - authorId: who wrote the comment
    ///   - commentPlaceId: the save it was written on
    ///   - placeId: the save being looked at
    ///   - placeOwnerId: who added that save
    ///   - me: the signed-in person
    static func allowed(authorId: String, commentPlaceId: String, placeId: String, placeOwnerId: String, me: String?) -> [PlaceCommentAction] {
        guard let me, !me.isEmpty else { return [] }
        if authorId == me { return [.edit, .delete] }
        if placeOwnerId == me && !placeId.isEmpty && commentPlaceId == placeId { return [.delete] }
        return []
    }

    /// New words worth sending: trimmed, not empty, and not what it already says
    static func newText(from typed: String?, current: String) -> String? {
        let text = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != current.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return text
    }

    /// The line under the name: when it was written, and that it was changed
    static func timeLine(relative: String, edited: Bool) -> String {
        edited ? "\(relative) · edited" : relative
    }
}

extension PlaceComment {
    /// What the signed-in person may do with this comment on `place`
    func allowedActions(on place: Place, me: String? = AuthService.shared.getUserId()) -> [PlaceCommentAction] {
        PlaceCommentActions.allowed(authorId: userId, commentPlaceId: placeId, placeId: place.id, placeOwnerId: place.addedBy, me: me)
    }

    /// "1h ago", or "1h ago · edited"
    var timeLine: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return PlaceCommentActions.timeLine(relative: formatter.localizedString(for: createdAt, relativeTo: Date()), edited: editedAt != nil)
    }
}
