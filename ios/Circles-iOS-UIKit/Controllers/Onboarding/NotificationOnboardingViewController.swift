import UIKit
import UserNotifications

/// First-session notification ask (Wes, 2026-10-09: "we want them to
/// accept notifications"). Same primer as location; a no is respected
/// without an extra alert.
final class NotificationOnboardingViewController: PermissionPrimerViewController {
    override var symbolName: String { "bell.badge.fill" }
    override var headline: String { "Don't miss a thing" }
    override var subheadline: String { "Know when the people you follow add to their maps — and when someone loves yours." }
    override var reasons: [Reason] {
        [Reason(symbol: "map.fill", title: "New places from people you follow",
                detail: "See it the moment someone adds a favorite to their map."),
         Reason(symbol: "paperplane.fill", title: "Suggestions and messages",
                detail: "Friends can send you places they think you'll love."),
         Reason(symbol: "heart.fill", title: "Likes, comments and follows",
                detail: "Find out when someone saves or loves a place on your map."),
         Reason(symbol: "alarm.fill", title: "Reminders you set",
                detail: "Water, medications, check-ins and your other widgets.")]
    }
    override var footnote: String? { "You choose which ones you get in Settings → Notifications." }
    override var allowTitle: String { "Turn On Notifications" }

    override func requestPermission() {
        NotificationService.shared.requestNotificationPermissions { [weak self] granted in
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "hasShownNotificationOnboarding")
                AnalyticsService.shared.logEvent("onboarding_notifications_answered", parameters: ["granted": granted ? "1" : "0"])
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                self?.finish()
            }
        }
    }

    override func finish() {
        UserDefaults.standard.set(true, forKey: "hasShownNotificationOnboarding")
        super.finish()
    }
}
