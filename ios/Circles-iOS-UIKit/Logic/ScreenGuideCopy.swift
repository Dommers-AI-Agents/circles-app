import Foundation

/// Where the home tour's "Show me" can take someone, so the screen they land
/// on explains itself and offers a next step (Wes, 2026-11-07: Store Rewards
/// opened and the tour just stopped). Pure: the words, tested.
enum ScreenGuideKind: String {
    case rewards, checkIn, findPeople, profile, addPlace
    /// Their own place, right after adding it from a guide: what they can do with it
    case ownPlace
    /// "Show me how" QR guides (Scan Actions, 2026-11-11). Raw values are the
    /// server's `appGuide` (backend/config/scanGuides.js).
    case sharePlace, makeCircle, widgets
    /// A store owner's walkthrough: find the business and claim it
    case storeSetup
    /// Then, once it's theirs: Manage Store, points, a first reward, the QR
    case storeManage
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
        case .sharePlace:
            let name = placeName ?? "a place"
            return [
                Stop(title: "Share \(name)",
                     message: "Tap Share at the top. Send a link in a text, or pick Show QR to Save."),
                Stop(title: "Show QR to Save",
                     message: "Hold up your phone. Whoever scans it with their Camera sees the place, picks a circle and it's saved to their map. No app yet? It opens right there."),
                Stop(title: "A whole list, too",
                     message: "Open a circle or filter your Home map, then tap Share these places to make one QR for all of them.")
            ]
        case .makeCircle:
            return [
                Stop(title: "Make a circle",
                     message: "Tap + to start one: brunch spots, date nights, coffee. You choose who can see it."),
                Stop(title: "Fill it up",
                     message: "Open the circle and tap Add Place, or save a place from the map straight into it.")
            ]
        case .widgets:
            return [
                Stop(title: "Your widgets",
                     message: "Little apps inside FavCircles: water, habits, workouts, runs, postcards and more. Tap one to open it."),
                Stop(title: "Make it yours",
                     message: "Tap Manage to turn widgets on or off and put them in the order you like.")
            ]
        case .storeSetup:
            return [
                Stop(title: "Find your business",
                     message: "Search for your store by name, pick it, then tell us how to reach you."),
                Stop(title: "We check, then you're in",
                     message: "FavCircles confirms you own it, usually within a day. You'll get a notification, and Manage Store opens from your Me tab.")
            ]
        case .storeManage:
            let name = placeName ?? "your store"
            return [
                Stop(title: "Manage \(name)",
                     message: "Everything customers see about your store, and how they earn with you, lives here."),
                Stop(title: "Points",
                     message: "Choose what a visit or a purchase earns. Customers see their points in their app and in Apple Wallet."),
                Stop(title: "Your first reward",
                     message: "Add an offer: a free coffee at 100 points, or 10% off a first visit. You can change it any time."),
                Stop(title: "Put up your QR",
                     message: "Print the window sticker and the register card. Customers scan them to save your store and earn.")
            ]
        }
    }

    /// The last card of a guide someone scanned a QR for: no tour to go back
    /// to, so the buttons end it
    static func scanFinish(_ kind: ScreenGuideKind) -> Finish {
        switch kind {
        case .storeSetup:
            return Finish(title: nil, message: nil, next: nil, back: "Got it")
        default:
            return Finish(title: nil, message: nil, next: nil, back: "Done")
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
        case .sharePlace, .makeCircle, .widgets, .storeSetup, .storeManage:
            return scanFinish(kind)
        }
    }
}
