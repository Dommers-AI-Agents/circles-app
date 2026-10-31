import UIKit
import UserNotifications

// App Clips may post notifications for 8 hours after a launch without asking
// (NSAppClipRequestEphemeralUserNotification). The clip hands its device token
// to the server, which sends at most one reminder in that window, and only if
// they haven't installed the app (controllers/clipController, clip-reminders).
@MainActor
final class ClipNotifications {
    static let shared = ClipNotifications()
    private var pending: (bearer: String, code: String?)?

    func register(session: ClipSession, code: String?) {
        pending = (session.token, code)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // .ephemeral: granted for the clip's 8 hours; never prompt
            guard settings.authorizationStatus == .ephemeral || settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didRegister(deviceToken: Data) {
        guard let pending else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            try? await ClipAPIClient.shared.registerDevice(token: token, code: pending.code, bearer: pending.bearer)
        }
    }
}
