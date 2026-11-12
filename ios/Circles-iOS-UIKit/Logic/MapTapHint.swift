import Foundation

/// The "👆 Tap a place to add it" pill on the Home and expanded maps (Wes,
/// 2026-11-11). It shows on maps where places can be tapped until the person
/// adds a place from a map once, then it's gone for good on this phone
/// (device-local, like the other first-use hints).
enum MapTapHint {
    static let text = "👆 Tap a place to add it"
    static let retiredKey = "mapTapHintRetired"

    static func shows(placesTappable: Bool, defaults: UserDefaults = .standard) -> Bool {
        placesTappable && !defaults.bool(forKey: retiredKey)
    }

    /// They chose Add Place on a tapped place: the hint has done its job.
    static func retire(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: retiredKey) else { return }
        defaults.set(true, forKey: retiredKey)
        NotificationCenter.default.post(name: .mapTapHintRetired, object: nil)
    }
}
