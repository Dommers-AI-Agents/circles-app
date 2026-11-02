import Foundation

/// Every finished action and every empty screen offers a next tap (Wes,
/// 2026-11-02: "never end on a page with no suggested next step"; the scan →
/// points → My Rewards flow is the model). One step = one button: an id for
/// tracking and its words. Which steps follow which moment lives here, so the
/// wording stays the same everywhere. At most two per moment.
struct NextStep: Equatable {
    let id: String
    let title: String

    static let seeOnMap = NextStep(id: "see_on_map", title: "See it on my map")
    static let addPlace = NextStep(id: "add_place", title: "Add a place")
    static let addMoreLikeIt = NextStep(id: "add_more_like_it", title: "Add more like it")
    static let postMoment = NextStep(id: "post_moment", title: "Post a moment here")
    static let scanForPoints = NextStep(id: "scan_for_points", title: "Scan for points")
    static let myCheckIns = NextStep(id: "my_check_ins", title: "My check-ins")
    static let findPeople = NextStep(id: "find_people", title: "Find people to follow")
    static let seeTheirMap = NextStep(id: "see_their_map", title: "See their map")
    static let seeMoments = NextStep(id: "see_moments", title: "See it in Moments")
    static let shareIt = NextStep(id: "share_it", title: "Share it")
    static let myRewards = NextStep(id: "my_rewards", title: "My Rewards")
    static let previewStore = NextStep(id: "preview_store", title: "See what customers see")
    static let printCodes = NextStep(id: "print_codes", title: "Print my QR codes")
    static let explore = NextStep(id: "explore", title: "Explore places nearby")
    static let openChat = NextStep(id: "open_chat", title: "Open the chat")

    /// What follows each moment
    enum Moment: String {
        case checkedIn, checkedInAtRewardsStore, momentPosted, followed
        case storeOffersSaved, storeDetailsSaved, circleSaved, suggestionSent, connectionAccepted
    }

    static func after(_ moment: Moment) -> [NextStep] {
        switch moment {
        case .checkedIn: return [.postMoment, .myCheckIns]
        case .checkedInAtRewardsStore: return [.scanForPoints, .postMoment]
        case .momentPosted: return [.seeMoments, .shareIt]
        case .followed: return [.seeTheirMap, .findPeople]
        case .storeOffersSaved, .storeDetailsSaved: return [.previewStore, .printCodes]
        case .circleSaved: return [.addPlace, .shareIt]
        case .suggestionSent: return [.openChat, .explore]
        case .connectionAccepted: return [.seeTheirMap, .openChat]
        }
    }
}
