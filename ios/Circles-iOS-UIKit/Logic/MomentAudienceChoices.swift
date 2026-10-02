import Foundation

/// One row of a moment's "Who can see this?" sheet: a tier, or — for Inner
/// Circle — one named list.
struct MomentAudienceChoice: Equatable {
    let visibility: VideoVisibility
    /// The named Inner Circle list, when this row is one. Nil for every other tier.
    let listId: String?
    let title: String
    let subtitle: String
    let isSelected: Bool
}

/// The rows the action-sheet pickers offer (the moment owner menu's "Change
/// Privacy" and the link flow in the composer), so they name the same lists
/// the form picker (`PrivacyPickerButton`) does.
enum MomentAudienceChoices {

    /// - Parameters:
    ///   - lists: the named lists worth offering (`InnerCircleManager.usableLists`).
    ///   - current: what the moment says now, marked selected.
    static func choices(lists: [InnerCircleNamedList],
                        current: VideoVisibility,
                        currentListId: String?) -> [MomentAudienceChoice] {
        VideoVisibility.selectable.flatMap { level -> [MomentAudienceChoice] in
            guard level == .innerCircle, !lists.isEmpty else {
                return [MomentAudienceChoice(visibility: level, listId: nil,
                                             title: level.displayLabel,
                                             subtitle: level.pickerSubtitle,
                                             isSelected: current == level && (level != .innerCircle || currentListId == nil))]
            }
            // Only the lists themselves, never "anyone on my lists" (Wes,
            // 2026-10-02). A moment on no known list just has no row checked.
            return lists.map { list in
                MomentAudienceChoice(visibility: level, listId: list.id,
                                     title: list.name,
                                     subtitle: list.userIds.count == 1 ? "Inner Circle · 1 person" : "Inner Circle · \(list.userIds.count) people",
                                     isSelected: current == level && currentListId == list.id)
            }
        }
    }
}
