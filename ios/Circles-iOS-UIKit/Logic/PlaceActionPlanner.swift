import Foundation

/// One button in the place page's action row.
struct PlaceAction: Equatable {
    enum Kind: Equatable {
        /// The store's menu in the app (ordering on when the store takes orders)
        case inAppMenu(ordering: Bool)
        /// A web page: the owner's link (menu, reserve, order, catering, book) or the website
        case link(String)
        /// A partner group from the catalog (Delivery, Reservations, Ride…)
        case partner(groupId: String)
    }
    let kind: Kind
    let title: String
    let icon: String
}

/// Which buttons a place gets, and in what order (Wes, 2026-11-06: "How can
/// we intelligently prioritize… Ilios isn't the kind that takes reservations.
/// A menu button would likely be more valuable.").
///
/// - The store's own choices come first and always show: Menu, then its
///   Reserve / Order / Catering / Book links.
/// - Menu: in-app ordering → the store's in-app menu → the owner's menu link →
///   their published menu link → the website. Food and drink places only,
///   unless the store set one up itself.
/// - The automatic partner buttons fill the row up to three, and only when
///   they likely apply: Reservations when Google says it takes them (or it's
///   $$$ with no answer), Delivery unless Google says no, Ride only when
///   you're more than 3 miles away. An owner can turn each one off; an owner's
///   Reserve link replaces the OpenTable button.
struct PlaceActionPlanner {
    struct OwnerButtons: Equatable {
        var reserve: String?
        var order: String?
        var catering: String?
        var book: String?
        var menu: String?
        /// Automatic buttons the owner turned off: "delivery", "reserve", "ride"
        var hidden: Set<String> = []
    }

    var category: PlaceCategory
    var delivery: Bool?
    var takeout: Bool?
    var reservable: Bool?
    var priceLevel: PriceLevel?
    var website: String?
    /// Meters from the viewer; nil when unknown
    var distanceMeters: Double?
    var owner: OwnerButtons?
    /// The store has its full menu in the app
    var hasInAppMenu = false
    /// …and takes orders from it
    var takesOrders = false
    /// The store's published menu link (a Business storefront block)
    var publishedMenuLink: String?
    /// Partner groups already eligible for this place (category, providers)
    var partnerGroups: [PartnerActionGroup] = []

    static let automaticLimit = 3
    static let maxButtons = 6
    /// Close enough that Directions is the answer, not a ride
    static let rideMinimumMeters = 4_828.0

    private static let foodAndDrink: Set<PlaceCategory> = [.restaurant, .cafe, .bar]

    func actions() -> [PlaceAction] {
        guard category != .home, category != .work else { return [] }
        var out: [PlaceAction] = []
        if let menu = menuAction() { out.append(menu) }
        if let owner {
            let links: [(String?, String, String)] = [
                (owner.reserve, "Reserve", "calendar.badge.clock"),
                (owner.order, "Order", "bag"),
                (owner.catering, "Catering", "fork.knife"),
                (owner.book, "Book", "calendar")
            ]
            for (url, title, icon) in links {
                if let url = Self.webAddress(url) { out.append(PlaceAction(kind: .link(url), title: title, icon: icon)) }
            }
        }
        for group in partnerGroups.sorted(by: { rank($0) < rank($1) }) where out.count < Self.automaticLimit {
            guard shows(group) else { continue }
            out.append(PlaceAction(kind: .partner(groupId: group.id), title: group.title, icon: group.icon))
        }
        return Array(out.prefix(Self.maxButtons))
    }

    private func menuAction() -> PlaceAction? {
        let menu = { (kind: PlaceAction.Kind) in PlaceAction(kind: kind, title: "Menu", icon: "menucard") }
        if hasInAppMenu { return menu(.inAppMenu(ordering: takesOrders)) }
        if let link = Self.webAddress(owner?.menu) { return menu(.link(link)) }
        if let link = Self.webAddress(publishedMenuLink) { return menu(.link(link)) }
        guard Self.foodAndDrink.contains(category), let site = Self.webAddress(website) else { return nil }
        return menu(.link(site))
    }

    /// Strong signals first: a place that takes reservations books before it delivers
    private func rank(_ group: PartnerActionGroup) -> Int {
        switch group.id {
        case "reserve": return reservable == true ? 0 : 2
        case "delivery": return 1
        case "ride": return 9
        default: return 5 + group.order
        }
    }

    private func shows(_ group: PartnerActionGroup) -> Bool {
        if owner?.hidden.contains(group.id) == true { return false }
        switch group.id {
        case "reserve":
            if Self.webAddress(owner?.reserve) != nil { return false }
            if let reservable { return reservable }
            return (priceLevel?.rawValue ?? 0) >= PriceLevel.expensive.rawValue
        case "delivery":
            return !(delivery == false && takeout == false)
        case "ride":
            guard let distanceMeters else { return false }
            return distanceMeters >= Self.rideMinimumMeters
        default:
            return true
        }
    }

    /// "ilios.com/menu" → "https://ilios.com/menu"; nil for blanks and non-web schemes
    static func webAddress(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            guard !lower.contains("://"), !lower.hasPrefix("mailto:"), !lower.hasPrefix("tel:") else { return nil }
            s = "https://" + s
        }
        guard let url = URL(string: s), url.host?.isEmpty == false else { return nil }
        return s
    }
}
