import Foundation

/// Whether a finished place fetch may replace what the home screen already
/// holds in memory.
///
/// Offline, every batch request fails and the fetch "completes" with nothing.
/// Replacing the pins painted from the disk cache with that nothing is how a
/// cached launch showed the map and then emptied it a second later. A fetch
/// that failed somewhere and brought back nothing says nothing about the
/// user's places, so what is on screen stays.
///
/// A complete fetch always wins, including a complete empty one — the user
/// really may have deleted their last place.
enum PlaceRefreshMerge {
    static func shouldReplaceInMemory(fetched: Int, fetchComplete: Bool, current: Int) -> Bool {
        if fetchComplete { return true }
        if fetched > 0 { return true }
        return current == 0
    }
}
