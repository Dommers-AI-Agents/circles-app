import Foundation

/// What the owner preview needs from the place page.
protocol PlaceOwnerPreviewDelegate: AnyObject {
    /// Flipped between the owner's view and exactly what customers see.
    func ownerPreviewDidToggle(_ viewingAsCustomer: Bool)
}

/// The owner's state on their own place page: verified owner, and whether
/// they're previewing it as a customer. The page shows; Manage Store edits
/// (2026-10-23: the page's tap-to-edit moved to Manage Store → Store details,
/// one place for every edit, reached from the page's owner bar and the
/// profile's store icon).
final class PlaceOwnerPreview {
    /// Verified owner (or manager) of this venue, from getVenueByPlace
    var isVenueOwner = false
    private(set) var viewingAsCustomer = false
    private weak var host: PlaceOwnerPreviewDelegate?

    init(host: PlaceOwnerPreviewDelegate) {
        self.host = host
    }

    func toggleViewAsCustomer() {
        viewingAsCustomer.toggle()
        host?.ownerPreviewDidToggle(viewingAsCustomer)
    }
}
