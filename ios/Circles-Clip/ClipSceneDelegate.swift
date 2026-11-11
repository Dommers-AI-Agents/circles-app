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

        // A Scan Action QR (/q/<code>): a place or list a friend is showing
        // them, a guide, a store's setup (2026-11-11)
        if let scanCode = connectionOptions.userActivities.lazy.compactMap(Self.scanCode(from:)).first {
            window.rootViewController = Self.scanRoot(code: scanCode)
            window.makeKeyAndVisible()
            return
        }

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
            if let scanCode = Self.scanCode(fromPath: testURL.path) {
                window.rootViewController = Self.scanRoot(code: scanCode)
                window.makeKeyAndVisible()
                return
            }
            code = Self.stickerCode(fromPath: testURL.path)
        }
        #endif
        // No code (the Default App Clip Link on an NFC sticker or QR, or
        // TestFlight's row): the generic Join FavCircles flow, never a dead
        // end (Wes, 2026-11-07)
        if code == nil { code = Self.genericJoinCode }
        window.rootViewController = Self.rootViewController(for: ClipInvocation(code: code, tag: activity.flatMap(Self.stickerTag(from:)), ref: activity.flatMap(Self.stickerRef(from:)), payload: activity?.appClipActivationPayload))
        window.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let scanCode = Self.scanCode(from: userActivity) {
            window?.rootViewController = Self.scanRoot(code: scanCode)
            return
        }
        guard let code = Self.stickerCode(from: userActivity)
                ?? (userActivity.webpageURL?.host == "appclip.apple.com" ? Self.genericJoinCode : nil) else { return }
        window?.rootViewController = Self.rootViewController(for: ClipInvocation(code: code, tag: Self.stickerTag(from: userActivity), ref: Self.stickerRef(from: userActivity), payload: userActivity.appClipActivationPayload))
    }

    /// Always the offer screen: it loads the store, then skips straight to
    /// the customer's points when the clip already knows them. Launched
    /// without a code (TestFlight's clip row), it says how to use the clip.
    private static func rootViewController(for invocation: ClipInvocation) -> UIViewController {
        let nav = UINavigationController(rootViewController: ClipOfferViewController(invocation: invocation))
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    private static func scanRoot(code: String) -> UIViewController {
        let nav = UINavigationController(rootViewController: ClipScanViewController(code: code))
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    /// `/q/<code>`: 8 easy-to-read characters, or a guide's name (the app's
    /// Logic/ScanActionLink.swift has the same rules)
    static func scanCode(from activity: NSUserActivity) -> String? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL else { return nil }
        return scanCode(fromPath: url.path)
    }

    static func scanCode(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "q" else { return nil }
        let upper = parts[1].uppercased()
        if upper.range(of: "^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$", options: .regularExpression) != nil { return upper }
        let lower = parts[1].lowercased()
        return lower.range(of: "^[a-z][a-z-]{2,39}$", options: .regularExpression) != nil && !lower.hasSuffix("-") ? lower : nil
    }

    /// The generic "Join FavCircles" code (backend rewardConfig.GENERIC_JOIN_CODE)
    static let genericJoinCode = "JOINUS"

    // Same /s/<CODE> shape the full app routes (SceneDelegate.handleUniversalLink)
    static func stickerCode(from activity: NSUserActivity) -> String? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return nil }
        return stickerCode(fromPath: url.path)
    }

    /// An NFC sticker's tag, `?t=` on the store's window link (2026-11-01)
    static func stickerTag(from activity: NSUserActivity) -> String? {
        guard let url = activity.webpageURL,
              let tag = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value,
              !tag.isEmpty else { return nil }
        return tag
    }

    /// Bring a friend: `?ref=` names who shared the store's link (2026-11-09)
    static func stickerRef(from activity: NSUserActivity) -> String? {
        guard let url = activity.webpageURL,
              let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value,
              !ref.isEmpty else { return nil }
        return ref
    }

    static func stickerCode(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "s" else { return nil }
        let code = parts[1].uppercased()
        guard code.range(of: "^[A-Z0-9]{4,16}$", options: .regularExpression) != nil else { return nil }
        return code
    }
}
