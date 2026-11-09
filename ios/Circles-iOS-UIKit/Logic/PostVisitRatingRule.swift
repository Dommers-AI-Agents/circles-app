import Foundation

/// After a visit to a store (a reward given, a register scan): a quick 0–10
/// FavCircles rating, then one next step (Wes, 2026-11-09). Google stays as it
/// is; the rating here is the easy one, so it's the one we ask for. Pure.
enum PostVisitRatingRule {

    enum Next: Equatable {
        /// 7 or more: tell your circles — write a review on FavCircles
        case recommend
        /// 4 or less: tell the store privately, where only the team reads it
        case tellPrivately
        /// 5–6: nothing pushed
        case none
    }

    static let recommendFrom = 7
    static let privateUpTo = 4

    static func next(for rating: Int) -> Next {
        if rating >= recommendFrom { return .recommend }
        if rating <= privateUpTo { return .tellPrivately }
        return .none
    }

    /// Regulars aren't asked on every scan: once the rating is older than
    /// this, the next visit asks again ("How was it this time?").
    static let askAgainAfter: TimeInterval = 30 * 24 * 60 * 60

    static func shouldAskAgain(userRatedAt: Date?, now: Date = Date()) -> Bool {
        guard let ratedAt = userRatedAt else { return true }
        return now.timeIntervalSince(ratedAt) > askAgainAfter
    }

    static func prompt(storeName: String, firstTime: Bool) -> String {
        firstTime ? "How would you rate \(storeName)?" : "How was \(storeName) this time?"
    }

    /// The card's wording once a rating is in
    static func followUp(_ next: Next, storeName: String) -> String? {
        switch next {
        case .recommend: return "Glad you love it! A review tells your circles why \(storeName) is worth the trip."
        case .tellPrivately: return "Sorry it wasn't great. Tell \(storeName) privately — only the team reads it."
        case .none: return nil
        }
    }
}
