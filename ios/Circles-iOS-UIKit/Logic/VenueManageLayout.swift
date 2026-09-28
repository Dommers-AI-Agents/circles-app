import Foundation

/// Which sections and rows the store-owner page shows, in order, and which of
/// them are Business-tier. Pure: store facts in, layout out — so the free vs
/// Business locks and the online-store trimming are table-tested rather than
/// computed from row offsets inside the controller.
enum VenueManageLayout {

    enum Section: Equatable {
        case glance
        case placePage
        case loyalty
        case announcements
        case windowSticker
        case team
        case more
    }

    enum Row: Equatable {
        // At a glance
        case statTiles
        case fullStats
        case savers
        case followers
        case activity
        // Your place page
        case viewPage
        case hours
        case coverPhoto
        case storefrontButtons
        case menu
        case gallery
        // Loyalty program
        case earnRate
        case offer(Int)
        case addOffer
        case showRegisterCard
        case replaceRegisterCard
        case loyaltyCodes
        // Announcements
        case announcement(Int)
        case addAnnouncement
        // Window sticker
        case showWindowSticker
        case emailStickers
        // Owner & team
        case contactName
        case contactEmail
        case managers
        case plan
        // Help & more
        case ownerGuide
        case brandStorefront
        case addBusiness
    }

    struct Facts: Equatable {
        /// Online-only brand store: no window, no counter, no map pin
        var isVirtual = false
        /// Linked to a place record (public page, hours, cover photo)
        var hasPlace = true
        /// Headline counters arrived with the venue payload
        var hasStats = true
        var offerCount = 0
        var announcementCount = 0
    }

    static func sections(_ facts: Facts) -> [(section: Section, rows: [Row])] {
        let physical = !facts.isVirtual

        var glance: [Row] = []
        if facts.hasStats { glance.append(.statTiles) }
        glance += [.fullStats, .savers, .followers, .activity]

        var placePage: [Row] = []
        if facts.hasPlace { placePage.append(.viewPage) }
        if facts.hasPlace && physical { placePage += [.hours, .coverPhoto] }
        placePage += [.storefrontButtons, .menu, .gallery]

        var loyalty: [Row] = [.earnRate]
        loyalty += (0..<facts.offerCount).map { Row.offer($0) }
        loyalty.append(.addOffer)
        if physical { loyalty += [.showRegisterCard, .replaceRegisterCard] }
        loyalty.append(.loyaltyCodes)

        var announcements = (0..<facts.announcementCount).map { Row.announcement($0) }
        announcements.append(.addAnnouncement)

        var result: [(Section, [Row])] = [
            (.glance, glance),
            (.placePage, placePage),
            (.loyalty, loyalty),
            (.announcements, announcements)
        ]
        if physical {
            result.append((.windowSticker, [.showWindowSticker, .emailStickers]))
        }
        result.append((.team, [.contactName, .contactEmail, .managers, .plan]))
        result.append((.more, [.ownerGuide, .brandStorefront, .addBusiness]))
        return result.map { (section: $0.0, rows: $0.1) }
    }

    /// Tools that need FavCircles Business for this store. Everything else —
    /// headline stats, the place page basics, buttons, the window sticker,
    /// team and plan — works on the free plan.
    static func isBusiness(_ row: Row) -> Bool {
        switch row {
        case .savers, .followers, .activity,
             .menu, .gallery,
             .earnRate, .offer, .addOffer, .showRegisterCard, .replaceRegisterCard, .loyaltyCodes,
             .announcement, .addAnnouncement:
            return true
        default:
            return false
        }
    }
}
