import Foundation

/// One venue from a Swarm (Foursquare) data export: every check-in there,
/// folded into one place with its history.
struct SwarmVenueHistory: Equatable {
    /// Foursquare's venue id ("5ecea99334eba80008b02265"); a name+spot key
    /// when an old export has none
    let id: String
    let name: String
    let url: String?
    /// The venue's own location when the export has it (older exports);
    /// otherwise the phone's most accurate spot at check-in
    let latitude: Double?
    let longitude: Double?
    /// True when latitude/longitude are the venue's own (not the phone's)
    let isVenueLocation: Bool
    let address: String?
    let category: String?
    let checkInCount: Int
    let firstCheckInAt: Date?
    let lastCheckInAt: Date?
}

struct SwarmExport: Equatable {
    /// Most-visited first, then most recent
    let venues: [SwarmVenueHistory]
    let checkInCount: Int
}

/// Reads the zip Foursquare emails after Swarm → Settings → Data & Privacy →
/// Privacy rights → Data download request (Wes, 2026-11-09). Check-ins live
/// in `checkins1.json` (and `checkins2.json`… for long histories), with a CSV
/// twin of each. Nothing else in the export names a venue: `shares.json` and
/// `tastes.json` carry ids only, the rest is account data. Pure: no UIKit,
/// no services.
///
/// Format seen in a real export (Nov 2026):
///   { "count": 1, "items": [ { "id", "createdAt": "2026-11-07 12:06:39.000000"
///     (UTC; `timeZoneOffset` is the local zone in minutes), "type": "checkin",
///     "venue": { "id", "name", "url" }, "lat", "lng", "hacc" (metres) } ] }
/// Older exports may nest `venue.location` (lat/lng/address) and
/// `venue.categories`, and use epoch seconds for `createdAt`; both are read.
enum SwarmExportParser {

    enum Failure: LocalizedError, Equatable {
        case noCheckInFiles
        case noCheckIns

        var errorDescription: String? {
            switch self {
            case .noCheckInFiles:
                return "That doesn't look like a Swarm export. Pick the zip Foursquare emailed you (it has a checkins1.json file inside)."
            case .noCheckIns:
                return "Your Swarm export has no check-ins to import."
            }
        }
    }

    /// checkins.json, checkins1.json, checkins12.csv… in any folder of the zip
    static func checkInsFileKind(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard !name.hasPrefix("._"), name.hasPrefix("checkins") else { return nil }
        let stem = (name as NSString).deletingPathExtension.dropFirst("checkins".count)
        guard stem.allSatisfy(\.isNumber) else { return nil }
        let ext = (name as NSString).pathExtension
        return ["json", "csv"].contains(ext) ? ext : nil
    }

    /// A file (or a zip's contents) opened with the app is Swarm's export
    static func isSwarmExport(fileNames: [String]) -> Bool {
        fileNames.contains { checkInsFileKind($0) != nil }
    }

    static func parse(files: [(name: String, data: Data)]) throws -> SwarmExport {
        let json = files.filter { checkInsFileKind($0.name) == "json" }
        let csv = files.filter { checkInsFileKind($0.name) == "csv" }
        // Each JSON has a CSV twin with the same rows: read one kind, never both
        let rows: [CheckInRow]
        if !json.isEmpty {
            rows = json.flatMap { rowsFromJSON($0.data) }
        } else if !csv.isEmpty {
            rows = csv.flatMap { rowsFromCSV($0.data) }
        } else {
            throw Failure.noCheckInFiles
        }
        let venues = fold(rows)
        guard !venues.isEmpty else { throw Failure.noCheckIns }
        return SwarmExport(venues: venues, checkInCount: venues.reduce(0) { $0 + $1.checkInCount })
    }

    // MARK: - Rows

    struct CheckInRow: Equatable {
        var venueId: String?
        var venueName: String
        var venueURL: String?
        var latitude: Double?
        var longitude: Double?
        var accuracy: Double?
        var venueLatitude: Double?
        var venueLongitude: Double?
        var address: String?
        var category: String?
        var at: Date?
    }

    static func rowsFromJSON(_ data: Data) -> [CheckInRow] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let items: [[String: Any]]
        if let dict = object as? [String: Any] {
            items = (dict["items"] as? [[String: Any]])
                ?? ((dict["response"] as? [String: Any])?["checkins"] as? [String: Any])?["items"] as? [[String: Any]]
                ?? []
        } else {
            items = object as? [[String: Any]] ?? []
        }
        return items.compactMap { item in
            if let type = item["type"] as? String, type.lowercased() != "checkin" { return nil }
            guard let venue = item["venue"] as? [String: Any],
                  let name = trimmed(venue["name"] as? String) else { return nil }
            let location = venue["location"] as? [String: Any]
            return CheckInRow(
                venueId: trimmed(venue["id"] as? String),
                venueName: name,
                venueURL: trimmed(venue["url"] as? String) ?? trimmed(venue["canonicalUrl"] as? String),
                latitude: number(item["lat"]),
                longitude: number(item["lng"]),
                accuracy: number(item["hacc"]),
                venueLatitude: number(location?["lat"]),
                venueLongitude: number(location?["lng"]),
                address: address(from: location),
                category: primaryCategory(venue["categories"]),
                at: date(item["createdAt"])
            )
        }
    }

    static func rowsFromCSV(_ data: Data) -> [CheckInRow] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        let table = ImportParsingService.parseCSV(text)
        guard let header = table.first else { return [] }
        let column = Dictionary(header.enumerated().map {
            ($1.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{FEFF}", with: "").lowercased(), $0)
        }, uniquingKeysWith: { first, _ in first })
        func value(_ row: [String], _ key: String) -> String? {
            guard let index = column[key], index < row.count else { return nil }
            return trimmed(row[index])
        }
        guard column["venue.name"] != nil else { return [] }
        return table.dropFirst().compactMap { row in
            if let type = value(row, "type"), type.lowercased() != "checkin" { return nil }
            guard let name = value(row, "venue.name") else { return nil }
            return CheckInRow(
                venueId: value(row, "venue.id"),
                venueName: name,
                venueURL: value(row, "venue.url"),
                latitude: value(row, "lat").flatMap(Double.init),
                longitude: value(row, "lng").flatMap(Double.init),
                accuracy: value(row, "hacc").flatMap(Double.init),
                venueLatitude: value(row, "venue.location.lat").flatMap(Double.init),
                venueLongitude: value(row, "venue.location.lng").flatMap(Double.init),
                address: value(row, "venue.location.address"),
                category: nil,
                at: date(value(row, "createdAt"))
            )
        }
    }

    // MARK: - Folding

    /// One venue per Foursquare id: count, first and last check-in, and the
    /// best location (the venue's own, else the most accurate phone spot).
    static func fold(_ rows: [CheckInRow]) -> [SwarmVenueHistory] {
        var order: [String] = []
        var groups: [String: [CheckInRow]] = [:]
        for row in rows {
            let key = row.venueId ?? fallbackKey(row)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        let venues: [SwarmVenueHistory] = order.compactMap { key in
            guard let group = groups[key], let newest = group.max(by: { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }) else { return nil }
            let dates = group.compactMap(\.at).sorted()
            let withVenueSpot = group.first { valid($0.venueLatitude, $0.venueLongitude) }
            let bestPhoneSpot = group
                .filter { valid($0.latitude, $0.longitude) }
                .min { ($0.accuracy ?? .greatestFiniteMagnitude) < ($1.accuracy ?? .greatestFiniteMagnitude) }
            return SwarmVenueHistory(
                id: key,
                name: newest.venueName,
                url: group.compactMap(\.venueURL).first,
                latitude: withVenueSpot?.venueLatitude ?? bestPhoneSpot?.latitude,
                longitude: withVenueSpot?.venueLongitude ?? bestPhoneSpot?.longitude,
                isVenueLocation: withVenueSpot != nil,
                address: group.compactMap(\.address).first,
                category: group.compactMap(\.category).first,
                checkInCount: group.count,
                firstCheckInAt: dates.first,
                lastCheckInAt: dates.last
            )
        }
        return venues.sorted {
            if $0.checkInCount != $1.checkInCount { return $0.checkInCount > $1.checkInCount }
            return ($0.lastCheckInAt ?? .distantPast) > ($1.lastCheckInAt ?? .distantPast)
        }
    }

    private static func fallbackKey(_ row: CheckInRow) -> String {
        let name = row.venueName.lowercased()
        guard let lat = row.venueLatitude ?? row.latitude, let lng = row.venueLongitude ?? row.longitude else { return "name:\(name)" }
        // ~1 km cells: two branches of a chain stay apart
        return String(format: "name:%@@%.2f,%.2f", name, lat, lng)
    }

    // MARK: - Values

    private static func valid(_ lat: Double?, _ lng: Double?) -> Bool {
        guard let lat = lat, let lng = lng else { return false }
        return abs(lat) <= 90 && abs(lng) <= 180 && !(lat == 0 && lng == 0)
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func address(from location: [String: Any]?) -> String? {
        guard let location = location else { return nil }
        if let lines = location["formattedAddress"] as? [String], !lines.isEmpty {
            return lines.joined(separator: ", ")
        }
        let parts = ["address", "city", "state", "postalCode", "country"].compactMap { trimmed(location[$0] as? String) }
        return parts.isEmpty || trimmed(location["address"] as? String) == nil ? nil : parts.joined(separator: ", ")
    }

    private static func primaryCategory(_ value: Any?) -> String? {
        guard let categories = value as? [[String: Any]] else { return nil }
        let primary = categories.first { ($0["primary"] as? Bool) == true } ?? categories.first
        return trimmed(primary?["name"] as? String)
    }

    /// "2026-11-07 12:06:39.000000" (UTC), ISO 8601, or epoch seconds
    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        guard let text = trimmed(value as? String) else { return nil }
        if let seconds = Double(text), seconds > 100_000_000 { return Date(timeIntervalSince1970: seconds) }
        for formatter in exportFormatters {
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private static let exportFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}

/// Words for a Swarm import (review rows, the done message). Pure.
enum SwarmImportCopy {
    /// "12 check-ins · last Nov 7" / "1 check-in · last Mar 2, 2019"
    static func historyLine(count: Int, last: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        var line = "\(count) check-in\(count == 1 ? "" : "s")"
        if let last = last {
            line += " · last \(CheckInHistoryFormatter.dayLabel(for: last, now: now, calendar: calendar, locale: locale))"
        }
        return line
    }

    /// The done message's history sentence, nil when none was recorded
    static func historySentence(_ places: Int) -> String? {
        guard places > 0 else { return nil }
        return "Your Swarm check-in history is on \(places) place\(places == 1 ? "" : "s")."
    }
}

/// How to get the export, word for word as Swarm shows it (Wes's screenshots,
/// Nov 2026: "Privacy rights", not "Privacy settings"). Used by Import Places
/// and the Help topic.
enum SwarmImportInstructions {
    static let steps = """
    In Swarm:

    1. Tap your profile, then the gear (Settings)
    2. Tap Data & Privacy → Privacy rights
    3. Tap Data download request
    4. Foursquare emails you a link (it can take a few days)
    5. Download the zip, save it to Files, then pick it here

    Each place you checked in at comes over once, with how many times you went. Nothing is posted to Swarm or to your FavCircles feed.
    """
}

// Here, not in ImportParsingService.swift: the Share extension compiles that
// file and has no Swarm parser
extension ImportParsingService {
    /// A Swarm export as one import list ("Swarm check-ins"), most-visited first
    static func swarmList(from export: SwarmExport) -> ImportList {
        let iso = ISO8601DateFormatter()
        let places: [ImportPlaceCandidate] = export.venues.map { venue in
            var candidate = ImportPlaceCandidate(
                name: venue.name,
                address: venue.isVenueLocation ? venue.address : nil,
                lat: venue.latitude,
                lng: venue.longitude,
                category: nil,
                notes: nil,
                tags: [],
                sourceExternalId: venue.id,
                sourceUrl: venue.url
            )
            if let first = venue.firstCheckInAt ?? venue.lastCheckInAt, let last = venue.lastCheckInAt ?? venue.firstCheckInAt {
                candidate.checkIns = ImportCheckInHistory(count: venue.checkInCount, firstAt: iso.string(from: first), lastAt: iso.string(from: last))
            }
            // Only the venue's own location with its address needs no lookup
            candidate.needsVenueLookup = !(venue.isVenueLocation && venue.address != nil)
            return candidate
        }
        return ImportList(name: "Swarm check-ins", places: places)
    }
}
