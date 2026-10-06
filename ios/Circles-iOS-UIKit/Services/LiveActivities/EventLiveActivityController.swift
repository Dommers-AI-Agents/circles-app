import Foundation
import ActivityKit
import FirebaseMessaging
import FavWidgetsCore

/// An event on the lock screen: started from the event's Lock Screen button,
/// then kept current by the server, which gets this activity's push token
/// (and the phone's FCM token, which FCM needs to route it).
@available(iOS 16.2, *)
@MainActor
final class EventLiveActivityController {
    static let shared = EventLiveActivityController()
    private init() {}

    private var tokenTasks: [String: Task<Void, Never>] = [:]

    private func activity(for eventId: String) -> ActivityKit.Activity<EventActivityAttributes>? {
        ActivityKit.Activity<EventActivityAttributes>.activities.first { $0.attributes.eventId == eventId && $0.activityState == .active }
    }

    func isOn(_ eventId: String) -> Bool { activity(for: eventId) != nil }

    func start(_ event: WidgetEventLiveStart) -> Bool {
        if isOn(event.eventId) { return true }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let attributes = EventActivityAttributes(eventId: event.eventId, name: event.name, emoji: event.emoji)
        let state = EventActivityAttributes.ContentState(
            members: event.members, photos: event.photos,
            headline: "\(event.members) \(event.members == 1 ? "person" : "people") in", rollCall: nil, song: nil, challenges: nil, ended: false)
        do {
            let activity = try ActivityKit.Activity.request(
                attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(6 * 3600)),
                pushType: .token)
            watchToken(activity)
            return true
        } catch {
            Logger.debug("🔒 Event Live Activity not started: \(error.localizedDescription)")
            return false
        }
    }

    func stop(_ eventId: String) async {
        tokenTasks[eventId]?.cancel()
        tokenTasks[eventId] = nil
        if let activity = activity(for: eventId) { await activity.end(nil, dismissalPolicy: .immediate) }
        APIService.shared.request(endpoint: "widgets/events/\(eventId)/live-activity", method: .delete) { (_: Result<SimpleAPIResponse, APIError>) in }
    }

    /// Re-attach token watchers after a relaunch (the activities outlive the app).
    func resumeWatchingTokens() {
        for activity in ActivityKit.Activity<EventActivityAttributes>.activities where activity.activityState == .active {
            if tokenTasks[activity.attributes.eventId] == nil { watchToken(activity) }
        }
    }

    private func watchToken(_ activity: ActivityKit.Activity<EventActivityAttributes>) {
        let eventId = activity.attributes.eventId
        tokenTasks[eventId] = Task { @MainActor in
            for await data in activity.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                guard let fcm = Messaging.messaging().fcmToken else { continue }
                APIService.shared.request(endpoint: "widgets/events/\(eventId)/live-activity", method: .post,
                                          body: ["token": token, "fcmToken": fcm]) { (result: Result<SimpleAPIResponse, APIError>) in
                    if case .failure(let error) = result { Logger.debug("🔒 live token not registered: \(error)") }
                }
            }
        }
    }
}
