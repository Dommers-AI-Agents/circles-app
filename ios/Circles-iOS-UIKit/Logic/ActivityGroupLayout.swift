import Foundation

/// How a burst of one person's activities is laid out in the Activity feed
/// (Wes, 2026-11-24: the small rows that opened under a group "look small.
/// And kind of out of place").
///
/// A small burst is one card you swipe through: every swipe is a whole
/// activity (its picture, its words, its own heart and comments), so there
/// is nothing left to expand. A big burst would be tedious to swipe, so it
/// keeps "Show all N" — and opens into full-size cards under a thin summary
/// row instead of the small indented rows. Pure, table-tested.
enum ActivityGroupLayout: Equatable {
    /// One card, one activity per swipe
    case pages
    /// The stack card with "Show all N"; opens into full cards
    case expandable

    /// The most activities worth swiping through one at a time
    static let maxPages = 5

    /// `enabled` is the lively feed AND the grouped-pages switches; off, a
    /// burst is today's stack card with the small rows under it (nil).
    static func layout(count: Int, enabled: Bool) -> ActivityGroupLayout? {
        guard enabled, count >= 2 else { return nil }
        return count <= maxPages ? .pages : .expandable
    }

    /// The page a card shows: the one remembered for it, kept inside the
    /// burst (activities can leave a burst between reloads).
    static func page(_ remembered: Int?, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(remembered ?? 0, 0), count - 1)
    }

    /// The page a swipe lands on; nil at either end (the card doesn't wrap,
    /// so the dots always read left to right).
    static func page(after current: Int, count: Int, forward: Bool) -> Int? {
        let next = current + (forward ? 1 : -1)
        return (0..<count).contains(next) ? next : nil
    }
}
