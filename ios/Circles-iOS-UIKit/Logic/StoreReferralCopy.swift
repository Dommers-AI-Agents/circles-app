import Foundation

/// Bring a friend: the customer's invite and the owner's settings. Pure.
enum StoreReferralCopy {

    /// The button on the store's page: "Invite a friend · you both get points"
    static func inviteButton(_ referral: StoreReferral) -> String {
        referral.referrerPoints == referral.friendPoints
            ? "Invite a friend · you both get \(referral.referrerPoints) points"
            : "Invite a friend · you get \(referral.referrerPoints), they get \(referral.friendPoints)"
    }

    /// The one-bubble link's title
    static func shareTitle(storeName: String, referral: StoreReferral) -> String {
        "Join me at \(storeName) on FavCircles — \(referral.friendPoints) bonus points on your first visit"
    }

    // MARK: Owner

    static func summary(_ settings: StoreReferralSettings) -> String {
        settings.enabled
            ? "On · inviter \(settings.referrerPoints) pts, friend \(settings.friendPoints) pts"
            : "Off: customers invite friends with your window link; both earn points"
    }

    static func statsLine(_ stats: StoreReferralStats?) -> String {
        guard let stats, stats.friendsBrought > 0 else { return "No friends brought in yet" }
        let month = stats.thisMonth > 0 ? " · \(stats.thisMonth) this month" : ""
        return "\(stats.friendsBrought) friend\(stats.friendsBrought == 1 ? "" : "s") brought in\(month) · \(stats.pointsPaid) points paid"
    }

    static let explanation = "Customers share your window link with ?ref on it. When the friend's first purchase is scanned at the register, the inviter and the friend both get the points you set here. Honor-system points, like the rest of rewards; at most 20 rewarded invites per person a month."

    static func pointsLine(_ points: Int) -> String { "\(points) points" }
}
