import UIKit

// MARK: - "Tap a place to add it" (Wes, 2026-11-11)
// The same pill Add Place shows, at the bottom of the Home and expanded maps,
// until the person adds a place from a map once (MapTapHint).

extension FullScreenMapViewController {
    /// Call once from setupUI, after the map is in place.
    func setupMapTapHint() {
        guard MapTapHint.shows(placesTappable: viewMode == .allPlaces) else { return }
        let pill = PaddedPillLabel()
        pill.text = MapTapHint.text
        pill.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        pill.textColor = .white
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        pill.isUserInteractionEnabled = false
        pill.accessibilityLabel = "Tap a place on the map to add it"
        pill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        mapTapHintPill = pill
        NotificationCenter.default.addObserver(self, selector: #selector(mapTapHintRetired),
                                               name: .mapTapHintRetired, object: nil)
    }

    /// A place was tapped: out of the way while its sheet is up (it comes back
    /// next time the map shows, until they add one).
    func hideMapTapHint() {
        guard let pill = mapTapHintPill, pill.alpha > 0 else { return }
        UIView.animate(withDuration: 0.25) { pill.alpha = 0 }
    }

    /// The map is showing again: the pill too, unless they've added from a map.
    func refreshMapTapHint() {
        guard let pill = mapTapHintPill else { return }
        guard MapTapHint.shows(placesTappable: viewMode == .allPlaces) else {
            pill.removeFromSuperview()
            mapTapHintPill = nil
            return
        }
        view.bringSubviewToFront(pill)
        if pill.alpha < 1 { UIView.animate(withDuration: 0.25) { pill.alpha = 1 } }
    }

    @objc private func mapTapHintRetired() {
        guard let pill = mapTapHintPill else { return }
        mapTapHintPill = nil
        UIView.animate(withDuration: 0.25, animations: { pill.alpha = 0 }) { _ in pill.removeFromSuperview() }
    }
}
