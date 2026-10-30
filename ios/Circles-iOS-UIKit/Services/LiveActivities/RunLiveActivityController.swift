import Foundation
import ActivityKit
import FavWidgets
import FavWidgetsCore

/// FavRun on the lock screen and in the Dynamic Island: started with the
/// run, updated as it goes, ended when it's saved or discarded. The lock
/// screen's Pause/Resume reaches RunSession through ToggleRunPauseIntent.
@available(iOS 16.2, *)
@MainActor
final class RunLiveActivityController {
    static let shared = RunLiveActivityController()

    /// The display on the lock screen, whoever started it: after the app
    /// closed mid-run and reopened, the run is restored and keeps updating the
    /// display it already had instead of starting a second one.
    private var activity: ActivityKit.Activity<RunActivityAttributes>? {
        ActivityKit.Activity<RunActivityAttributes>.activities.first { $0.activityState == .active }
    }
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
        if let activity {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try ActivityKit.Activity.request(attributes: RunActivityAttributes(), content: content, pushType: nil)
        } catch {
            Logger.debug("🏃 Live Activity not started: \(error.localizedDescription)")
        }
    }

    private func end() {
        for a in ActivityKit.Activity<RunActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// A display with no run behind it (finished elsewhere, or too old to resume) leaves the lock screen.
    func endStaleActivities() {
        guard !RunSession.shared.isActive else { return }
        for a in ActivityKit.Activity<RunActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
