import Foundation
import UIKit

/// Whether the Activity feed is the lively one (hero cards, motion) or the
/// compact list (Wes, 2026-11-16: "can we switch back easy?"). Two switches,
/// both on by default: the server's `activityFeed.alive` (off = every phone
/// goes back on next launch, no release) AND this phone's own toggle under
/// Settings → Data. Reduce Motion keeps the cards and drops the motion.
enum ActivityFeedPreference {
    static let deviceKey = "activityFeed.lively"
    static let changed = Notification.Name.activityFeedPreferenceChanged

    /// This phone's toggle (default on)
    static var livelyOnThisPhone: Bool {
        get { UserDefaults.standard.object(forKey: deviceKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: deviceKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// The server's switch (missing = on)
    static var liveOnServer: Bool {
        ClientConfigService.shared.config.activityFeed?.alive ?? true
    }

    /// Hero cards on?
    static var isLively: Bool { liveOnServer && livelyOnThisPhone }

    /// Motion on? (the cards without the choreography when Reduce Motion is set)
    static var animates: Bool { isLively && !UIAccessibility.isReduceMotionEnabled }

    // MARK: Grouped activities you swipe through (Wes, 2026-11-24)

    /// A burst of one person's activities as one card you swipe through,
    /// instead of small rows opening under it. Same two switches: the
    /// server's `activityFeed.groupPages` and this phone's toggle. Needs the
    /// lively feed; off, groups open the small rows they always did.
    static let groupPagesDeviceKey = "activityFeed.groupPages"

    static var groupPagesOnThisPhone: Bool {
        get { UserDefaults.standard.object(forKey: groupPagesDeviceKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: groupPagesDeviceKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static var groupPagesOnServer: Bool {
        ClientConfigService.shared.config.activityFeed?.groupPages ?? true
    }

    static var pagesGroups: Bool { isLively && groupPagesOnServer && groupPagesOnThisPhone }

    static let groupPagesRowTitle = "Swipe through grouped activity"
    static let groupPagesRowDetail = "A few activities by one person become one card you swipe; needs the lively feed"

    static let rowTitle = "Lively activity feed"
    static let rowDetail = "Big cards and a little motion for check-ins, places and photos"
}
