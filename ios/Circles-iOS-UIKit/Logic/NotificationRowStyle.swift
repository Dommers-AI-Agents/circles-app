import UIKit

/// The icon on a Notifications-list row, by push type.
enum NotificationRowStyle {
    struct Style: Equatable {
        let symbol: String
        let color: UIColor
    }

    static func style(for type: String) -> Style {
        switch type {
        case "place_like": return Style(symbol: "heart.fill", color: .systemRed)
        case "place_comment", "activity_comment": return Style(symbol: "bubble.left.fill", color: .systemBlue)
        case "activity_reaction": return Style(symbol: "hand.thumbsup.fill", color: .systemBlue)
        case "connection_request": return Style(symbol: "person.badge.plus.fill", color: Constants.Colors.primary)
        case "connection_accepted": return Style(symbol: "person.2.fill", color: Constants.Colors.primary)
        case "new_follower": return Style(symbol: "person.fill.checkmark", color: Constants.Colors.primary)
        case "new_message": return Style(symbol: "message.fill", color: .systemBlue)
        case "new_suggestion": return Style(symbol: "lightbulb.fill", color: .systemYellow)
        case "check_in", "check_in_response": return Style(symbol: "mappin.circle.fill", color: .systemGreen)
        case "moment_tag": return Style(symbol: "video.fill", color: .systemPurple)
        case "store_claim": return Style(symbol: "storefront.fill", color: .systemOrange)
        case "store_claim_approved": return Style(symbol: "storefront.fill", color: .systemGreen)
        case "milestone": return Style(symbol: "trophy.fill", color: .systemYellow)
        case "nextbar_round", "nextbar_result": return Style(symbol: "wineglass.fill", color: .systemPurple)
        case "postcard_order": return Style(symbol: "envelope.fill", color: .systemTeal)
        case "event_invite", "event_joined", "event_photos": return Style(symbol: "party.popper.fill", color: .systemPurple)
        case "fridgemail": return Style(symbol: "photo.on.rectangle.angled", color: .systemOrange)
        case "favcoin_claim_settled": return Style(symbol: "dollarsign.circle.fill", color: .systemGreen)
        case "did_you_know": return Style(symbol: "sparkles", color: .systemIndigo)
        case "care_silence": return Style(symbol: "exclamationmark.heart.fill", color: .systemRed)
        default:
            if type.hasPrefix("care_") { return Style(symbol: "heart.text.square.fill", color: .systemPink) }
            return Style(symbol: "bell.fill", color: .systemGray)
        }
    }
}
