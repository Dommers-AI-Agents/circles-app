import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// The workout in progress on the lock screen and in the Dynamic Island
/// (Wes, 2026-10-30): the next exercise and set with the numbers it'll be
/// logged at, a Done button that ticks it without opening the app, the
/// workout clock, sets done, and the rest countdown after a set.
struct WorkoutLiveActivityWidget: Widget {
    private static let blue = Color(red: 0.192, green: 0.510, blue: 0.808)   // #3182CE, the widget's accent
    private static let openWorkouts = URL(string: "https://api.favcircles.com/app/widget/workouts")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.openWorkouts)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName ?? "All sets done").font(.headline).lineLimit(1)
                        if let label = context.state.setLabel {
                            Text([label, context.state.numbers].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        RestOrClock(state: context.state).font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("\(context.state.doneSets)/\(context.state.totalSets) sets").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DoneButton(state: context.state, tint: Self.blue)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Self.blue)
                    Text("\(context.state.doneSets)/\(context.state.totalSets)").monospacedDigit()
                }
            } compactTrailing: {
                RestOrClock(state: context.state).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(Self.blue)
            }
            .widgetURL(Self.openWorkouts)
            .keylineTint(Self.blue)
        }
    }

    private struct LockScreenWorkoutView: View {
        let state: WorkoutActivityAttributes.ContentState
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(state.name, systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(WorkoutLiveActivityWidget.blue).lineLimit(1)
                    Spacer()
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: 60, alignment: .trailing)
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.exerciseName ?? "All sets done 💪")
                            .font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1)
                        Text(state.exerciseName == nil
                             ? "Open the workout to finish it"
                             : [state.setLabel, state.numbers].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        if let rest = state.restEndsAt, rest > Date() {
                            Text(timerInterval: Date()...rest, countsDown: true)
                                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                                .frame(maxWidth: 70, alignment: .trailing)
                            Text("rest").font(.caption).foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("\(state.doneSets)/\(state.totalSets)")
                                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("sets").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .foregroundStyle(.white)
                DoneButton(state: state, tint: WorkoutLiveActivityWidget.blue)
            }
        }
    }

    /// The rest countdown while one runs, else the workout clock.
    private struct RestOrClock: View {
        let state: WorkoutActivityAttributes.ContentState
        var body: some View {
            if let rest = state.restEndsAt, rest > Date() {
                Text(timerInterval: Date()...rest, countsDown: true).monospacedDigit().foregroundStyle(.orange)
            } else {
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false).monospacedDigit()
            }
        }
    }

    private struct DoneButton: View {
        let state: WorkoutActivityAttributes.ContentState
        let tint: Color
        var body: some View {
            if let setId = state.nextSetId {
                Button(intent: CompleteWorkoutSetIntent(setId: setId)) {
                    Label("Done · \(state.numbers ?? "log this set")", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            } else {
                Link(destination: WorkoutLiveActivityWidget.openWorkouts) {
                    Label("Finish workout", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
}
