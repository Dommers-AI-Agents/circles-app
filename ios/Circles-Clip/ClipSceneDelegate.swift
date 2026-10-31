import AppClip
import UIKit

class ClipSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        // The invocation URL rides in on an NSUserActivity — from the camera /
        // App Clip code at launch (connectionOptions) or later via continueUserActivity.
        let activity = connectionOptions.userActivities.first { Self.stickerCode(from: $0) != nil }
        var code = activity.flatMap(Self.stickerCode(from:))

        #if DEBUG
        // Testing from the start: CLIP_RESET=1 forgets the signed-in customer
        if ProcessInfo.processInfo.environment["CLIP_RESET"] == "1" {
            ClipSession.clear()
        }
        // Xcode injects _XCAppClipURL as a user activity, but `simctl launch`
        // only sets the raw env var — honor it directly so CLI testing works.
        if code == nil,
           let testURLString = ProcessInfo.processInfo.environment["_XCAppClipURL"],
           let testURL = URL(string: testURLString) {
            code = Self.stickerCode(fromPath: testURL.path)
        }
        #endif
        window.rootViewController = Self.rootViewController(for: ClipInvocation(code: code, payload: activity?.appClipActivationPayload))
        window.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let code = Self.stickerCode(from: userActivity) else { return }
        window?.rootViewController = Self.rootViewController(for: ClipInvocation(code: code, payload: userActivity.appClipActivationPayload))
    }

    /// Always the offer screen: it loads the store, then skips straight to
    /// the customer's points when the clip already knows them. Launched
    /// without a code (TestFlight's clip row), it says how to use the clip.
    private static func rootViewController(for invocation: ClipInvocation) -> UIViewController {
        let nav = UINavigationController(rootViewController: ClipOfferViewController(invocation: invocation))
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    // Same /s/<CODE> shape the full app routes (SceneDelegate.handleUniversalLink)
    static func stickerCode(from activity: NSUserActivity) -> String? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return nil }
        return stickerCode(fromPath: url.path)
    }

    static func stickerCode(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "s" else { return nil }
        let code = parts[1].uppercased()
        guard code.range(of: "^[A-Z0-9]{4,16}$", options: .regularExpression) != nil else { return nil }
        return code
    }
}
