import Foundation

/// Where a tapped push takes the person. Pure: `userInfo` in, a destination
/// out, no UIKit and no NotificationCenter. The AppDelegate performs it.
/// Each case mirrors one branch of the old 270-line switch, so a table
/// test can pin every push type the server sends.
enum NotificationDestination: Equatable {
    case conversation(id: String)
    case messages
    case homeWidget(id: String)
    /// "Your postcard is printing": the postcard page opened on that card's detail.
    case postcardOrder(id: String)
    /// The quote of the day: the Quotes page opened on that quote in the reel.
    case dailyQuote(id: String)
    case suggestions(placeId: String?, suggestionId: String?)
    /// `showComments` nil = post without userInfo (as `new_place` always did).
    case circle(id: String, showComments: Bool?)
    case place(id: String, showComments: Bool?)
    /// nil id = the activity feed itself.
    case activity(id: String?)
    case network(showPending: Bool)
    /// "X accepted your request": remembers X, then opens the network tab on them.
    case connectionAccepted(userId: String)
    case dailySummary
    /// Post `navName` if the tab bar is up, else stash `pending` for the scene.
    case postOrStash(navName: String, pending: String, object: String?)
    /// The proximity banner: marks the place prompted today, then check-in.
    case proximityCheckIn(placeId: String)
    case piggyBank
    case userProfile(id: String)
    case video(id: String)
    case meTab
    case deepLink(URL)
}

enum NotificationTapRouter {
    /// The push type, wherever the sender put it.
    static func type(in userInfo: [AnyHashable: Any]) -> String? {
        if let type = userInfo["type"] as? String { return type }
        if let custom = userInfo["customData"] as? [String: Any], let type = custom["type"] as? String { return type }
        if let data = userInfo["data"] as? [String: Any], let type = data["type"] as? String { return type }
        return nil
    }

    static func destination(for userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        guard let type = type(in: userInfo) else { return nil }
        let placeId = userInfo["placeId"] as? String
        let activityId = userInfo["activityId"] as? String
        let circleId = userInfo["circleId"] as? String
        let conversationId = userInfo["conversationId"] as? String

        switch type {
        case "new_message":
            return conversationId.map { .conversation(id: $0) } ?? .messages

        case "nextbar_round", "nextbar_result": return .homeWidget(id: "nextbar")
        case "fridgemail": return .homeWidget(id: "fridgemail")
        case "postcard_order":
            if let orderId = string("orderId", in: userInfo) { return .postcardOrder(id: orderId) }
            return .homeWidget(id: "postcard")
        case "water_reminder": return .homeWidget(id: "water")
        case "daily_quote":
            if let quoteId = string("quoteId", in: userInfo) { return .dailyQuote(id: quoteId) }
            return .homeWidget(id: "quotes")
        case "care_invite", "care_ask", "care_answer", "care_accepted", "care_silence": return .homeWidget(id: "howareyou")

        case "new_suggestion":
            return .suggestions(placeId: placeId, suggestionId: userInfo["suggestionId"] as? String)

        case "new_place":
            return circleId.map { .circle(id: $0, showComments: nil) }

        case "place_liked", "place_commented":
            if let placeId { return .place(id: placeId, showComments: type == "place_commented") }
            return activityId.map { .activity(id: $0) }

        case "circle_liked", "circle_commented":
            if let circleId { return .circle(id: circleId, showComments: type == "circle_commented") }
            return activityId.map { .activity(id: $0) }

        case "connection_request":
            return .network(showPending: true)

        case "connection_accepted":
            if let by = userInfo["acceptedByUserId"] as? String { return .connectionAccepted(userId: by) }
            return .network(showPending: false)

        case "daily_summary":
            return .dailySummary

        case "check_in", "checkin":
            // The old switch had this label twice; the first arm (place, else
            // activity) is the one that ever ran. Kept exactly.
            if let placeId { return .place(id: placeId, showComments: nil) }
            return activityId.map { .activity(id: $0) }

        case "check_in_response":
            return placeId.map { .place(id: $0, showComments: nil) }

        case "activity_update", "activity_like", "activity_comment":
            return .activity(id: activityId)

        case "all_places_map":
            return .postOrStash(navName: "NavigateToAllPlacesMap", pending: "all-places-map", object: nil)

        case "create_wallet":
            return .postOrStash(navName: "NavigateToCreateWallet", pending: "create-wallet", object: nil)

        case ProximityNotificationScheduler.notificationType:
            guard let placeId, !placeId.isEmpty else { return nil }
            return .proximityCheckIn(placeId: placeId)

        case "favcoin_claim_settled":
            return .piggyBank

        case "new_follower", "user_followed":
            return actorId(userInfo).map { .userProfile(id: $0) }

        case "video_uploaded", "video_liked", "moment_uploaded", "moment_liked", "moment_tag":
            if let videoId = videoId(userInfo) { return .video(id: videoId) }
            return placeId.map { .place(id: $0, showComments: nil) }

        case "store_claim", "store_claim_approved":
            return .meTab

        default:
            // Unknown type: route on whatever data is present, in the old order.
            if let activityId { return .activity(id: activityId) }
            if let circleId { return .circle(id: circleId, showComments: nil) }
            if let placeId { return .place(id: placeId, showComments: nil) }
            if let conversationId { return .conversation(id: conversationId) }
            if let videoId = videoId(userInfo) { return .video(id: videoId) }
            if let actor = actorId(userInfo) { return .userProfile(id: actor) }
            if let deepLink = userInfo["deepLink"] as? String, let url = URL(string: deepLink), url.scheme == "circles" {
                return .deepLink(url)
            }
            return nil
        }
    }

    /// A data field, wherever the sender put it (same shapes as `type(in:)`).
    static func string(_ key: String, in userInfo: [AnyHashable: Any]) -> String? {
        if let value = userInfo[key] as? String, !value.isEmpty { return value }
        if let custom = userInfo["customData"] as? [String: Any], let value = custom[key] as? String, !value.isEmpty { return value }
        if let data = userInfo["data"] as? [String: Any], let value = data[key] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func actorId(_ userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["fromUserId"] as? String) ?? (userInfo["actorId"] as? String)
    }

    private static func videoId(_ userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["videoId"] as? String) ?? (userInfo["momentId"] as? String)
    }
}
