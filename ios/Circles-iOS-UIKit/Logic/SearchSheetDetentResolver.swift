import CoreGraphics

/// Where a drag on the search results sheet should leave it. A flick decides
/// by direction; a slow drag decides by whether it went past halfway.
struct SearchSheetDetentResolver {
    /// Points per second: faster than this and the direction alone decides.
    static let flickVelocity: CGFloat = 500
    /// Pulling the list down past this much of over-scroll collapses the sheet.
    static let pullDownCollapseOffset: CGFloat = 60

    /// - translationY: finger travel since the drag began (positive = down).
    /// - travel: expanded height minus handle height.
    static func resolve(from state: SearchSheetState,
                        translationY: CGFloat,
                        velocityY: CGFloat,
                        travel: CGFloat) -> SearchSheetState {
        if velocityY > flickVelocity { return .collapsed }
        if velocityY < -flickVelocity { return .expanded }
        let half = max(travel, 1) / 2
        switch state {
        case .expanded: return translationY > half ? .collapsed : .expanded
        case .collapsed: return translationY < -half ? .expanded : .collapsed
        }
    }

    /// The table was pulled down past its top by `offsetY` (negative).
    static func shouldCollapse(forPullDownOffset offsetY: CGFloat) -> Bool {
        offsetY < -pullDownCollapseOffset
    }
}
