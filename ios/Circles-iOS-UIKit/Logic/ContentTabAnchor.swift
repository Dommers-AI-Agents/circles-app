import CoreGraphics

/// Where the home page scrolls to, and how tall the content slot is, for
/// the tab under the segment bar.
///
/// The home is one long scroll view: map, then the feed section (header row,
/// segment bar, content slot). The slot used to be a fixed 600pt, so with the
/// page scrolled wherever it was its bottom sat below the fold — and every
/// tab scrolls inside the slot, so a drag on a short widget list (which
/// bounces rather than passing the drag up) could never reveal the last
/// card, and a moment sat half off-screen with swipes moving the page. The
/// slot is now exactly the height left under the bar, and picking a tab pins
/// the section's top to the top of the visible area: the whole tab is on
/// screen, and it scrolls inside a frame that is fully visible.
enum ContentTabAnchor {
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
