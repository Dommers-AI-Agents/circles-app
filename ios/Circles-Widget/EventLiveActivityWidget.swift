import SwiftUI
import WidgetKit
import ActivityKit

/// An event on the lock screen and in the Dynamic Island: what just
/// happened, roll call, the song up next, and a tap into the event. The
/// server updates it by push for everyone who turned it on.
struct EventLiveActivityWidget: Widget {
    private static let purple = Color(red: 0.482, green: 0.184, blue: 0.969)   // #7B2FF7
    private static let pink = Color(red: 1, green: 0.24, blue: 0.5)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            LockScreenEventView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(EventLiveLinks.open(context.attributes.eventId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji).font(.system(size: 34))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(context.state.photos)").font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("photos").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.rollCall ?? context.state.headline).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let song = context.state.song { Text(song).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(context.attributes.emoji)
            } compactTrailing: {
                if let rc = context.state.rollCall {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange).accessibilityLabel(rc)
                } else {
                    Text("\(context.state.photos) 📸").font(.caption2.weight(.semibold))
                }
            } minimal: {
                Text(context.attributes.emoji)
            }
            .widgetURL(EventLiveLinks.open(context.attributes.eventId))
            .keylineTint(Self.purple)
        }
    }

    private struct LockScreenEventView: View {
        let attributes: EventActivityAttributes
        let state: EventActivityAttributes.ContentState

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(attributes.emoji).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attributes.name).font(.system(size: 17, weight: .heavy)).lineLimit(1)
                        Text(state.ended ? "Ended" : "\(state.members) people · \(state.photos) photos")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Text("FavCircles").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                if let rc = state.rollCall {
                    Label(rc, systemImage: "hand.raised.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.orange)
                }
                Text(state.headline).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 12) {
                    if let song = state.song { Text(song).lineLimit(1) }
                    if let c = state.challenges { Text("🏆 \(c)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.white.opacity(0.8))
                if !state.ended {
                    Link(destination: EventLiveLinks.open(attributes.eventId)) {
                        Label(state.rollCall != nil ? "I'm here" : "Open the event", systemImage: state.rollCall != nil ? "hand.raised" : "camera.fill")
                            .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(LinearGradient(colors: [EventLiveActivityWidget.pink, EventLiveActivityWidget.purple],
                                                                      startPoint: .leading, endPoint: .trailing)))
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }
}
