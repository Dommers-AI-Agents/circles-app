import Testing
import Foundation
@testable import Circles_iOS

/// Who may edit or delete a comment on a place: the same rule as the server's
/// `placeCommentRules.js`.
struct PlaceCommentActionsTests {
    private func allowed(author: String = "ann", writtenOn: String = "bobs-save", looking: String = "bobs-save",
                         owner: String = "bob", me: String?) -> [PlaceCommentAction] {
        PlaceCommentActions.allowed(authorId: author, commentPlaceId: writtenOn, placeId: looking, placeOwnerId: owner, me: me)
    }

    @Test func theAuthorEditsAndDeletesFromAnySaveOfTheVenue() {
        #expect(allowed(me: "ann") == [.edit, .delete])
        #expect(allowed(looking: "carols-save", owner: "carol", me: "ann") == [.edit, .delete])
    }

    @Test func theOwnerOfTheSaveItWasWrittenOnDeletesButNeverEdits() {
        #expect(allowed(me: "bob") == [.delete])
    }

    @Test func anotherSaverOfTheVenueHasNoSay() {
        #expect(allowed(looking: "carols-save", owner: "carol", me: "carol").isEmpty)
        #expect(allowed(me: "dave").isEmpty)
    }

    @Test func nobodySignedInSeesNothing() {
        #expect(allowed(me: nil).isEmpty)
        #expect(allowed(author: "", me: "").isEmpty)
        // A comment with no save recorded is nobody's to moderate
        #expect(allowed(writtenOn: "", looking: "", me: "bob").isEmpty)
    }

    @Test func newWordsAreTrimmedAndMustDiffer() {
        #expect(PlaceCommentActions.newText(from: "  Good coffee \n", current: "Good cofee") == "Good coffee")
        #expect(PlaceCommentActions.newText(from: "Good cofee ", current: "Good cofee") == nil)
        #expect(PlaceCommentActions.newText(from: "   ", current: "Good cofee") == nil)
        #expect(PlaceCommentActions.newText(from: nil, current: "Good cofee") == nil)
    }

    @Test func anEditedCommentSaysSo() {
        #expect(PlaceCommentActions.timeLine(relative: "1h ago", edited: false) == "1h ago")
        #expect(PlaceCommentActions.timeLine(relative: "1h ago", edited: true) == "1h ago · edited")
        #expect(PlaceCommentAction.edit.title == "Edit")
        #expect(PlaceCommentAction.delete.title == "Delete")
    }

    @Test func theSavedCopyKeepsWhatOnlyTheListKnew() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func comment(_ json: String) throws -> PlaceComment { try decoder.decode(PlaceComment.self, from: Data(json.utf8)) }
        let old = try comment(#"{"_id":"c1","placeId":"p1","userId":"ann","text":"Good cofee","createdAt":"2026-11-24T10:00:00Z","replyCount":2,"isVenueOwner":true}"#)
        let saved = try comment(#"{"_id":"c1","placeId":"p1","userId":"ann","text":"Good coffee","createdAt":"2026-11-24T10:00:00Z","editedAt":"2026-11-24T11:00:00Z"}"#)
        #expect(old.editedAt == nil)
        let merged = saved.keepingDetails(of: old)
        #expect(merged.text == "Good coffee")
        #expect(merged.editedAt != nil)
        #expect(merged.replyCount == 2)
        #expect(merged.isVenueOwner == true)
    }
}
