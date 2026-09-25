import CoreGraphics

/// Where the home page scrolls to, and how tall the content slot becomes,
/// when the Moments segment is picked.
///
/// The home is one long scroll view: map, then the feed section (header row,
/// segment bar, content slot). The Moments feed pages one moment per slot
/// height, so with the slot at its usual fixed height and the page scrolled
/// wherever it was, a moment sat partly off-screen and a swipe moved the page
/// instead of the reel. Picking Moments now pins the feed section's top to
/// the top of the visible area and makes the slot exactly the height left
/// under the bar, so one full moment is on screen and each swipe is the next.
enum MomentsTabAnchor {
    struct Layout: Equatable {
        /// New height for the content slot.
        var slotHeight: CGFloat
        /// Outer scroll view content offset (y) that pins the section top.
        var contentOffsetY: CGFloat
    }

    /// - Parameters:
    ///   - visibleHeight: scroll view bounds height minus its adjusted insets.
    ///   - sectionTop: the feed section's top in scroll-content coordinates.
    ///   - chromeHeight: header row + segment bar (+ daily card) above the slot,
    ///     i.e. the slot's top measured from the section's top.
    ///   - topInset: the scroll view's adjusted top inset (nav bar); offsets are
    ///     measured from -topInset.
    ///   - minSlotHeight: never squash the reel below this (tiny landscape).
    static func layout(visibleHeight: CGFloat, sectionTop: CGFloat, chromeHeight: CGFloat,
                       topInset: CGFloat, minSlotHeight: CGFloat = 320) -> Layout {
        let slot = max(minSlotHeight, visibleHeight - chromeHeight)
        return Layout(slotHeight: slot.rounded(.down), contentOffsetY: sectionTop - topInset)
    }
}
