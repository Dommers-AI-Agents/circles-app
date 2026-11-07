import CoreGraphics

/// Where a drag on the search results sheet should leave it: the resting
/// height nearest to where the sheet would coast to. Three of them since
/// 2026-11-07 (Wes: swipe the list up or down for more or less of it):
/// collapsed (handle only), expanded (about half) and full (a strip of map).
struct SearchSheetDetentResolver {
    /// How far a release's speed carries the sheet, in seconds of travel
    static let projection: CGFloat = 0.2
    /// Pulling the list down past this much of over-scroll steps the sheet down.
    static let pullDownCollapseOffset: CGFloat = 60

    /// - currentHeight: the sheet's height when the finger lifts.
    /// - velocityY: points per second, positive = down (the sheet shrinks).
    /// - heights: each resting state's height for the current room and content.
    static func resolve(currentHeight: CGFloat, velocityY: CGFloat,
                        heights: [SearchSheetState: CGFloat]) -> SearchSheetState {
        let projected = currentHeight - velocityY * projection
        return heights.min { abs($0.value - projected) < abs($1.value - projected) }?.key ?? .expanded
    }

    /// The table was pulled down past its top by `offsetY` (negative).
    static func shouldCollapse(forPullDownOffset offsetY: CGFloat) -> Bool {
        offsetY < -pullDownCollapseOffset
    }

    /// One step down from `state` (a pull-down on the list).
    static func stepDown(from state: SearchSheetState) -> SearchSheetState {
        state == .full ? .expanded : .collapsed
    }
}
