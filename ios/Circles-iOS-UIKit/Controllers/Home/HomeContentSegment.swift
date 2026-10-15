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
        case .specials: return "Locals"
        case .widgets: return "Widgets"
        }
    }

    /// The header label above the segmented control.
    var headerTitle: String {
        switch self {
        case .activity: return "Recent Activity"
        case .moments: return "Moments"
        case .specials: return "Locals"
        case .widgets: return "Widgets"
        }
    }

    /// Only Moments shows the record-a-moment camera button.
    var showsCameraButton: Bool { self == .moments }

    // MARK: - Sharing a tab

    /// The slug a tab's share link carries (`/app/tab/<slug>`), for the tabs
    /// worth sending someone: Locals and Widgets (Wes, 2026-10-15). Activity
    /// and Moments are the viewer's own network, so a link to them means
    /// nothing to anyone else. The slug is the public name, not the case
    /// name: "specials" is a leftover.
    var shareSlug: String? {
        switch self {
        case .specials: return "locals"
        case .widgets: return "widgets"
        case .activity, .moments: return nil
        }
    }

    /// The segment a share link names; nil for any other slug.
    init?(shareSlug: String) {
        // "local" was the slug for a day before the tab became Locals
        let slug = shareSlug.lowercased() == "local" ? "locals" : shareSlug.lowercased()
        guard let match = Self.allCases.first(where: { $0.shareSlug == slug }) else { return nil }
        self = match
    }

    /// The header shows a Share button on the tabs that have a link.
    var showsShareButton: Bool { shareSlug != nil }

    /// What the shared card says the tab is, in one line.
    var shareBlurb: String {
        switch self {
        case .specials: return "Deals at the places near you, and what's on nearby."
        case .widgets: return "Mini-apps for everyday life: water, workouts, events, postcards and more."
        case .activity: return "What the people you know are saving and doing."
        case .moments: return "Short videos from places people love."
        }
    }

    /// The symbol on the shared card.
    var shareSymbolName: String {
        switch self {
        case .specials: return "mappin.and.ellipse"
        case .widgets: return "square.grid.2x2.fill"
        case .activity: return "person.2.fill"
        case .moments: return "play.rectangle.fill"
        }
    }
}
