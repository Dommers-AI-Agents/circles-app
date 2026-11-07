import UIKit

// MARK: - How to add a place (Wes, 2026-11-07)
// The screen says it up front: search above, or tap the place on the map
// (a "Tap a place" pill on the map until its first tap), and your photos are a button
// under the map when the caller offers that route.

extension AddPlaceViewController {
    /// Call once the views are laid out (setupUI).
    func setupAddFromPhotosButton() {
        let offered = onAddFromPhotos != nil
        addFromPhotosButton.isHidden = !offered
        let height = addFromPhotosButton.heightAnchor.constraint(equalToConstant: offered ? 68 : 0)
        height.isActive = true
        addFromPhotosButton.accessibilityHint = "Find places in your photos: pick some, a time period, or build your map"
        addFromPhotosButton.addAction(UIAction { [weak self] _ in self?.onAddFromPhotos?() }, for: .touchUpInside)
    }

    /// The map was tapped or a place picked: the pill has done its job.
    func hideMapTapHint() {
        guard !mapTapHint.isHidden, mapTapHint.alpha > 0 else { return }
        UIView.animate(withDuration: 0.25, animations: { self.mapTapHint.alpha = 0 }) { _ in
            self.mapTapHint.isHidden = true
        }
    }
}
