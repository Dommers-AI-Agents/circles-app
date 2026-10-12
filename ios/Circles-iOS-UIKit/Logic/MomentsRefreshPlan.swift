import Foundation

/// What a quiet background refresh of the Moments feed should do with the
/// moments already on screen (Wes, 2026-10-12: switching to Moments used to
/// blank the feed and wait for the network every time). Pure.
enum MomentsRefreshPlan: Equatable {
    /// Same moments in the same order: update their counts in place
    case unchanged
    /// Moments the viewer hasn't seen arrived: offer them with a pill rather
    /// than yanking the video that's playing
    case newMoments(count: Int)

    /// `current`: ids on screen (any number loaded so far); `fresh`: ids of
    /// the newest page. Moments that disappeared (deleted, now hidden) are
    /// left for the next full load rather than pulled out from under the
    /// viewer.
    static func plan(current: [String], fresh: [String]) -> MomentsRefreshPlan {
        let onScreen = Set(current)
        let added = fresh.filter { !onScreen.contains($0) }.count
        return added > 0 ? .newMoments(count: added) : .unchanged
    }
}
