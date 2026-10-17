import Foundation

/// What a store owner is told after posting a new offer, announcement or
/// event: who it alerted (followers who turned on the store's bell, at most
/// once a day). The post itself always reaches the feed and Locals.
struct StoreAlertResult: Codable, Equatable {
    let audience: Int
    let sent: Int
    let throttled: Bool
}

enum StoreAlertCopy {
    /// nil when nobody has alerts on: nothing to report beyond "posted".
    static func line(_ result: StoreAlertResult?) -> String? {
        guard let result, result.audience > 0 else { return nil }
        let people = result.audience == 1 ? "1 follower" : "\(result.audience) followers"
        if result.throttled {
            return "Posted. You already alerted your \(people) today, so this one shows in their feed without a notification."
        }
        return "Posted, and sent as an alert to \(people) who turned on alerts."
    }
}
