import Foundation

/// Which origins of your OWN places show on your maps: "in_app" (added by
/// you), "photos" (Build my map from my photos), and each import
/// ("google_maps", "mapstr", …). Switched in the map filter's My Places +
/// rows (Wes, 2026-10-16: control automated vs manual additions). Kept on
/// this phone, per account.
enum MapOriginVisibility {
    static let changed = Notification.Name("MapOriginVisibilityChanged")

    /// A place's origin key.
    static func origin(of place: Place) -> String { place.importSource ?? "in_app" }

    private static func key(_ uid: String) -> String { "mapHiddenOrigins.\(uid)" }

    static func hidden(uid: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(uid)) ?? [])
    }

    static func isVisible(_ origin: String, uid: String, defaults: UserDefaults = .standard) -> Bool {
        !hidden(uid: uid, defaults: defaults).contains(origin)
    }

    /// Flips one origin; returns whether it's now visible.
    @discardableResult
    static func toggle(_ origin: String, uid: String, defaults: UserDefaults = .standard) -> Bool {
        var set = hidden(uid: uid, defaults: defaults)
        let nowVisible = set.contains(origin)
        if nowVisible { set.remove(origin) } else { set.insert(origin) }
        defaults.set(Array(set), forKey: key(uid))
        NotificationCenter.default.post(name: changed, object: origin)
        return nowVisible
    }
}
