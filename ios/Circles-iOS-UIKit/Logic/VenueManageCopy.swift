import Foundation

/// Plain-language copy for the store-owner page: what each group is for (the
/// section header and the explanation behind its ⓘ), and the headline tiles.
enum VenueManageCopy {

    struct Header: Equatable {
        let title: String
        let explanation: String
    }

    static func header(_ section: VenueManageLayout.Section, isVirtual: Bool = false) -> Header {
        switch section {
        case .glance:
            return Header(
                title: "At a glance",
                explanation: "Your store's headline numbers. Tap Stats & Insights for monthly trends. With FavCircles Business you can also see who saved your place, who follows it, and every visit and redemption.")
        case .placePage:
            return Header(
                title: "Your place page",
                explanation: isVirtual
                    ? "What customers see when they open your store: buttons that make money (Reserve, Order, Catering, Book — free), and with FavCircles Business your menu, featured items and your own photos."
                    : "What customers see when they open your place: your hours and cover photo, buttons that make money (Reserve, Order, Catering, Book — free), and with FavCircles Business your menu, featured items and your own photos.")
        case .loyalty:
            return Header(
                title: "Loyalty program",
                explanation: isVirtual
                    ? "Customers earn points with your loyalty codes and spend them on your offers. Pack a code into every order; they redeem it in the app and follow your store."
                    : "Customers scan your register card after buying something to earn points (once a day), then spend them on your offers at the counter. Loyalty codes work the same way for shipped orders and event handouts.")
        case .announcements:
            return Header(
                title: "Announcements",
                explanation: "Short updates shown on your place's page and in your followers' feeds — deals, happy hours, events. Expired announcements hide automatically.")
        case .windowSticker:
            return Header(
                title: "Window sticker",
                explanation: "Print this code and put it in your window. Customers scan it to save your place in FavCircles and start earning points. Free for every store.")
        case .team:
            return Header(
                title: "Owner & team",
                explanation: "How FavCircles reaches you about this store, who helps you run it, and your plan. Monthly reports and printable QR codes go to the contact email.")
        case .more:
            return Header(
                title: "Help & more",
                explanation: "The store owner video guide, your brand's storefront on your profile, and claiming another location.")
        }
    }

    static func footer(_ section: VenueManageLayout.Section, isVirtual: Bool = false) -> String? {
        switch section {
        case .placePage:
            return "Buttons are free for every store. Menu, featured items and photos come with FavCircles Business."
        case .loyalty:
            return isVirtual
                ? nil
                : "Making a new register card turns the printed one off immediately — only do it if the card leaked or was lost."
        case .windowSticker:
            return "The email has both printable codes: the window sticker and the register card."
        default:
            return nil
        }
    }

    /// The four numbers an owner checks first. Counters the payload omits read 0.
    static func statTiles(_ stats: AdminVenueStats) -> [VenueAdminCopy.StatTile] {
        [
            .init(title: "Visits", value: stats.visits ?? 0, caption: "Register-card check-ins", monthNote: nil),
            .init(title: "Redeemed", value: stats.redemptions ?? 0, caption: "Offers cashed in", monthNote: nil),
            .init(title: "Saves", value: stats.saves ?? 0, caption: "Saved your place", monthNote: nil),
            .init(title: "Followers", value: stats.followers ?? 0, caption: "Get your updates", monthNote: nil)
        ]
    }

    static func managersLine(_ count: Int) -> String {
        switch count {
        case 0: return "Invite someone to run this store with you"
        case 1: return "1 manager helps run this store"
        default: return "\(count) managers help run this store"
        }
    }

    static func planLine(premium: Bool?) -> (title: String, detail: String) {
        switch premium {
        case true?:
            return ("FavCircles Business", "Active for this store · Manage in the App Store")
        case false?:
            return ("Free plan", "See what Business unlocks for this store")
        case nil:
            return ("Plan", "Checking…")
        }
    }
}
