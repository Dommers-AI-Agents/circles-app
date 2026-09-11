import UIKit

/// One of the home screen's content tabs (Activity / Moments / Specials).
///
/// The home controller owns the segment bar and a single content container;
/// each tab is a child view controller whose view fills that container. The
/// host toggles tabs with `setTabVisible(_:)` — the child's UIKit appearance
/// callbacks don't fire on an `isHidden` flip, so visibility is explicit.
protocol HomeContentTab: UIViewController {
    /// Whether this tab is the one showing. Set by the host BEFORE any hook or
    /// fetch runs; a tab must not autoplay or touch shared UI unless it is
    /// the visible tab. Data may still load while hidden (e.g. the initial
    /// load fetches every feed at once).
    var isActiveTab: Bool { get set }
    /// The segment was switched to this tab.
    func tabDidBecomeVisible()
    /// The segment is switching away from this tab.
    func tabWillHide()
    /// Pull-to-refresh on the outer scroll view while this tab is visible.
    func refreshTab()
}

extension HomeContentTab {
    func setTabVisible(_ visible: Bool) {
        if visible {
            view.isHidden = false
            isActiveTab = true
            tabDidBecomeVisible()
        } else {
            isActiveTab = false
            tabWillHide()
            view.isHidden = true
        }
    }
}

/// What a tab needs from the home screen. Satisfied by the home controller;
/// mostly its existing methods.
protocol HomeContentTabHost: AnyObject {
    /// The outer scroll view's pull-to-refresh finished for this fetch.
    func endRefreshing()
    /// Lay out the whole home tree now (a tab's own `view.layoutIfNeeded()`
    /// only covers its subtree, which may not be positioned yet).
    func layoutContentIfNeeded()
    /// Pin `overlay` over the whole home screen (pickers that dim and capture
    /// everything, not just the tab's slot).
    func attachFullScreenOverlay(_ overlay: UIView)

    // Destinations shared with deep links; they depend on the home's loaded
    // circles/places, so the home resolves them.
    func navigateToPlace(withId placeId: String, showComments: Bool)
    func navigateToGlobalPlace(withId globalPlaceId: String, showComments: Bool)
    func navigateToCircle(withId circleId: String)
    func navigateToCheckInPlace(activity: Activity)
    /// Switch to the Moments tab and land on `video`.
    func openMomentInMomentsTab(_ video: PlaceVideo)
}
