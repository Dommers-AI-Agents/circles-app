import Foundation

/// What one person may do to one photo in a place's library — the same
/// rules the server enforces (placePhotoService.permissionsFor), so the menu
/// never offers something that would be refused.
enum PlacePhotoActions {

    enum Action: Equatable {
        /// Owner/admin: move to the front
        case setCover
        /// Your own photo: gone for good
        case delete
        /// Owner/admin, someone else's photo: removed for everyone, stays gone
        case remove
        /// Someone else's photo: report it
        case report
    }

    static func actions(photo: AttributedPhoto, isCover: Bool, viewerId: String?, canManage: Bool) -> [Action] {
        let own = viewerId != nil && photo.uploadedBy == viewerId
        var out: [Action] = []
        if canManage && !isCover && photo.photoId != nil && photo.isPrivate != true { out.append(.setCover) }
        if photo.photoId != nil {
            if own { out.append(.delete) } else if canManage { out.append(.remove) }
        }
        if !own && photo.photoId != nil && photo.uploadedBy != nil { out.append(.report) }
        return out
    }

    /// The ids in their new order after moving the item at `from` to `to`.
    static func moved(_ ids: [String], from: Int, to: Int) -> [String] {
        guard ids.indices.contains(from), to >= 0, to < ids.count else { return ids }
        var out = ids
        let id = out.remove(at: from)
        out.insert(id, at: to)
        return out
    }

    /// Report ids take the form the server's moderation expects
    static func reportContentId(placeId: String, photoId: String) -> String { "\(placeId):\(photoId)" }
}
