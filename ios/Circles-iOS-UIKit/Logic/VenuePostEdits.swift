import Foundation

/// An offer as the owner edits it: what's wrong with it (if anything), and
/// which fields actually changed so an edit only sends those.
struct VenueOfferEdit: Equatable {
    var title: String
    var pointsText: String
    var isActive: Bool

    struct Changes: Equatable {
        var title: String?
        var pointsCost: Int?
        var active: Bool?
        var isEmpty: Bool { title == nil && pointsCost == nil && active == nil }
    }

    init(title: String = "", pointsText: String = "", isActive: Bool = true) {
        self.title = title
        self.pointsText = pointsText
        self.isActive = isActive
    }

    init(offer: RewardOffer) {
        self.init(title: offer.title, pointsText: "\(offer.pointsCost)", isActive: offer.active != false)
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var pointsCost: Int? { Int(pointsText.trimmingCharacters(in: .whitespaces)) }

    /// Why it can't be saved yet, naming the field; nil when it can
    var problem: String? {
        if trimmedTitle.isEmpty { return "Add what the customer gets, like \u{201C}Free coffee\u{201D}." }
        guard let cost = pointsCost, cost > 0 else { return "Points must be a whole number above 0." }
        return nil
    }

    /// "About 4 visits at 25 points each" — how far away the reward feels
    static func visitsHint(pointsCost: Int?, earnRate: Int) -> String? {
        guard let cost = pointsCost, cost > 0, earnRate > 0 else { return nil }
        let visits = Int((Double(cost) / Double(earnRate)).rounded(.up))
        return visits == 1
            ? "One visit earns it at \(earnRate) points a visit."
            : "About \(visits) visits at \(earnRate) points each."
    }

    func changes(from offer: RewardOffer) -> Changes {
        var c = Changes()
        if trimmedTitle != offer.title { c.title = trimmedTitle }
        if let cost = pointsCost, cost != offer.pointsCost { c.pointsCost = cost }
        if isActive != (offer.active != false) { c.active = isActive }
        return c
    }
}

/// An announcement as the owner edits it. The expiry is a day: the post stays
/// up through the end of that day in the owner's time zone.
struct VenueAnnouncementEdit: Equatable {
    var title: String
    var message: String
    /// nil = no end date
    var endsOn: Date?

    struct Changes: Equatable {
        var title: String?
        var message: String?
        var expiresAt: String?
        var clearExpiry = false
        var isEmpty: Bool { title == nil && message == nil && expiresAt == nil && !clearExpiry }
    }

    init(title: String = "", message: String = "", endsOn: Date? = nil) {
        self.title = title
        self.message = message
        self.endsOn = endsOn
    }

    init(announcement: VenueAnnouncement) {
        self.init(title: announcement.title, message: announcement.message, endsOn: announcement.expiryDate)
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    func problem(now: Date = Date(), calendar: Calendar = .current) -> String? {
        if trimmedTitle.isEmpty { return "Add a headline, like \u{201C}Happy Hour\u{201D}." }
        if trimmedMessage.isEmpty { return "Add the details people see under the headline." }
        if let end = endsOn, Self.endOfDay(end, calendar: calendar) <= now {
            return "The end date has already passed. Pick a later day or turn off the end date."
        }
        return nil
    }

    /// ISO string for the last second of the chosen day, or nil for no end date
    func expiresAt(calendar: Calendar = .current) -> String? {
        endsOn.map { ISO8601DateFormatter().string(from: Self.endOfDay($0, calendar: calendar)) }
    }

    func changes(from announcement: VenueAnnouncement, calendar: Calendar = .current) -> Changes {
        var c = Changes()
        if trimmedTitle != announcement.title { c.title = trimmedTitle }
        if trimmedMessage != announcement.message { c.message = trimmedMessage }
        let before = announcement.expiryDate.map { calendar.startOfDay(for: $0) }
        let after = endsOn.map { calendar.startOfDay(for: $0) }
        if before != after {
            if after == nil { c.clearExpiry = true } else { c.expiresAt = expiresAt(calendar: calendar) }
        }
        return c
    }

    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
