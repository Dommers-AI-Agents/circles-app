import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// A How Are You? question on the parent's Lock Screen until they answer it:
/// who's asking, the question, and the answer buttons. A 0–10 or typed
/// question opens the widget to answer. After answering it shows what was
/// sent for a moment, then goes.
struct CareQuestionLiveActivityWidget: Widget {
    static let accent = Color(red: 0.878, green: 0.337, blue: 0.498)   // How Are You? accent #E0567F

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CareQuestionAttributes.self) { context in
            LockScreenQuestionView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(CareQuestionLinks.open)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.attributes.fromName) asks", systemImage: "heart.text.square.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Self.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.question).font(.subheadline.weight(.semibold)).lineLimit(2)
                        AnswerButtons(askId: context.attributes.askId, state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "heart.text.square.fill").foregroundStyle(Self.accent)
            } compactTrailing: {
                Text(context.state.answered ? "Sent" : "Answer").font(.caption2.weight(.semibold)).foregroundStyle(Self.accent)
            } minimal: {
                Image(systemName: context.state.answered ? "checkmark" : "heart.text.square.fill").foregroundStyle(Self.accent)
            }
            .widgetURL(CareQuestionLinks.open)
            .keylineTint(Self.accent)
        }
    }

    private struct LockScreenQuestionView: View {
        let attributes: CareQuestionAttributes
        let state: CareQuestionAttributes.ContentState
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(attributes.fromName) asks", systemImage: "heart.text.square.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(CareQuestionLiveActivityWidget.accent)
                    Spacer()
                    Text("FavCircles").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Text(state.question)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                AnswerButtons(askId: attributes.askId, state: state)
            }
        }
    }

    /// One button per choice (answers in place), or "Answer" into the widget
    /// for a number or words. Once answered: what was sent.
    private struct AnswerButtons: View {
        let askId: String
        let state: CareQuestionAttributes.ContentState
        var body: some View {
            if state.answered {
                Label("Sent: \(state.answerText ?? "your answer")", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(CareQuestionLiveActivityWidget.accent)
            } else if state.choices.isEmpty {
                Link(destination: CareQuestionLinks.open) {
                    Text(state.kind == "scale" ? "Answer 0–10" : "Answer")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(CareQuestionLiveActivityWidget.accent))
                        .foregroundStyle(.white)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(state.choices, id: \.key) { choice in
                        Button(intent: AnswerCareQuestionIntent(askId: askId, answer: choice.key)) {
                            Text(choice.label)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .background(Capsule().fill(CareQuestionLiveActivityWidget.accent.opacity(0.9)))
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}
