import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit
import AppIntents

/// A Wake Up alarm on the lock screen and in the Dynamic Island while it
/// snoozes: the minutes left, and Play now to skip the rest of the snooze
/// and start the station. (The ringing screen itself is the system's.)
@available(iOS 26.0, *)
struct WakeAlarmLiveActivityWidget: Widget {
    static let orange = Color(red: 0.94, green: 0.54, blue: 0.14)   // Wake Up accent #F08A24
    private static let openWakeUp = URL(string: "https://api.favcircles.com/app/widget/wakeup")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, alarmID: context.state.alarmID)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.openWakeUp)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozing", systemImage: "zzz").font(.caption.weight(.semibold)).foregroundStyle(Self.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state).font(.system(size: 24, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PlayNow(metadata: context.attributes.metadata, alarmID: context.state.alarmID)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(Self.orange)
            } compactTrailing: {
                Countdown(state: context.state).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(Self.orange)
            }
            .widgetURL(Self.openWakeUp)
            .keylineTint(Self.orange)
        }
    }

    private struct LockScreenView: View {
        let attributes: AlarmAttributes<WakeAlarmMetadata>
        let state: AlarmPresentationState
        let alarmID: UUID

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Snoozing", systemImage: "zzz").font(.caption.weight(.semibold)).foregroundStyle(WakeAlarmLiveActivityWidget.orange)
                    Spacer()
                    Text("FavCircles").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(attributes.metadata?.title ?? "Wake up")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Countdown(state: state).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                PlayNow(metadata: attributes.metadata, alarmID: alarmID)
            }
        }
    }

    /// Minutes left in the snooze, ticking by itself
    private struct Countdown: View {
        let state: AlarmPresentationState
        var body: some View {
            switch state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now...max(countdown.fireDate, Date.now), countsDown: true)
                    .monospacedDigit().multilineTextAlignment(.trailing)
            default:
                Image(systemName: "alarm.waves.left.and.right.fill")
            }
        }
    }

    /// Skips the rest of the snooze and opens the station
    private struct PlayNow: View {
        let metadata: WakeAlarmMetadata?
        let alarmID: UUID
        var body: some View {
            if let link = metadata?.stationURL, !link.isEmpty {
                Button(intent: WakeUpPlayStationIntent(alarmID: alarmID.uuidString, stationURL: link,
                                                       stationName: metadata?.stationName ?? "")) {
                    Label(metadata?.stationName.map { "Play \($0) now" } ?? "Play now", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(WakeAlarmLiveActivityWidget.orange)
            }
        }
    }
}
