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
