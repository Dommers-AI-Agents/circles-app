import Foundation

/// The rules behind Profile › Activity: which filter chips exist, how rows
/// are worded, and how a page of rows becomes day sections with the day's
/// social actions (likes, comments, follows) collapsed into one line so
/// check-ins and moments stay visible. Pure; no UIKit.
enum ProfileActivityTimeline {
    enum Filter: String, CaseIterable {
        case all, checkins, places, moments, sent

        var title: String {
            switch self {
            case .all: return "All"
            case .checkins: return "Check-ins"
            case .places: return "Places"
            case .moments: return "Moments"
            // Server category "sent": postcards, Fridge Mail and place
            // suggestions. A bare "Sent" didn't say what was in it.
            case .sent: return "Postcards & suggestions"
            }
        }

        /// What the timeline says when this filter has nothing.
        var emptyMessage: String {
            switch self {
            case .all: return "Nothing yet. Check in, add a place or post a moment and it lands here."
            case .checkins: return "No check-ins yet. Check in at a place and it shows up here."
            case .places: return "No places yet. Places you add to your circles show up here."
            case .moments: return "No moments yet. Moments you post show up here."
            case .sent: return "Nothing sent yet. Postcards, Fridge Mail drawings and places you suggest to people show up here."
            }
        }
    }

    /// What a row is drawn as: its icon, its tint, and where a tap goes.
    enum Kind: Equatable {
        case checkIn, place, moment, sent, social, other

        init(category: String?) {
            switch category {
            case "checkins": self = .checkIn
            case "places": self = .place
            case "moments": self = .moment
            case "sent": self = .sent
            case "social": self = .social
            default: self = .other
            }
        }

        var symbolName: String {
            switch self {
            case .checkIn: return "mappin.and.ellipse"
            case .place: return "plus.circle"
            case .moment: return "play.rectangle"
            case .sent: return "envelope"
            case .social: return "heart"
            case .other: return "sparkles"
            }
        }
    }

    enum Row: Equatable {
        case single(OwnActivityItem)
        /// The day's social actions, folded: `items` newest first.
        case socialDigest(dayKey: String, items: [OwnActivityItem])
    }

    struct DaySection: Equatable {
        let dayKey: String
        let title: String
        let rows: [Row]
    }

    // MARK: - Grouping

    /// Newest day first, rows newest first within it; a day's social rows
    /// fold into one digest at the position of the newest one.
    static func sections(from items: [OwnActivityItem], now: Date = Date(), calendar: Calendar = .current) -> [DaySection] {
        var order: [String] = []
        var byDay: [String: [OwnActivityItem]] = [:]
        for item in items.sorted(by: { $0.timestamp > $1.timestamp }) {
            let key = dayKey(item.timestamp, calendar: calendar)
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(item)
        }
        return order.map { key in
            let dayItems = byDay[key] ?? []
            var rows: [Row] = []
            var social: [OwnActivityItem] = []
            var digestIndex: Int?
            for item in dayItems {
                if Kind(category: item.category) == .social {
                    if digestIndex == nil { digestIndex = rows.count; rows.append(.socialDigest(dayKey: key, items: [])) }
                    social.append(item)
                } else {
                    rows.append(.single(item))
                }
            }
            if let i = digestIndex {
                if social.count == 1, let only = social.first {
                    rows[i] = .single(only)
                } else {
                    rows[i] = .socialDigest(dayKey: key, items: social)
                }
            }
            return DaySection(dayKey: key, title: dayTitle(dayItems.first?.timestamp ?? now, now: now, calendar: calendar), rows: rows)
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "TODAY", "YESTERDAY", "MON, SEP 22", or "SEP 22, 2025" for another year.
    static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        f.dateFormat = sameYear ? "EEE, MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }

    // MARK: - Words

    /// "Checked in at Tommy's Tavern", "Posted a moment at …", "Sent a postcard to Mom".
    static func title(for item: OwnActivityItem) -> String {
        let name = item.targetName ?? ""
        switch item.type {
        case "check_in": return name.isEmpty ? "Checked in" : "Checked in at \(name)"
        case "place_added", "place", "place_discovered":
            if let circle = item.circleName, !circle.isEmpty { return "Added \(name) to \(circle)" }
            return name.isEmpty ? "Added a place" : "Added \(name)"
        case "photo_uploaded": return name.isEmpty ? "Added a photo" : "Added a photo of \(name)"
        case "circle_created": return name.isEmpty ? "Created a circle" : "Created the circle \(name)"
        case "video_uploaded", "moment_uploaded":
            let noun = item.contentType == "photo" ? "a photo moment" : "a moment"
            return name.isEmpty ? "Posted \(noun)" : "Posted \(noun) at \(name)"
        case "postcard_sent": return "Sent a postcard to \(item.recipientName ?? name)"
        case "postcard_mailed": return "Mailed a postcard to \(item.recipientName ?? name)"
        case "fridgemail_sent": return "Mailed \(item.recipientName ?? name) a drawing"
        case "suggestion_sent": return name.isEmpty ? "Suggested a place" : "Suggested \(name)"
        case "place_liked", "global_place_liked": return name.isEmpty ? "Liked a place" : "Liked \(name)"
        case "video_liked": return name.isEmpty ? "Liked a moment" : "Liked a moment at \(name)"
        case "comment_added", "place_commented": return name.isEmpty ? "Commented" : "Commented on \(name)"
        case "circle_liked": return name.isEmpty ? "Liked a circle" : "Liked the circle \(name)"
        case "circle_commented": return name.isEmpty ? "Commented on a circle" : "Commented on \(name)"
        case "comment_liked": return "Liked a comment"
        case "user_followed": return name.isEmpty ? "Followed someone" : "Followed \(name)"
        case "reaction_added": return name.isEmpty ? "Reacted" : "Reacted to \(name)"
        case "suggestion_accepted": return name.isEmpty ? "Accepted a suggestion" : "Added \(name) from a suggestion"
        default: return name.isEmpty ? "Activity" : name
        }
    }

    /// The second line: companions, rating, note, counts, mail status, privacy.
    static func detail(for item: OwnActivityItem) -> String? {
        var parts: [String] = []
        switch Kind(category: item.category) {
        case .checkIn:
            if !item.companions.isEmpty { parts.append("with " + item.companions.prefix(3).joined(separator: ", ")) }
            if let r = item.rating { parts.append("rated \(r)") }
            if let m = item.message, !m.isEmpty { parts.append("“\(m)”") }
            if item.isPrivate { parts.append("Private · only you") }
        case .place:
            if let a = item.placeAddress, !a.isEmpty { parts.append(shortAddress(a)) }
            if let m = item.message, !m.isEmpty { parts.append("“\(m)”") }
        case .moment:
            if let likes = item.likeCount { parts.append(likes == 1 ? "1 like" : "\(likes) likes") }
            if let comments = item.commentCount, comments > 0 { parts.append(comments == 1 ? "1 comment" : "\(comments) comments") }
        case .sent:
            if let status = item.mailStatus { parts.append(mailStatusLine(status)) }
            if let m = item.message, !m.isEmpty { parts.append("“\(m)”") }
        case .social:
            if let m = item.message, !m.isEmpty { parts.append("“\(m)”") }
        case .other:
            break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func mailStatusLine(_ status: String) -> String {
        switch status {
        case "submitted", "printing": return "printed, in the mail"
        case "mailed", "in_transit": return "in the mail"
        case "delivered": return "delivered"
        default: return status.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// "Liked 3 places and commented on Sal's moment" → one line for the digest.
    static func digestTitle(_ items: [OwnActivityItem]) -> String {
        var likes = 0, comments = 0, follows = 0, other = 0
        for item in items {
            switch item.type {
            case "place_liked", "global_place_liked", "video_liked", "circle_liked", "comment_liked", "reaction_added": likes += 1
            case "comment_added", "place_commented", "circle_commented": comments += 1
            case "user_followed": follows += 1
            default: other += 1
            }
        }
        var parts: [String] = []
        if likes > 0 { parts.append(likes == 1 ? "1 like" : "\(likes) likes") }
        if comments > 0 { parts.append(comments == 1 ? "1 comment" : "\(comments) comments") }
        if follows > 0 { parts.append(follows == 1 ? "1 follow" : "\(follows) follows") }
        if other > 0 { parts.append(other == 1 ? "1 more" : "\(other) more") }
        return parts.joined(separator: ", ")
    }

    /// "123 Main St, Charlotte, NC 28202, USA" → "Charlotte".
    static func shortAddress(_ address: String) -> String {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 3 { return parts[parts.count - 3] }
        return parts.first ?? address
    }

    // MARK: - Summary words

    /// "4-week check-in streak · most visited: Tommy's Tavern".
    static func summaryLine(_ summary: OwnActivitySummary) -> String? {
        var parts: [String] = []
        if summary.streakWeeks >= 2 { parts.append("\(summary.streakWeeks)-week check-in streak") }
        if let most = summary.mostVisited, most.count >= 2 { parts.append("most visited: \(most.name)") }
        if summary.privateCheckIns > 0 { parts.append(summary.privateCheckIns == 1 ? "1 private check-in" : "\(summary.privateCheckIns) private check-ins") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "September" from "2026-09".
    static func monthName(_ key: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return key }
        var comps = DateComponents(); comps.year = parts[0]; comps.month = parts[1]; comps.day = 1
        guard let date = calendar.date(from: comps) else { return key }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMMM" : "MMMM yyyy"
        return f.string(from: date)
    }

    /// The text shared as this month's recap.
    static func recapText(_ summary: OwnActivitySummary, name: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let month = monthName(summary.month, now: now, calendar: calendar)
        var bits: [String] = []
        let c = summary.counts
        if c.checkins > 0 { bits.append(c.checkins == 1 ? "1 check-in" : "\(c.checkins) check-ins") }
        if c.places > 0 { bits.append(c.places == 1 ? "1 place added" : "\(c.places) places added") }
        if c.moments > 0 { bits.append(c.moments == 1 ? "1 moment" : "\(c.moments) moments") }
        if c.postcards > 0 { bits.append(c.postcards == 1 ? "1 postcard" : "\(c.postcards) postcards") }
        var text = "\(name)'s \(month) on FavCircles" + (bits.isEmpty ? "." : ": " + bits.joined(separator: ", ") + ".")
        if let most = summary.mostVisited, most.count >= 2 { text += " Most visited: \(most.name)." }
        return text
    }
}
