import Foundation

/// Words for a circle's "Include on my map" switch (Wes, 2026-10-09: a list
/// of places you want without them on your saved-places map).
enum CircleMapCopy {
    static let title = "Include on my map"
    static let onNote = "Its places show as pins on your map."
    /// Off still alerts on arrival (Wes's call) — and says how to stop that
    static let offNote = "Its places stay in this circle but leave your map and your friends' maps. "
        + "You'll still get an alert when you walk into one — turn that off in Settings → Notifications → Alert Me at Saved Places."
    static let notOnMapTag = "Not on map"

    static func note(isOn: Bool) -> String { isOn ? onNote : offNote }
}
