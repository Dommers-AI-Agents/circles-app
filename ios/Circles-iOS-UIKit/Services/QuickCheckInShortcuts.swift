import UIKit
import CoreLocation

/// Applies `QuickCheckInShortcutPlanner` to the app icon's long-press menu.
enum QuickCheckInShortcuts {
    /// Replaces the dynamic "Check in at <place>" rows with the nearest
    /// saved places to `around`. Safe to call from any queue.
    static func update(places: [Place], around: CLLocation?) {
        let planned = QuickCheckInShortcutPlanner.plan(places: places, around: around)
        let items = planned.map { shortcut in
            UIApplicationShortcutItem(
                type: QuickCheckInShortcutPlanner.checkInAtPlaceType,
                localizedTitle: "Check in at \(shortcut.placeName)",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "mappin.and.ellipse"),
                userInfo: [QuickCheckInShortcutPlanner.placeIdKey: shortcut.placeId as NSSecureCoding]
            )
        }
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = items
        }
    }

    /// Recomputes from the disk cache and the last location fix, for hooks
    /// that have neither in hand (backgrounding).
    static func updateFromCache() {
        guard let userId = AuthService.shared.getUserId() else { return }
        let location = LocationService.shared.lastKnownLocation
        PlacesDiskCache.shared.load(userId: userId) { cached in
            update(places: cached ?? [], around: location)
        }
    }

    /// The previous account's place names must not sit on the menu.
    static func clear() {
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = []
        }
    }
}
