import Foundation
import Testing
@testable import Circles_iOS

/// A tapped heart stays on the comment (2026-11-03: the screen reloaded the
/// old copy, so the heart never showed)
struct CommentLikeTests {
    private func comment(likes: [String], count: Int?) throws -> PlaceComment {
        let json = """
        {"_id": "c1", "placeId": "p1", "userId": "tommy", "text": "Awesome local bar",
         "likes": \(likes.map { "\"\($0)\"" }), "likesCount": \(count.map(String.init) ?? "null"), "createdAt": "2026-11-03T17:43:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaceComment.self, from: Data(json.utf8))
    }

    @Test func likingAddsMeAndTheServerCountWins() throws {
        guard let me = AuthService.shared.getUserId() else { return }   // signed-out test host: nothing to check
        let start = try comment(likes: ["someone"], count: 1)
        let liked = start.withLike(true)
        #expect(liked.isLikedByCurrentUser)
        #expect(liked.displayLikesCount == 2)
        #expect(start.withLike(true, count: 5).displayLikesCount == 5)
        let unliked = try comment(likes: ["someone", me], count: 2).withLike(false)
        #expect(!unliked.isLikedByCurrentUser)
        #expect(unliked.displayLikesCount == 1)
    }
}
