import UIKit
import UserNotifications
import FavWidgetsCore

/// What the buttons on a notification do (accept, reply, save, answer,
/// log a cup). The AppDelegate hands every `didReceive` here; a plain tap
/// goes back through `onTap`.
final class NotificationActionHandler {
    private let onTap: ([AnyHashable: Any]) -> Void
    private let topViewController: () -> UIViewController?

    init(onTap: @escaping ([AnyHashable: Any]) -> Void, topViewController: @escaping () -> UIViewController?) {
        self.onTap = onTap
        self.topViewController = topViewController
    }

    enum CareAnswerAction: String, CaseIterable {
        static let categoryIdentifier = "CARE_ASK"
        case great = "CARE_GREAT"
        case okay = "CARE_OKAY"
        case notGreat = "CARE_NOT_GREAT"

        var title: String {
            switch self {
            case .great: return "Doing great 👍"
            case .okay: return "Okay"
            case .notGreat: return "Not so good"
            }
        }

        /// The server's answer value.
        var answer: String {
            switch self {
            case .great: return "great"
            case .okay: return "okay"
            case .notGreat: return "not_great"
            }
        }
    }

    /// Sends a Lock Screen answer to the server, then releases the
    /// notification. If the phone is offline the tap opens the widget so

    /// Runs the action. Calls `completion` itself, possibly later: a
    /// background action's process can be suspended the moment the handler
    /// returns, so network-backed actions hold it until their request lands.
    func handle(_ response: UNNotificationResponse, completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification actions
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            onTap(userInfo)
            
        case "ACCEPT_CONNECTION":
            // Handle connection accept action
            if let requestId = userInfo["requestId"] as? String {
                handleAcceptConnection(requestId: requestId)
            }
            
        case "DECLINE_CONNECTION":
            // Handle connection decline action
            if let requestId = userInfo["requestId"] as? String {
                handleDeclineConnection(requestId: requestId)
            }
            
        case "REPLY_MESSAGE":
            // Handle message reply action
            if let textResponse = response as? UNTextInputNotificationResponse,
               let conversationId = userInfo["conversationId"] as? String {
                handleQuickReply(conversationId: conversationId, message: textResponse.userText)
            }
            
        case "VIEW_MESSAGE":
            // Navigate to specific conversation
            if let conversationId = userInfo["conversationId"] as? String {
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToConversation"),
                    object: conversationId
                )
            }
            
        case "VIEW_PLACE":
            // Navigate to place detail
            if let placeId = userInfo["placeId"] as? String {
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToPlace"),
                    object: placeId
                )
            }
            
        case "SAVE_PLACE":
            // Handle save place action
            if let placeId = userInfo["placeId"] as? String {
                handleSavePlace(placeId: placeId)
            }
            
        case "VIEW_ACTIVITY":
            // Navigate based on activity type
            handleViewActivity(userInfo: userInfo)

        case ProximityNotificationScheduler.checkInAction:
            // Same as tapping the banner: open the pre-filled check-in sheet
            onTap(userInfo)

        case WaterQuickLog.logCupAction:
            // Held until the write lands, like the care answers.
            Task {
                do {
                    let result = try await WaterQuickLog.logCup(store: HomeWidgetsAPIDataStore())
                    Logger.debug("💧 Logged a cup from the reminder: \(result.cups) of \(result.goal)")
                } catch {
                    Logger.debug("❌ Water quick log failed: \(error)")
                    NotificationCenter.default.post(name: .navigateToHomeWidget, object: "water")
                }
                await MainActor.run { completion() }
            }
            return

        case CareAnswerAction.great.rawValue, CareAnswerAction.okay.rawValue, CareAnswerAction.notGreat.rawValue:
            // Answer from the Lock Screen. The completion handler is held until
            // the request returns: a background action's process can be
            // suspended as soon as we call it.
            if let askId = userInfo["askId"] as? String, let action = CareAnswerAction(rawValue: response.actionIdentifier) {
                handleCareAnswer(askId: askId, action: action, completion: completion)
                return
            }

        case ProximityNotificationScheduler.notNowAction, UNNotificationDismissActionIdentifier:
            // Don't offer this place again today; free its region slot
            if let type = userInfo["type"] as? String,
               type == ProximityNotificationScheduler.notificationType,
               let placeId = userInfo["placeId"] as? String {
                ProximityNotificationScheduler.markPromptedToday(placeId: placeId)
                ProximityNotificationScheduler.shared.replanFromCache(force: true)
            }

        default:
            break
        }

        completion()
    }

    private func handleCareAnswer(askId: String, action: CareAnswerAction, completion: @escaping () -> Void) {
        APIService.shared.request(
            endpoint: "widgets/care/asks/\(askId)/answer",
            method: .post,
            body: ["answer": action.answer, "note": ""]
        ) { (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    Logger.debug("❌ Care answer failed: \(error)")
                    NotificationCenter.default.post(name: .navigateToHomeWidget, object: "howareyou")
                }
                completion()
            }
        }
    }
    
    /// Post a navigation notification if the main tab bar is already installed;
    /// otherwise stash a pending deep link for SceneDelegate.handlePendingDeepLink
    /// to replay once the interface is up. A cold-start tap posts before any
    /// observer exists and would otherwise be dropped unheard — same pattern the
    /// daily-summary tap uses.

    private func handleAcceptConnection(requestId: String) {
        // Show loading indicator
        DispatchQueue.main.async {
            if let topVC = self.topViewController() {
                let loading = AlertPresenter.showLoading(message: "Accepting connection...", from: topVC)
                
                // Make API call to accept connection
                NetworkManager.shared.acceptConnectionRequest(requestId: requestId) { result in
                    loading.dismiss(animated: true) {
                        switch result {
                        case .success:
                            // Show success and navigate to network
                            AlertPresenter.showSuccess("Connection accepted!", from: topVC)
                            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
                        case .failure(let error):
                            AlertPresenter.showError(error, from: topVC)
                        }
                    }
                }
            }
        }
    }
    
    private func handleDeclineConnection(requestId: String) {
        // Make API call to decline connection
        NetworkManager.shared.declineConnectionRequest(requestId: requestId) { result in
            DispatchQueue.main.async {
                if let topVC = self.topViewController() {
                    switch result {
                    case .success:
                        // Just show a brief confirmation
                        AlertPresenter.showBriefMessage("Connection declined", from: topVC)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: topVC)
                    }
                }
            }
        }
    }
    
    private func handleQuickReply(conversationId: String, message: String) {
        // Send the message via messaging service
        MessagingService.shared.sendQuickReply(conversationId: conversationId, message: message) { result in
            DispatchQueue.main.async {
                if let topVC = self.topViewController() {
                    switch result {
                    case .success:
                        // Show brief success
                        AlertPresenter.showBriefMessage("Reply sent", from: topVC)
                    case .failure(let error):
                        // Show error and offer to open conversation
                        AlertPresenter.showConfirmation(
                            title: "Reply Failed",
                            message: "Failed to send reply. Open conversation?",
                            from: topVC
                        ) {
                            NotificationCenter.default.post(
                                name: Notification.Name("NavigateToConversation"),
                                object: conversationId
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func handleSavePlace(placeId: String) {
        // Show circle picker to save place
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("SavePlaceToCircle"),
                object: placeId
            )
        }
    }
    
    private func handleViewActivity(userInfo: [AnyHashable: Any]) {
        // Navigate based on activity type
        if let activityType = userInfo["activityType"] as? String {
            switch activityType {
            case "new_place", "place_liked":
                if let circleId = userInfo["circleId"] as? String {
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToCircle"),
                        object: circleId
                    )
                }
            case "new_connection":
                NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
            case "comment":
                if let placeId = userInfo["placeId"] as? String {
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToPlace"),
                        object: placeId
                    )
                }
            default:
                // Navigate to home/activity feed
                NotificationCenter.default.post(name: Notification.Name("NavigateToHome"), object: nil)
            }
        }
    }
    
}
