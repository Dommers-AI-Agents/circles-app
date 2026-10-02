import Testing
import Foundation
@testable import Circles_iOS

/// The rows of a moment's action-sheet audience picker: tiers, with Inner
/// Circle expanded into one row per named list.
struct MomentAudienceChoicesTests {

    private let family = InnerCircleNamedList(id: "fam", name: "Family", userIds: ["a", "b"], users: [])
    private let gym = InnerCircleNamedList(id: "gym", name: "Gym", userIds: ["c"], users: [])

    @Test func withoutListsInnerCircleIsOneRow() {
        let rows = MomentAudienceChoices.choices(lists: [], current: .followers, currentListId: nil)
        #expect(rows.map(\.visibility) == VideoVisibility.selectable)
        #expect(rows.allSatisfy { $0.listId == nil })
        #expect(rows.filter(\.isSelected).map(\.visibility) == [.followers])
    }

    @Test func innerCircleBecomesOneRowPerList() {
        let rows = MomentAudienceChoices.choices(lists: [family, gym], current: .network, currentListId: nil)
        let inner = rows.filter { $0.visibility == .innerCircle }
        #expect(inner.map(\.title) == ["Family", "Gym"])
        #expect(inner.map(\.listId) == ["fam", "gym"])
        #expect(inner.map(\.subtitle) == ["Inner Circle · 2 people", "Inner Circle · 1 person"])
        // No vague "anyone on my lists" row unless the moment already says that.
        #expect(!rows.contains { $0.title == "Anyone on my lists" })
    }

    @Test func theStoredListIsTheSelectedRow() {
        let rows = MomentAudienceChoices.choices(lists: [family, gym], current: .innerCircle, currentListId: "gym")
        #expect(rows.filter(\.isSelected).map(\.listId) == ["gym"])
        #expect(!rows.contains { $0.title == "Anyone on my lists" })
    }

    @Test func anyoneOnMyListsIsNeverOffered() {
        // Wes, 2026-10-02: it defeats the point of lists — only named lists
        for listId in [nil, "deleted"] as [String?] {
            let rows = MomentAudienceChoices.choices(lists: [family], current: .innerCircle, currentListId: listId)
            #expect(!rows.contains { $0.title == "Anyone on my lists" || $0.title == "A list you've since emptied" })
            #expect(rows.filter { $0.visibility == .innerCircle }.map(\.listId) == [family.id])
            #expect(rows.filter(\.isSelected).isEmpty)
        }
    }
}
