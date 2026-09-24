import UIKit
import UserNotifications
import FavWidgetsCore

/// Every notification category the app registers, with its Lock Screen
/// actions. One place to look when a push type gains a button; the
/// server's `category` for a type must match an identifier here.
enum NotificationCategoryRegistry {
    static func register() {
        UNUserNotificationCenter.current().setNotificationCategories(categories())
    }

    static func categories() -> Set<UNNotificationCategory> {
        // Connection request actions
        let acceptAction = UNNotificationAction(
            identifier: "ACCEPT_CONNECTION",
            title: "Accept",
            options: [.authenticationRequired, .foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE_CONNECTION",
            title: "Decline",
            options: [.authenticationRequired, .destructive]
        )
        let connectionCategory = UNNotificationCategory(
            identifier: "CONNECTION_REQUEST",
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Message actions
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_MESSAGE",
            title: "Reply",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your message..."
        )
        let viewAction = UNNotificationAction(
            identifier: "VIEW_MESSAGE",
            title: "View",
            options: [.authenticationRequired, .foreground]
        )
        let messageCategory = UNNotificationCategory(
            identifier: "NEW_MESSAGE",
            actions: [replyAction, viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Place suggestion actions
        let viewPlaceAction = UNNotificationAction(
            identifier: "VIEW_PLACE",
            title: "View Place",
            options: [.authenticationRequired, .foreground]
        )
        let saveAction = UNNotificationAction(
            identifier: "SAVE_PLACE",
            title: "Save to Circle",
            options: [.authenticationRequired]
        )
        let suggestionCategory = UNNotificationCategory(
            identifier: "PLACE_SUGGESTION",
            actions: [viewPlaceAction, saveAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Activity update category
        let viewActivityAction = UNNotificationAction(
            identifier: "VIEW_ACTIVITY",
            title: "View",
            options: [.authenticationRequired, .foreground]
        )
        let activityCategory = UNNotificationCategory(
            identifier: "ACTIVITY_UPDATE",
            actions: [viewActivityAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // "You're near <saved place>" local banner (ProximityNotificationScheduler).
        // Check In opens the pre-filled sheet — the backend needs a recipient,
        // so a background one-tap check-in isn't possible. Not Now runs in the
        // background and stamps the once-per-day gate.
        let checkInAction = UNNotificationAction(
            identifier: ProximityNotificationScheduler.checkInAction,
            title: "Check In",
            options: [.foreground]
        )
        let notNowAction = UNNotificationAction(
            identifier: ProximityNotificationScheduler.notNowAction,
            title: "Not Now",
            options: []
        )
        let checkInPromptCategory = UNNotificationCategory(
            identifier: ProximityNotificationScheduler.categoryIdentifier,
            actions: [checkInAction, notNowAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // "How Are You?" question to a parent, answered right on the Lock
        // Screen. Background actions with NO authentication required, so an
        // older parent answers without unlocking the phone. One category per
        // question KIND, because the buttons are baked in here: the server
        // only sends a kind to builds that registered it (X-App-Build).
        let careCategory = UNNotificationCategory(
            identifier: NotificationActionHandler.CareAnswerAction.categoryIdentifier,
            actions: NotificationActionHandler.CareAnswerAction.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let careDoneCategory = UNNotificationCategory(
            identifier: NotificationActionHandler.CareDoneAction.categoryIdentifier,
            actions: NotificationActionHandler.CareDoneAction.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let careYesNoCategory = UNNotificationCategory(
            identifier: NotificationActionHandler.CareYesNoAction.categoryIdentifier,
            actions: NotificationActionHandler.CareYesNoAction.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        // 0–10 is typed (eleven buttons don't fit a Lock Screen); a tap on
        // the notification itself opens the widget on a big slider.
        let careScaleCategory = UNNotificationCategory(
            identifier: NotificationActionHandler.careScaleCategory,
            actions: [UNTextInputNotificationAction(
                identifier: NotificationActionHandler.careScaleInputAction,
                title: "Answer 0 to 10",
                options: [],
                textInputButtonTitle: "Send",
                textInputPlaceholder: "A number from 0 to 10"
            )],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let careTextCategory = UNNotificationCategory(
            identifier: NotificationActionHandler.careTextCategory,
            actions: [UNTextInputNotificationAction(
                identifier: NotificationActionHandler.careTextInputAction,
                title: "Reply",
                options: [],
                textInputButtonTitle: "Send",
                textInputPlaceholder: "A few words is plenty"
            )],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Water reminder (a local notification the Water widget schedules):
        // "Log a cup" writes today's cup without opening the app.
        let waterCategory = UNNotificationCategory(
            identifier: WaterQuickLog.categoryIdentifier,
            actions: [UNNotificationAction(identifier: WaterQuickLog.logCupAction, title: "Log a cup 💧", options: [])],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        return [
            connectionCategory,
            messageCategory,
            suggestionCategory,
            activityCategory,
            checkInPromptCategory,
            careCategory,
            careDoneCategory,
            careYesNoCategory,
            careScaleCategory,
            careTextCategory,
            waterCategory
        ]
    }
}
