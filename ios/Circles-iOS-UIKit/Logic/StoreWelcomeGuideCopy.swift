import Foundation

/// The store tour on its page, the first time the app opens after someone
/// joined at that store in the App Clip (Wes, 2026-11-26: "Upon downloading
/// the App they should be brought to the store place view and shown around
/// the store. The new user can also then continue to learn more about the
/// app like a normal user"). Their page, the bell they turned on, their
/// rewards where the store's are live; then the usual first run. Pure.
enum StoreWelcomeGuideCopy {
    static func stops(storeName: String, rewardsLive: Bool) -> [ScreenGuideCopy.Stop] {
        var stops = [
            ScreenGuideCopy.Stop(title: "Welcome to \(storeName)\u{2019}s page",
                                 message: "Everything about \(storeName) lives here: photos, hours, the menu and what people say about it. It\u{2019}s saved on your map."),
            ScreenGuideCopy.Stop(title: "You\u{2019}re connected",
                                 message: "The bell is on, so \(storeName)\u{2019}s new specials, events and news come to you, at most one a day. Tap it any time to stop.")
        ]
        if rewardsLive {
            stops.append(ScreenGuideCopy.Stop(title: "Your rewards",
                                              message: "Your points at \(storeName) and what they buy. Scan the code at the register on each visit to earn more."))
        }
        return stops
    }

    /// Then the rest of FavCircles; Skip goes there too
    static let finish = ScreenGuideCopy.Finish(
        title: "Now, your own map",
        message: "FavCircles keeps every place you love in one map, and shows you where your friends go. Here\u{2019}s how it works.",
        next: nil,
        back: "Keep exploring")
}
