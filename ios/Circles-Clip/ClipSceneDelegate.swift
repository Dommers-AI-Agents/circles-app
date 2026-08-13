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
        var code = connectionOptions.userActivities
            .compactMap { Self.stickerCode(from: $0) }
            .first

        #if DEBUG
        // Xcode injects _XCAppClipURL as a user activity, but `simctl launch`
        // only sets the raw env var — honor it directly so CLI testing works.
        if code == nil,
           let testURLString = ProcessInfo.processInfo.environment["_XCAppClipURL"],
           let testURL = URL(string: testURLString) {
            code = Self.stickerCode(fromPath: testURL.path)
        }
        #endif
        window.rootViewController = Self.rootViewController(for: code)
        window.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let code = Self.stickerCode(from: userActivity) else { return }
        window?.rootViewController = Self.rootViewController(for: code)
    }

    private static func rootViewController(for code: String?) -> UIViewController {
        let root: UIViewController
        if let code = code {
            root = ClipOfferViewController(code: code)
        } else {
            // Launched without a sticker URL (e.g. from TestFlight's clip row).
            root = ClipOfferViewController(code: nil)
        }
        let nav = UINavigationController(rootViewController: root)
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
