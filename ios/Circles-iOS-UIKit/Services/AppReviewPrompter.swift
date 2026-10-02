import UIKit
import StoreKit

/// Asks for an App Store rating at a calm, happy moment. The rules are
/// `ReviewPromptPolicy`; this keeps the device's counters and calls StoreKit.
/// iOS decides whether the sheet actually appears (and caps it at 3 a year),
/// so a call here is a request, not a guarantee.
final class AppReviewPrompter {
    static let shared = AppReviewPrompter()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let happyMoments = "reviewPrompt.happyMoments"
        static let firstSeen = "reviewPrompt.firstSeen"
        static let lastAsked = "reviewPrompt.lastAsked"
        static let lastAskedVersion = "reviewPrompt.lastAskedVersion"
    }

    private init() {}

    /// A place saved, a badge reached. Also starts the first-seen clock.
    func recordHappyMoment() {
        _ = firstSeen
        defaults.set(defaults.integer(forKey: Key.happyMoments) + 1, forKey: Key.happyMoments)
    }

    /// Call where nothing else is on screen or about to be: after a save that
    /// had no other offer, or as a badge celebration closes.
    func askIfDue(after delay: TimeInterval = 0.6) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let state = ReviewPromptPolicy.State(
            happyMoments: defaults.integer(forKey: Key.happyMoments),
            firstSeen: firstSeen,
            lastAsked: defaults.object(forKey: Key.lastAsked) as? Date,
            lastAskedVersion: defaults.string(forKey: Key.lastAskedVersion)
        )
        guard ReviewPromptPolicy.shouldAsk(state, appVersion: version, now: Date()) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let scene = Self.activeScene() else { return }
            self.defaults.set(Date(), forKey: Key.lastAsked)
            self.defaults.set(version, forKey: Key.lastAskedVersion)
            AnalyticsService.shared.logEvent("app_review_requested", parameters: [:])
            AppStore.requestReview(in: scene)
        }
    }

    private var firstSeen: Date {
        if let date = defaults.object(forKey: Key.firstSeen) as? Date { return date }
        let now = Date()
        defaults.set(now, forKey: Key.firstSeen)
        return now
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
