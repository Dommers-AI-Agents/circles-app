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
/// up through the end of that day in the owner's time zone. An event (a time
/// it happens) takes itself down when it's over instead, and shows under
/// "Happening nearby" on the Local tab.
struct VenueAnnouncementEdit: Equatable {
    var title: String
    var message: String
    /// nil = no end date
    var endsOn: Date?
    /// The event's start; nil = a plain announcement
    var eventStart: Date?
    /// Optional end time of the event
    var eventEnd: Date?
    var eventIsFree: Bool

    struct Changes: Equatable {
        var title: String?
        var message: String?
        var expiresAt: String?
        var clearExpiry = false
        var event: EventPayload?
        var clearEvent = false
        var isEmpty: Bool { title == nil && message == nil && expiresAt == nil && !clearExpiry && event == nil && !clearEvent }
    }

    /// What the server stores for an event
    struct EventPayload: Equatable {
        let startsAt: String
        let endsAt: String?
        let localDate: String
        let localTime: String
        let isFree: Bool

        var dictionary: [String: Any] {
            var body: [String: Any] = ["startsAt": startsAt, "localDate": localDate, "localTime": localTime, "isFree": isFree]
            body["endsAt"] = endsAt ?? NSNull()
            return body
        }
    }

    init(title: String = "", message: String = "", endsOn: Date? = nil,
         eventStart: Date? = nil, eventEnd: Date? = nil, eventIsFree: Bool = true) {
        self.title = title
        self.message = message
        self.endsOn = endsOn
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.eventIsFree = eventIsFree
    }

    init(announcement: VenueAnnouncement) {
        let event = announcement.event
        self.init(title: announcement.title, message: announcement.message,
                  endsOn: event == nil ? announcement.expiryDate : nil,
                  eventStart: event?.startDate, eventEnd: event?.endDate,
                  eventIsFree: event?.isFree ?? true)
    }

    var isEvent: Bool { eventStart != nil }

    /// The event as the server stores it, in the owner's own clock
    func eventPayload(calendar: Calendar = .current) -> EventPayload? {
        guard let start = eventStart else { return nil }
        let iso = ISO8601DateFormatter()
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        return EventPayload(
            startsAt: iso.string(from: start),
            endsAt: eventEnd.map { iso.string(from: $0) },
            localDate: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            localTime: String(format: "%02d:%02d:00", parts.hour ?? 0, parts.minute ?? 0),
            isFree: eventIsFree
        )
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    func problem(now: Date = Date(), calendar: Calendar = .current) -> String? {
        if trimmedTitle.isEmpty { return "Add a headline, like \u{201C}Happy Hour\u{201D}." }
        if trimmedMessage.isEmpty { return "Add the details people see under the headline." }
        if let start = eventStart {
            if start < now.addingTimeInterval(-3600) { return "The event's start time has passed. Pick a later time." }
            if let end = eventEnd, end <= start { return "The event has to end after it starts." }
            return nil
        }
        if let end = endsOn, Self.endOfDay(end, calendar: calendar) <= now {
            return "The end date has already passed. Pick a later day or turn off the end date."
        }
        return nil
    }

    /// ISO string for the last second of the chosen day, or nil for no end
    /// date (an event's expiry is set by the server from its times)
    func expiresAt(calendar: Calendar = .current) -> String? {
        guard !isEvent else { return nil }
        return endsOn.map { ISO8601DateFormatter().string(from: Self.endOfDay($0, calendar: calendar)) }
    }

    func changes(from announcement: VenueAnnouncement, calendar: Calendar = .current) -> Changes {
        var c = Changes()
        if trimmedTitle != announcement.title { c.title = trimmedTitle }
        if trimmedMessage != announcement.message { c.message = trimmedMessage }
        let newEvent = eventPayload(calendar: calendar)
        let oldEvent = announcement.event
        if let newEvent {
            // Minute precision: the pickers carry stray seconds
            func sameMinute(_ a: Date?, _ b: Date?) -> Bool {
                switch (a, b) {
                case (nil, nil): return true
                case let (a?, b?): return abs(a.timeIntervalSince(b)) < 60
                default: return false
                }
            }
            let same = oldEvent.map {
                sameMinute($0.startDate, eventStart) && sameMinute($0.endDate, eventEnd) && ($0.isFree ?? true) == eventIsFree
            } ?? false
            if !same { c.event = newEvent }
            return c
        }
        if oldEvent != nil { c.clearEvent = true }
        let before = (oldEvent == nil ? announcement.expiryDate : nil).map { calendar.startOfDay(for: $0) }
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
