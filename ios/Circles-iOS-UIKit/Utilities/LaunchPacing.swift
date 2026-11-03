import Foundation

/// Background work that shouldn't compete with the first screen at launch
/// (Wes, 2026-11-03: ~20 requests at once made a comment tap wait 7 s).
/// Always a fixed timer from launch, never a condition, so a deferred job
/// can run late by at most `delay` and can never be skipped. After the
/// launch window it runs at once.
enum LaunchPacing {
    /// When the app process started (first touch is in didFinishLaunching)
    static let launchedAt = Date()

    /// Background jobs (import fixes, Spotlight, widget snapshot, next steps)
    static let backgroundDelay: TimeInterval = 4

    /// `work` on the main queue once `delay` seconds have passed since launch
    static func afterLaunch(_ delay: TimeInterval = backgroundDelay, _ work: @escaping () -> Void) {
        let remaining = delay - Date().timeIntervalSince(launchedAt)
        if remaining <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        }
    }
}

/// "At most every N hours" for background passes that rescan the person's
/// whole account (2026-11-03): remembered per account on the device, so a
/// relaunch doesn't redo a pass that just ran. Explicit triggers (an import,
/// a save) don't ask this and run at once.
enum PeriodicPass {
    static func isDue(_ name: String, every interval: TimeInterval, defaults: UserDefaults = .standard,
                      userId: String? = AuthService.shared.getUserId(), now: Date = Date()) -> Bool {
        guard let userId else { return false }
        let key = "periodicPass.\(name).\(userId)"
        if let last = defaults.object(forKey: key) as? Date, now.timeIntervalSince(last) < interval { return false }
        defaults.set(now, forKey: key)
        return true
    }
}
