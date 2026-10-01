import UIKit

extension UIViewController {
    /// Closes this sheet even while its search bar is active.
    ///
    /// With a `UISearchController` in the navigation item, an active search is
    /// itself a presentation on top of the sheet, so a plain
    /// `dismiss(animated:)` closes the SEARCH and leaves the sheet up. Picking
    /// a result then looked like nothing happened, and whatever the caller
    /// presented next (the new conversation, a loading alert) was refused
    /// because the sheet was still on screen (Wes, 2026-10-01: searching for
    /// Margie in New Message and tapping her did nothing). This turns the
    /// search off and dismisses from the presenter, which closes everything
    /// above it in one go; `completion` runs once the sheet is gone.
    func dismissSheet(animated: Bool = true, completion: (() -> Void)? = nil) {
        navigationItem.searchController?.isActive = false
        if let presenter = (navigationController ?? self).presentingViewController {
            presenter.dismiss(animated: animated, completion: completion)
        } else {
            dismiss(animated: animated, completion: completion)
        }
    }
}
