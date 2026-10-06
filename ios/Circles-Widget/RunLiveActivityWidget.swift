import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// FavRun on the lock screen and in the Dynamic Island: distance, a
/// clock that ticks by itself, pace, and Pause/Resume. Tapping it opens the
/// run (where Finish is).
struct RunLiveActivityWidget: Widget {
    private static let orange = Color(red: 0.867, green: 0.420, blue: 0.125)   // #DD6B20
    private static let openRun = URL(string: "https://api.favcircles.com/app/widget/run")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.openRun)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(context.state.distance).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text(context.state.unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        RunClock(state: context.state).font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("\(context.state.pace) /\(context.state.unit)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PauseButton(isPaused: context.state.isPaused, tint: Self.orange)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "figure.run").foregroundStyle(Self.orange)
                    Text(context.state.distance).monospacedDigit()
                }
            } compactTrailing: {
                RunClock(state: context.state).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run").foregroundStyle(Self.orange)
            }
            .widgetURL(Self.openRun)
            .keylineTint(Self.orange)
        }
    }

    private struct LockScreenRunView: View {
        let state: RunActivityAttributes.ContentState
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(state.isPaused ? "Paused" : "FavRun", systemImage: state.isPaused ? "pause.circle.fill" : "figure.run")
                        .font(.caption.weight(.semibold)).foregroundStyle(RunLiveActivityWidget.orange)
                    Spacer()
                    Text("FavCircles").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.distance).font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text(state.unit == "mi" ? "miles" : "km").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        RunClock(state: state).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("time").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.pace).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("/\(state.unit)").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                PauseButton(isPaused: state.isPaused, tint: RunLiveActivityWidget.orange)
            }
        }
    }

    /// Ticks on its own while running; frozen while paused.
    private struct RunClock: View {
        let state: RunActivityAttributes.ContentState
        var body: some View {
            if let start = state.clockStart, !state.isPaused {
                Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
            } else {
                Text(Self.clock(state.movingSeconds)).monospacedDigit()
            }
        }
        static func clock(_ s: Double) -> String {
            let t = max(0, Int(s))
            return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
        }
    }

    private struct PauseButton: View {
        let isPaused: Bool
        let tint: Color
        var body: some View {
            Button(intent: ToggleRunPauseIntent()) {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isPaused ? .green : tint)
        }
    }
}
