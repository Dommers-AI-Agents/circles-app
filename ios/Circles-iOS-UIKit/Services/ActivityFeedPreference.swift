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

    static let rowTitle = "Lively activity feed"
    static let rowDetail = "Big cards and a little motion for check-ins, places and photos"
}
