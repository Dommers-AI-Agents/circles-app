import Foundation
import Testing
@testable import Circles_iOS

/// A tapped heart stays on the comment (2026-11-03: the screen reloaded the
/// old copy, so the heart never showed)
struct CommentLikeTests {
    private func comment(likes: [String], count: Int?) throws -> PlaceComment {
        let json = """
        {"_id": "c1", "placeId": "p1", "userId": "tommy", "text": "Awesome local bar",
         "likes": [\(likes.map { "\"\($0)\"" }.joined(separator: ", "))], "likesCount": \(count.map(String.init) ?? "null"), "createdAt": "2026-11-03T17:43:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaceComment.self, from: Data(json.utf8))
    }

    @Test func likingAddsMeAndTheServerCountWins() throws {
        // A fixed person, so the result never depends on who the test device is signed in as
        let me = "me-123"
        let start = try comment(likes: ["someone"], count: 1)
        let liked = start.withLike(true, me: me)
        #expect(liked.isLiked(by: me))
        #expect(liked.displayLikesCount == 2)
        #expect(start.withLike(true, count: 5, me: me).displayLikesCount == 5)
        let unliked = try comment(likes: ["someone", me], count: 2).withLike(false, me: me)
        #expect(!unliked.isLiked(by: me))
        #expect(unliked.displayLikesCount == 1)
        // Liking twice never counts twice
        #expect(liked.withLike(true, me: me).displayLikesCount == 2)
    }

    @Test func signedOutLeavesTheCommentAlone() throws {
        let start = try comment(likes: ["someone"], count: 1)
        #expect(start.withLike(true, me: nil).displayLikesCount == 1)
    }
}
