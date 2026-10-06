import Foundation
import ActivityKit
import FavWidgets
import FavWidgetsCore

/// Map My Run on the lock screen and in the Dynamic Island: started with the
/// run, updated as it goes, ended when it's saved or discarded. The lock
/// screen's Pause/Resume reaches RunSession through ToggleRunPauseIntent.
@available(iOS 16.2, *)
@MainActor
final class RunLiveActivityController {
    static let shared = RunLiveActivityController()

    private var activity: ActivityKit.Activity<RunActivityAttributes>?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .runLiveActivityTogglePause, object: nil, queue: .main) { _ in
            Task { @MainActor in RunSession.shared.togglePause() }
        }
    }

    func apply(_ update: WidgetRunLiveUpdate?) {
        guard let update else { end(); return }
        let state = RunActivityAttributes.ContentState(
            distance: update.distance, unit: update.unit, pace: update.pace,
            movingSeconds: update.movingSeconds, clockStart: update.clockStart, isPaused: update.isPaused)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60))
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try ActivityKit.Activity.request(attributes: RunActivityAttributes(), content: content, pushType: nil)
        } catch {
            Logger.debug("🏃 Live Activity not started: \(error.localizedDescription)")
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// A run that outlived the app (killed mid-run) leaves nothing on the lock screen.
    func endStaleActivities() {
        guard !RunSession.shared.isActive else { return }
        for a in ActivityKit.Activity<RunActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
