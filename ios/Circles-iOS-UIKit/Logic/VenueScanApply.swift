import Foundation

/// Putting an hours-sign or flyer scan into the owner's editors (pure). The
/// scan only suggests: days the sign doesn't show keep what the owner had,
/// and unsure values are named so the screen can ask the owner to check.
enum VenueScanApply {

    /// The hours draft with the scanned days filled in, and the days to check
    static func hours(_ draft: VenueHoursDraft, scan: HoursScanDraft) -> (draft: VenueHoursDraft, unsureDays: Set<Int>, filled: Int) {
        var out = draft
        var unsure: Set<Int> = []
        var filled = 0
        for scanned in scan.hours {
            guard let i = out.days.firstIndex(where: { $0.day == scanned.day }) else { continue }
            if scanned.isClosed {
                out.days[i].isClosed = true
            } else if let open = VenueHoursDraft.normalized(scanned.open), let close = VenueHoursDraft.normalized(scanned.close) {
                out.days[i].isClosed = false
                out.days[i].open = open
                out.days[i].close = close
            } else if scanned.open != nil || scanned.close != nil {
                // Only one of the two times read: fill it, ask the owner for the other
                if let open = VenueHoursDraft.normalized(scanned.open) { out.days[i].open = open }
                if let close = VenueHoursDraft.normalized(scanned.close) { out.days[i].close = close }
                out.days[i].isClosed = false
                unsure.insert(scanned.day)
                filled += 1
                continue
            } else {
                continue   // not on the sign: leave it
            }
            filled += 1
            if scanned.unsure == true { unsure.insert(scanned.day) }
        }
        return (out, unsure, filled)
    }

    /// A flyer as the announcement form's fields. Event times are the
    /// venue's local clock (`timeZone`), like the form's pickers.
    static func announcement(_ flyer: FlyerScanDraft, into edit: VenueAnnouncementEdit,
                             timeZone: TimeZone = .current) -> VenueAnnouncementEdit {
        var out = edit
        if !flyer.title.isEmpty { out.title = flyer.title }
        if !flyer.message.isEmpty { out.message = flyer.message }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func date(_ day: String, _ time: String?) -> Date? {
            let d = day.split(separator: "-").compactMap { Int($0) }
            guard d.count == 3 else { return nil }
            let t = (time ?? "").split(separator: ":").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2],
                                                      hour: t.count >= 2 ? t[0] : 19, minute: t.count >= 2 ? t[1] : 0))
        }
        if let event = flyer.event, let start = date(event.localDate, event.localTime) {
            out.eventStart = start
            if let endTime = event.endTime, var end = date(event.localDate, endTime) {
                if end <= start { end = end.addingTimeInterval(24 * 3600) }   // runs past midnight
                out.eventEnd = end
            } else {
                out.eventEnd = nil
            }
            out.eventIsFree = event.isFree == true
            out.endsOn = nil
        } else if let endsOn = flyer.expiresOn, let day = date(endsOn, "23:59") {
            out.endsOn = day
        }
        return out
    }

    /// "Check the date and start time: the photo was hard to read there."
    static func flyerCheckLine(_ flyer: FlyerScanDraft) -> String? {
        let names: [String: String] = ["title": "headline", "details": "details", "event_date": "date",
                                       "start_time": "start time", "end_time": "end time", "is_free": "free entry", "ends_on": "end date"]
        let parts = flyer.unsure.compactMap { names[$0] }
        guard !parts.isEmpty else { return nil }
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "Check the \(list): the photo was hard to read there."
    }
}
