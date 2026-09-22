import Foundation

/// Where the app lands when someone comes back to it while Sleep Sounds is
/// playing in the background.
///
/// Tapping the Now Playing tile — lock screen, Control Center, Dynamic
/// Island — opens the app but tells it nothing about why. The only signal
/// the app has is that its own sound is still going, and someone returning
/// to an app that is making noise almost always wants the thing making the
/// noise. So: land on the Sleep Sounds page, where the stop button is.
///
/// Pure so the rule is testable without a scene. The lifecycle hook in
/// SceneDelegate only gathers the facts and performs the navigation.
enum NowPlayingReturnGate {
    struct Context: Equatable {
        /// `SleepSoundEngine.shared.isPlaying` at the moment of return.
        var isPlaying: Bool
        var isSignedIn: Bool
        /// Something is presented over the tab bar — a payment sheet, the
        /// postcard composer, an alert. Navigating would dismiss it underneath
        /// the person, so we don't.
        var hasModal: Bool
        /// Which widget page is on top of the home stack, if any. Sleep Sounds
        /// itself means nothing to do; any other widget means someone is in
        /// the middle of something there — a postcard draft, a bill split —
        /// that popping to root would throw away.
        var topWidgetId: String?
    }

    static let sleepSoundsId = "sleepsounds"

    static func shouldOpenSleepSounds(_ c: Context) -> Bool {
        guard c.isPlaying, c.isSignedIn, !c.hasModal else { return false }
        guard c.topWidgetId == nil || c.topWidgetId == sleepSoundsId else { return false }
        return c.topWidgetId != sleepSoundsId
    }
}
