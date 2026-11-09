import Foundation

/// Which sections and rows the store-owner page shows, in order, and which of
/// them are Business-tier. Pure: store facts in, layout out — so the free vs
/// Business locks and the online-store trimming are table-tested rather than
/// computed from row offsets inside the controller.
enum VenueManageLayout {

    enum Section: Equatable {
        /// Orders waiting, first, while the store takes orders (2026-10-23)
        case ordersNow
        case glance
        /// What the page shows: details, hours, photos, buttons (all free)
        case placePage
        /// The menu and everything that takes orders from it (2026-11-06)
        case menuOrdering
        /// Points and the offers customers spend them on
        case loyalty
        /// Who shops here and what they tell you
        case customers
        case announcements
        /// Every printed or written code: register card, window sticker,
        /// NFC stickers, loyalty codes (2026-11-06)
        case codes
        case team
        case more
    }

    enum Row: Equatable {
        // At a glance
        case statTiles
        case fullStats
        /// Who's new, who came back, busiest times, the FavCircles score, reviews to answer (2026-11-09)
        case insights
        case savers
        case followers
        case activity
        // Your place page
        case viewPage
        /// Name, category, description, phone, website, address (free; the
        /// place page's tap-to-edit moved here 2026-10-23)
        case details
        case hours
        /// The place's one photo library: arrange, cover, remove (free)
        case photos
        case storefrontButtons
        case menu
        /// The whole menu, sections of items; scan the printed one (2026-10-20)
        case fullMenu
        /// Order ahead from the menu, pay at pickup (2026-10-20)
        case orders
        case onlineOrdering
        /// The store's web page, order.favcircles.com/<slug>: link it from the
        /// store's own site (2026-10-28)
        case orderPage
        case gallery
        // Loyalty program
        case earnRate
        /// Owner-set points for saving the store after a register scan (2026-10-30)
        case savePoints
        /// Delivery orders earn points from their receipt: the setting and the queue (2026-11-06)
        case deliveryOrders
        case offer(Int)
        case addOffer
        case showRegisterCard
        case replaceRegisterCard
        case loyaltyCodes
        /// Every reward redeemed here: given, open, or points back (2026-11-01)
        case rewardsUsed
        /// Who earns here: purchases, rewards, last visit; Remove from rewards (2026-11-02)
        case customers
        /// Stars and notes customers sent only to the team (2026-11-02)
        case feedback
        // Announcements
        case announcement(Int)
        case addAnnouncement
        // Window sticker
        case showWindowSticker
        /// Write the window link onto NFC stickers, taps per sticker (2026-11-01)
        case nfcStickers
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
        /// Order ahead is on: Orders leads the screen (off, Online ordering
        /// in "Menu & ordering" is the way in)
        var orderingOn = false
    }

    /// Wes, 2026-11-06: the old screen mixed the menu, ordering and buttons in
    /// one group and put codes and customer lists under Loyalty. Each tool now
    /// sits in exactly one group named for what the owner is doing.
    static func sections(_ facts: Facts) -> [(section: Section, rows: [Row])] {
        let physical = !facts.isVirtual

        var glance: [Row] = []
        if facts.hasStats { glance.append(.statTiles) }
        glance += [.fullStats, .insights, .activity]

        var placePage: [Row] = []
        if facts.hasPlace { placePage += [.viewPage, .details] }
        if facts.hasPlace && physical { placePage.append(.hours) }
        // No place page (online-only store): its own storefront gallery
        placePage.append(facts.hasPlace ? .photos : .gallery)
        placePage.append(.storefrontButtons)

        // Ordering off: the Online ordering row is the way in (Orders opened
        // the same settings screen, so it isn't listed twice)
        var menuOrdering: [Row] = [.fullMenu, .menu, .onlineOrdering]
        if physical { menuOrdering.append(.orderPage) }

        var loyalty: [Row] = [.earnRate]
        if physical { loyalty += [.savePoints, .deliveryOrders] }
        loyalty += (0..<facts.offerCount).map { Row.offer($0) }
        loyalty += [.addOffer, .rewardsUsed]

        let customers: [Row] = [.customers, .savers, .followers, .feedback]

        var announcements = (0..<facts.announcementCount).map { Row.announcement($0) }
        announcements.append(.addAnnouncement)

        let codes: [Row] = physical
            ? [.showRegisterCard, .showWindowSticker, .nfcStickers, .loyaltyCodes, .emailStickers, .replaceRegisterCard]
            : [.loyaltyCodes]

        var result: [(Section, [Row])] = []
        if facts.orderingOn { result.append((.ordersNow, [.orders])) }
        result += [
            (.glance, glance),
            (.placePage, placePage),
            (.menuOrdering, menuOrdering),
            (.loyalty, loyalty),
            (.customers, customers),
            (.announcements, announcements),
            (.codes, codes),
            (.team, [.contactName, .contactEmail, .managers, .plan]),
            (.more, [.ownerGuide, .brandStorefront, .addBusiness])
        ]
        return result.map { (section: $0.0, rows: $0.1) }
    }

    /// Tools that need FavCircles Business for this store. Everything else —
    /// headline stats, the place page basics, buttons, the window sticker,
    /// team and plan — works on the free plan.
    static func isBusiness(_ row: Row) -> Bool {
        switch row {
        case .insights, .savers, .followers, .activity,
             .menu, .fullMenu, .orders, .onlineOrdering, .orderPage, .gallery,
             .earnRate, .savePoints, .deliveryOrders, .offer, .addOffer, .showRegisterCard, .replaceRegisterCard, .loyaltyCodes, .rewardsUsed, .customers,
             .announcement, .addAnnouncement:
            return true
        default:
            return false
        }
    }
}
