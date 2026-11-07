import Foundation

/// Where the home tour's "Show me" can take someone, so the screen they land
/// on explains itself and offers a next step (Wes, 2026-11-07: Store Rewards
/// opened and the tour just stopped). Pure: the words, tested.
enum ScreenGuideKind: String {
    case rewards, checkIn, findPeople, profile, addPlace
    /// Their own place, right after adding it from a guide: what they can do with it
    case ownPlace
}

enum ScreenGuideCopy {
    struct Stop: Equatable {
        let title: String
        let message: String
    }

    /// The last card. With no title, the buttons go on the last stop
    /// instead (a one-bubble screen needs no extra card).
    struct Finish: Equatable {
        let title: String?
        let message: String?
        /// The link to the next thing to do, when there is one
        let next: String?
        /// The button that goes back to Home's tour
        let back: String
    }

    static let addPlaceNext = "Add a place you love"

    static func stops(_ kind: ScreenGuideKind, placeName: String? = nil) -> [Stop] {
        switch kind {
        case .rewards:
            return [
                Stop(title: "Store Rewards",
                     message: "Shops with a FavCircles sticker give rewards. Save one, scan the card at the register when you buy something, and your points and the shop's offers show up here."),
                Stop(title: "Have a code?",
                     message: "Stores and events hand out codes. Redeem one here for points at that store."),
                Stop(title: "Your Piggy Bank",
                     message: "FavCoins are for building FavCircles: adding places, making circles, checking in, adding photos and inviting friends. They're real coins on the Cactus blockchain that you can send to your own wallet.")
            ]
        case .checkIn:
            return [Stop(title: "Check in",
                         message: "Pick where you are. Each check-in goes in your history, earns FavCoins, and at stores with rewards it counts as a visit.")]
        case .findPeople:
            return [Stop(title: "Find your people",
                         message: "People near you and people who love the same places. Follow someone and their favorite places show up on your map.")]
        case .profile:
            return [Stop(title: "Your profile",
                         message: "Your map, your circles and your moments. Share it so friends can follow you and see where you love to go.")]
        case .addPlace:
            return [Stop(title: "Add a place you love",
                         message: "Search for the spot you can't stop recommending: a coffee shop, a restaurant, a park. Pick it and save it to a circle.")]
        case .ownPlace:
            let name = placeName ?? "your place"
            return [
                Stop(title: "Check in at \(name)",
                     message: "When you're there, tap Check In. It builds your history and earns FavCoins (and store points where there are rewards)."),
                Stop(title: "Add your photos",
                     message: "Your photos of \(name) help everyone see it, and the first one you add earns FavCoins."),
                Stop(title: "Directions, call, website",
                     message: "Everything you need to go: directions by name and address, the phone, the website and the menu."),
                Stop(title: "Share it",
                     message: "Tap Share at the top to send \(name) to a friend. They can save it to their own map in one tap.")
            ]
        }
    }

    static func finish(_ kind: ScreenGuideKind) -> Finish {
        switch kind {
        case .rewards:
            return Finish(title: "Start with a place you love",
                          message: "Saving the place you love most is the heart of FavCircles, and it earns your first FavCoins.",
                          next: addPlaceNext, back: "Back to the tour")
        case .ownPlace:
            return Finish(title: "That's your first pin",
                          message: "Add a few more places you love and your map starts to look like you.",
                          next: nil, back: "Back to the tour")
        case .profile:
            return Finish(title: "You're all set",
                          message: "Start with a place you love. The tour is in Help whenever you want it again.",
                          next: addPlaceNext, back: "Back to Home")
        case .checkIn, .findPeople:
            return Finish(title: nil, message: nil, next: addPlaceNext, back: "Back to the tour")
        case .addPlace:
            // They're about to add one: the place page takes it from there
            return Finish(title: nil, message: nil, next: nil, back: "Got it")
        }
    }
}
