import Foundation

/// At most one moment clip loops in the Activity feed at a time: the one
/// whose row sits nearest the middle of the screen. Pure.
enum ActivityClipFocus {
    /// `rows`: the visible clip rows as (row index, the row's vertical mid
    /// point in the table's coordinates); `visibleMidY`: the middle of what's
    /// on screen. nil when no clip row is visible.
    static func focusedRow(rows: [(row: Int, midY: CGFloat)], visibleMidY: CGFloat) -> Int? {
        rows.min { abs($0.midY - visibleMidY) < abs($1.midY - visibleMidY) }?.row
    }
}
