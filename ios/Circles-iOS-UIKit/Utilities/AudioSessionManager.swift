import AVFoundation

/// Owns the app's audio session so other apps' audio (Music, Spotify, podcasts)
/// is only interrupted while the user is actually watching a moment.
///
/// The rule: activate the session at the moment playback starts — never when a
/// player is merely created or preloaded — and release it with
/// `.notifyOthersOnDeactivation` as soon as nothing is playing, so the other
/// app resumes on its own.
final class AudioSessionManager {

    static let shared = AudioSessionManager()

    private init() {}

    /// Whether we currently hold the session. Both calls are idempotent, so
    /// scrolling between moments (which pauses one player and plays the next)
    /// never hands the session back and forth and makes music stutter in.
    private(set) var isHoldingSession = false

    /// Claim the session for video playback. Call immediately before `play()`.
    func beginPlayback() {
        guard !isHoldingSession else { return }
        isHoldingSession = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            Logger.debug("🔊 AudioSession: activated for video playback")
        } catch {
            Logger.debug("❌ AudioSession: failed to activate: \(error)")
        }
    }

    /// Give the session back so other audio can resume. Call once nothing is
    /// playing any more — leaving Moments, pausing everything, backgrounding.
    /// Don't call it between two moments; `beginPlayback` will just re-take it.
    func endPlayback() {
        guard isHoldingSession else { return }
        isHoldingSession = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            Logger.debug("🔇 AudioSession: deactivated, other audio may resume")
        } catch {
            // Deactivating while audio is still winding down throws; harmless.
            Logger.debug("⚠️ AudioSession: failed to deactivate: \(error)")
        }
    }
}
