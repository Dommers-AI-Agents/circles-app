import CoreGraphics

/// The two resting positions of the home search results sheet.
enum SearchSheetState: Equatable {
    /// Rows visible, sheet as tall as its content allows.
    case expanded
    /// Only the handle line ("26 places · 3 nearby") shows; the map has the room.
    case collapsed
    /// Swiped up for more of the list: a thin strip of map stays (Wes, 2026-11-07)
    case full
}

/// How tall the search results sheet is, given the room between the mode
/// control and the keyboard (or the safe-area bottom). Pure so the numbers
/// are testable; the view applies them.
///
/// Rules: the sheet takes about half the room and always leaves a strip of
/// map tall enough for the chip bar and the expand button; it never shrinks
/// below one row (on small phones the map strip gives way first); and it is
/// never taller than its content.
struct SearchSheetLayout {
    static let handleHeight: CGFloat = 52
    static let headerHeight: CGFloat = 28
    /// Title + distance/address line (same as the map's own list rows).
    static let rowHeight: CGFloat = 72
    /// Chip bar (8–44) and expand button (56–92) stay clear above the sheet.
    static let minMapStrip: CGFloat = 150
    /// Handle + one header + one row.
    static let minSheetHeight: CGFloat = handleHeight + headerHeight + rowHeight
    static let expandedFraction: CGFloat = 0.55
    /// Map left above a sheet swiped all the way up
    static let fullMapStrip: CGFloat = 56
    /// Search bar bottom → map top while searching.
    static let searchMapTopInset: CGFloat = 8

    /// Handle plus every non-empty section. Results sections have no title
    /// (the handle's chips name and count them, Wes 2026-11-07); recent
    /// searches and browse keep theirs.
    static func contentHeight(for plan: HomeSearchPlan) -> CGFloat {
        var height = handleHeight
        for rows in [plan.widgetRows, plan.placeRows, plan.suggestedSectionRows, plan.peopleSectionRows] where rows > 0 {
            height += CGFloat(rows) * rowHeight
        }
        for rows in [plan.recentRows, plan.browseRows] where rows > 0 {
            height += headerHeight + CGFloat(rows) * rowHeight
        }
        // The status line has no header
        height += CGFloat(plan.statusRows) * rowHeight
        return height
    }

    /// The expanded sheet's height for `available` points of room.
    static func expandedHeight(available: CGFloat, content: CGFloat) -> CGFloat {
        let room = max(minSheetHeight, min(expandedFraction * available, available - minMapStrip))
        return min(content, room)
    }

    /// Swiped up: all the room but a thin strip of map, never taller than the content.
    static func fullHeight(available: CGFloat, content: CGFloat) -> CGFloat {
        min(content, max(expandedHeight(available: available, content: content), available - fullMapStrip))
    }

    static func height(for state: SearchSheetState, available: CGFloat, content: CGFloat) -> CGFloat {
        switch state {
        case .collapsed: return handleHeight
        case .expanded: return expandedHeight(available: available, content: content)
        case .full: return fullHeight(available: available, content: content)
        }
    }
}
