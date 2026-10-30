import Foundation
import ActivityKit
import FirebaseMessaging

/// How Are You? questions on the Lock Screen. The server starts them by push
/// (push-to-start), so the app's jobs are: hand the server this phone's
/// push-to-start token, hand it each displayed question's own token (so an
/// answer anywhere takes it down), and answer from the display's buttons.
/// Started at launch: a push-started display launches the app in the
/// background to collect its token.
@available(iOS 17.2, *)
@MainActor
final class CareLiveActivityController {
    static let shared = CareLiveActivityController()
    private init() {}

    private var started = false
    private var startToken: String?
    private var uploadedStartToken: String?
    private var tokenTasks: [String: Task<Void, Never>] = [:]

    func start() {
        guard !started else { return }
        started = true
        CareQuestionAnswerBridge.answer = { askId, answer in
            await CareLiveActivityController.shared.answer(askId: askId, answer: answer)
        }
        Task { @MainActor in
            for await data in ActivityKit.Activity<CareQuestionAttributes>.pushToStartTokenUpdates {
                self.startToken = data.map { String(format: "%02x", $0) }.joined()
                self.uploadStartTokenIfNeeded()
            }
        }
        Task { @MainActor in
            for await activity in ActivityKit.Activity<CareQuestionAttributes>.activityUpdates {
                self.watchToken(activity)
            }
        }
        for activity in ActivityKit.Activity<CareQuestionAttributes>.activities { watchToken(activity) }
    }

    /// Signed in later than launch, or the FCM token arrived late: try again.
    func uploadStartTokenIfNeeded() {
        guard let token = startToken, token != uploadedStartToken,
              AuthService.shared.isLoggedIn, let fcm = Messaging.messaging().fcmToken else { return }
        APIService.shared.request(endpoint: "widgets/care/live-activity", method: .post,
                                  body: ["token": token, "fcmToken": fcm]) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            Task { @MainActor in
                if case .success = result { self?.uploadedStartToken = token }
                else { Logger.debug("🔒 care push-to-start token not registered") }
            }
        }
    }

    private func watchToken(_ activity: ActivityKit.Activity<CareQuestionAttributes>) {
        let askId = activity.attributes.askId
        guard tokenTasks[askId] == nil, activity.activityState == .active else { return }
        tokenTasks[askId] = Task { @MainActor in
            for await data in activity.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                guard let fcm = Messaging.messaging().fcmToken else { continue }
                APIService.shared.request(endpoint: "widgets/care/asks/\(askId)/live-activity", method: .post,
                                          body: ["token": token, "fcmToken": fcm]) { (result: Result<SimpleAPIResponse, APIError>) in
                    if case .failure(let error) = result { Logger.debug("🔒 care question token not registered: \(error)") }
                }
            }
        }
    }

    /// A choice button on the display: answer, then show what was sent for a moment.
    func answer(askId: String, answer: String) async -> Bool {
        let ok = await CareAnswerService.send(askId: askId, body: ["answer": answer, "note": ""])
        let activity = ActivityKit.Activity<CareQuestionAttributes>.activities.first { $0.attributes.askId == askId }
        guard let activity else { return ok }
        if ok {
            var state = activity.content.state
            state.answered = true
            state.answerText = state.choices.first { $0.key == answer }?.label
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
            tokenTasks[askId]?.cancel()
            tokenTasks[askId] = nil
        }
        return ok
    }
}
