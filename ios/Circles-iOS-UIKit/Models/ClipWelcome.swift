import Foundation

/// What the App Clip hands the app about the store it was opened at (see
/// ClipHandoff.Welcome in the Circles-Clip target — keep the two in step):
/// the app's first launch opens that store's page with a welcome sheet.
struct ClipWelcome: Codable {
    struct Offer: Codable {
        let title: String
        let pointsCost: Int
    }

    let code: String
    let kind: String?
    let venue: RewardVenue
    let awardedPoints: Int?
    let venueBalance: Int?
    let earnRate: Int?
    let offers: [Offer]
    let nextRewardLine: String?
    let alreadySaved: Bool?

    private static let stashKey = "clipWelcome"

    /// Held until the tab bar is up (adoption runs before the login state is read)
    static func stash(_ welcome: ClipWelcome) {
        if let data = try? JSONEncoder().encode(welcome) {
            UserDefaults.standard.set(data, forKey: stashKey)
        }
    }

    static func takeStashed() -> ClipWelcome? {
        guard let data = UserDefaults.standard.data(forKey: stashKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: stashKey)
        return try? JSONDecoder().decode(ClipWelcome.self, from: data)
    }
}
