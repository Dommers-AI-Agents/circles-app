import CoreGraphics

/// The two resting positions of the home search results sheet.
enum SearchSheetState: Equatable {
    /// Rows visible, sheet as tall as its content allows.
    case expanded
    /// Only the handle line ("26 places · 3 nearby") shows; the map has the room.
    case collapsed
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
    static let rowHeight: CGFloat = 60
    /// Chip bar (8–44) and expand button (56–92) stay clear above the sheet.
    static let minMapStrip: CGFloat = 150
    /// Handle + one header + one row.
    static let minSheetHeight: CGFloat = handleHeight + headerHeight + rowHeight
    static let expandedFraction: CGFloat = 0.55
    /// Search bar bottom → map top while searching: 6 + 32 (mode control) + 8.
    static let modeControlClearance: CGFloat = 46

    /// Handle plus every non-empty section (header + rows).
    static func contentHeight(for plan: HomeSearchPlan) -> CGFloat {
        var height = handleHeight
        for rows in [plan.placeRows, plan.suggestedRows, plan.peopleRows] where rows > 0 {
            height += headerHeight + CGFloat(rows) * rowHeight
        }
        return height
    }

    /// The expanded sheet's height for `available` points of room.
    static func expandedHeight(available: CGFloat, content: CGFloat) -> CGFloat {
        let room = max(minSheetHeight, min(expandedFraction * available, available - minMapStrip))
        return min(content, room)
    }

    static func height(for state: SearchSheetState, available: CGFloat, content: CGFloat) -> CGFloat {
        switch state {
        case .collapsed: return handleHeight
        case .expanded: return expandedHeight(available: available, content: content)
        }
    }
}
