import Foundation
import ActivityKit
import FavWidgets
import FavWidgetsCore

/// The workout on the lock screen and in the Dynamic Island (2026-10-30):
/// started with the workout, kept in step with the workout screen, ended on
/// finish or discard. Its Done button reaches `completeSet` through
/// CompleteWorkoutSetIntent, which ticks the set in the workout document
/// (WorkoutQuickLog) whether or not the workout screen is open.
@available(iOS 16.2, *)
@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()

    private var activity: ActivityKit.Activity<WorkoutActivityAttributes>? {
        ActivityKit.Activity<WorkoutActivityAttributes>.activities.first { $0.activityState == .active }
    }

    private init() {}

    /// Hooked up at launch so a lock-screen tap that cold-launches the app
    /// finds its handler.
    static func install() {
        WorkoutLiveActivityBridge.completeSet = { setId in
            await WorkoutLiveActivityController.shared.completeSet(setId)
        }
    }

    func apply(_ update: WidgetWorkoutLiveUpdate?) {
        guard let update else { end(); return }
        let state = WorkoutActivityAttributes.ContentState(
            name: update.name, startedAt: update.startedAt, doneSets: update.doneSets, totalSets: update.totalSets,
            exerciseName: update.exerciseName, setLabel: update.setLabel, numbers: update.numbers,
            nextSetId: update.nextSetId, restEndsAt: update.restEndsAt)
        // A gym session can run a couple of hours with the phone locked
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(4 * 60 * 60))
        if let activity, activity.attributes.sessionId == update.sessionId {
            Task { await activity.update(content) }
            return
        }
        // A different workout: the old display goes, the new one starts
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try ActivityKit.Activity.request(attributes: WorkoutActivityAttributes(sessionId: update.sessionId),
                                                 content: content, pushType: nil)
        } catch {
            Logger.debug("🏋️ Workout Live Activity not started: \(error.localizedDescription)")
        }
    }

    /// Done on the lock screen: tick that set in the saved workout, then
    /// show the next one (with a rest countdown when auto rest is on).
    func completeSet(_ setId: String) async {
        guard let id = UUID(uuidString: setId), let userId = KeychainService.shared.getUserId() else { return }
        let store = AppWidgetHost.makeDataStore(userId: userId)
        do {
            let settings = try await WorkoutQuickLog.completeSet(id, store: store)
            let rest = settings.autoRestTimer ? Date().addingTimeInterval(TimeInterval(max(5, settings.restTimerSeconds))) : nil
            apply(WorkoutLivePlan.state(settings).map { WidgetWorkoutLiveUpdate(state: $0, restEndsAt: rest) })
        } catch {
            Logger.debug("🏋️ Lock-screen set not saved: \(error.localizedDescription)")
        }
    }

    /// App opened: put the display back in step with the saved workout (a
    /// workout finished on another phone, or a display left from a killed app).
    func reconcile() async {
        guard let userId = KeychainService.shared.getUserId() else { end(); return }
        let settings = await WorkoutQuickLog.load(store: AppWidgetHost.makeDataStore(userId: userId))
        guard let state = settings.flatMap(WorkoutLivePlan.state) else {
            end()
            return
        }
        // Only refresh one that's up; starting a display is the workout screen's call
        guard activity != nil else { return }
        let rest = activity?.content.state.restEndsAt.flatMap { $0 > Date() ? $0 : nil }
        apply(WidgetWorkoutLiveUpdate(state: state, restEndsAt: rest))
    }

    private func end() {
        for a in ActivityKit.Activity<WorkoutActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
