import UIKit
import CoreLocation
import FavWidgets

/// Applies `QuickCheckInShortcutPlanner` to the app icon's long-press menu.
enum QuickCheckInShortcuts {
    /// Rebuilds the icon menu: the user's chosen actions, then "Check in at
    /// <place>" rows for the nearest saved places to `around` in whatever
    /// slots remain. Safe to call from any queue.
    static func update(places: [Place], around: CLLocation?) {
        // The widget registry is main-actor; the planner is pure and runs here.
        Task { @MainActor in
            let chosen = HomeShortcutCatalog.selection(
                stored: UserDefaults.standard.stringArray(forKey: HomeShortcutCatalog.selectionKey),
                options: HomeShortcutCatalog.options(widgets: FavWidgetRegistry.descriptors.map {
                    HomeShortcutCatalog.Widget(id: $0.id, title: $0.title, symbolName: $0.symbolName)
                })
            )
            let chosenItems = chosen.map { option in
                UIApplicationShortcutItem(
                    type: option.shortcutType,
                    localizedTitle: option.title,
                    localizedSubtitle: option.subtitle,
                    icon: UIApplicationShortcutIcon(systemImageName: option.symbolName),
                    userInfo: nil
                )
            }
            let planned = QuickCheckInShortcutPlanner.plan(
                places: places, around: around,
                limit: HomeShortcutCatalog.nearbySlots(selectedCount: chosen.count)
            )
            let nearbyItems = planned.map { shortcut in
                UIApplicationShortcutItem(
                    type: QuickCheckInShortcutPlanner.checkInAtPlaceType,
                    localizedTitle: "Check in at \(shortcut.placeName)",
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "mappin.and.ellipse"),
                    userInfo: [QuickCheckInShortcutPlanner.placeIdKey: shortcut.placeId as NSSecureCoding]
                )
            }
            UIApplication.shared.shortcutItems = chosenItems + nearbyItems
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
