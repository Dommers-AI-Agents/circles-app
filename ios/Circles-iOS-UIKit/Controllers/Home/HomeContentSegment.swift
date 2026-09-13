import Foundation

/// The home screen's content segments, in segmented-control order. Every
/// index comparison goes through this enum so adding a segment is one
/// case, not a hunt for magic numbers.
enum HomeContentSegment: Int, CaseIterable {
    case activity
    case moments
    case specials
    case widgets

    /// Segment title.
    var title: String {
        switch self {
        case .activity: return "Activity"
        case .moments: return "Moments"
        case .specials: return "Specials"
        case .widgets: return "Widgets"
        }
    }

    /// The header label above the segmented control.
    var headerTitle: String {
        switch self {
        case .activity: return "Recent Activity"
        case .moments: return "Moments"
        case .specials: return "Specials"
        case .widgets: return "Widgets"
        }
    }

    /// Only Moments shows the record-a-moment camera button.
    var showsCameraButton: Bool { self == .moments }
}
