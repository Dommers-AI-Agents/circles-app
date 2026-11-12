import Foundation

/// What a shared place's bubble shows (Wes, 2026-11-12: "like the Coach Mane
/// share — not a website link"). One bubble: a card with the key facts, and a
/// tap opens the place in FavCircles. Never the venue's website or a ticket
/// site, and never a block of text beside the link.
struct PlaceShareContent: Equatable {
    /// The card's headline and the bubble's title
    var title: String
    /// The small line above it: "Farmers market", "Event", "Deal at Sal's"
    var kicker: String
    /// When to go: "Sat 8 AM–1 PM", "Sat, Nov 15 · 7 PM"
    var when: String?
    /// Where it is
    var whereLine: String?
    /// One short extra: "Free", "From $25", "SNAP/EBT"
    var extra: String?
    var photoUrl: String?
    /// The SF Symbol drawn when there's no photo
    var symbol: String
}

/// Which link a share carries.
enum PlaceShareTarget: Equatable {
    /// A save or a venue record: `/place/<id>` opens it
    case place(id: String)
    /// Known to Google but not to FavCircles yet: make the venue record
    /// first, then share its id (a Google id alone opens nothing)
    case mint(googlePlaceId: String)
    /// Nothing that opens a place: the App Store link
    case appStore
}

enum PlaceShareCopy {
    /// A place page's own id works when it's someone's save (`addedBy` set)
    /// or a venue record. A page built from a Locals row has neither: its id
    /// is a Google id or a made-up "local-" one (2026-11-12: a shared market
    /// opened nothing).
    static func target(id: String, globalPlaceId: String?, googlePlaceId: String?, addedBy: String) -> PlaceShareTarget {
        let google = googlePlaceId.flatMap { $0.isEmpty ? nil : $0 }
        let isMadeUp = id.isEmpty || id == google || id.hasPrefix("local-")
        if !addedBy.isEmpty, !isMadeUp { return .place(id: id) }
        if let venue = globalPlaceId, !venue.isEmpty { return .place(id: venue) }
        if let google { return .mint(googlePlaceId: google) }
        return .appStore
    }

    static func content(for place: Place) -> PlaceShareContent {
        let hours = place.openingHours.flatMap { OpeningHoursFormatter.weekSummary($0) }
        let rating = place.rating.map { String(format: "★ %.1f", $0) }
        return PlaceShareContent(
            title: place.name,
            kicker: kicker(subcategory: place.subcategory) ?? place.category.displayName,
            when: hours,
            whereLine: nonEmpty(place.address),
            extra: rating,
            photoUrl: place.photos?.first(where: { !$0.isEmpty }),
            symbol: "mappin.circle.fill"
        )
    }

    static func content(for market: FarmersMarket) -> PlaceShareContent {
        PlaceShareContent(
            title: market.name,
            kicker: "Farmers market",
            when: nonEmpty(market.hoursSummary),
            whereLine: nonEmpty(market.address),
            extra: market.acceptsSnap == true ? "SNAP/EBT" : nil,
            photoUrl: market.photoUrl,
            symbol: "basket.fill"
        )
    }

    static func content(for event: NearbyEvent) -> PlaceShareContent {
        let place = [event.venueName, event.city].compactMap(nonEmpty).joined(separator: " · ")
        let price = event.isFree == true ? "Free" : NearbyEventFormatter.priceText(min: event.priceMin, currency: event.currency)
        return PlaceShareContent(
            title: event.name,
            kicker: event.isStoreEvent ? (event.sourceName.flatMap(nonEmpty) ?? "Event") : "Event",
            when: NearbyEventFormatter.dateLine(localDate: event.startLocalDate, localTime: event.startLocalTime),
            whereLine: place.isEmpty ? nonEmpty(event.venueAddress) : place,
            extra: price,
            photoUrl: event.imageUrl,
            symbol: event.source == "library" ? "books.vertical.fill" : "ticket.fill"
        )
    }

    /// A store's deal or news, on the store's card
    static func content(for item: SpecialItem) -> PlaceShareContent {
        let venue = item.venue
        switch item.kind {
        case .offer(let offer):
            return PlaceShareContent(title: offer.title, kicker: "Reward at \(venue.venueName)", when: nil,
                                     whereLine: nonEmpty(venue.placeAddress),
                                     extra: offer.pointsCost > 0 ? "\(offer.pointsCost) points" : nil,
                                     photoUrl: venue.photoUrl, symbol: "gift.fill")
        case .announcement(let news):
            return PlaceShareContent(title: news.title, kicker: venue.venueName, when: nonEmpty(news.message),
                                     whereLine: nonEmpty(venue.placeAddress), extra: nil,
                                     photoUrl: venue.photoUrl, symbol: "megaphone.fill")
        }
    }

    /// An event opens its venue's place page
    static func target(for event: NearbyEvent) -> PlaceShareTarget {
        if let venue = event.globalPlaceId, !venue.isEmpty { return .place(id: venue) }
        if let google = event.googlePlaceId, !google.isEmpty { return .mint(googlePlaceId: google) }
        return .appStore
    }

    /// A market opens its place page once Google knows it
    static func target(for market: FarmersMarket) -> PlaceShareTarget {
        if let google = market.googlePlaceId, !google.isEmpty { return .mint(googlePlaceId: google) }
        return .appStore
    }

    /// "farmers_market" → "Farmers market"; nil when there's nothing to show
    static func kicker(subcategory: String?) -> String? {
        guard let raw = subcategory?.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
