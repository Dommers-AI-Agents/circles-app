import Foundation

// MARK: - Import Models

/// Where an import payload came from. Raw values match the backend's
/// accepted `source` values (POST /api/import/prepare|execute).
enum ImportSource: String {
    case mapstr
    case googleMaps = "google_maps"
    case swarm

    var displayName: String {
        switch self {
        case .mapstr: return "Mapstr"
        case .googleMaps: return "Google Maps"
        case .swarm: return "Swarm"
        }
    }
}

/// One place parsed from an export file, before backend resolution.
struct ImportPlaceCandidate {
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?
    var category: String?
    var notes: String?
    var tags: [String]
    var sourceExternalId: String?
    var sourceUrl: String?

    var asRequestBody: [String: Any] {
        var body: [String: Any] = ["name": name]
        if let address = address { body["address"] = address }
        if let lat = lat { body["lat"] = lat }
        if let lng = lng { body["lng"] = lng }
        if let category = category { body["category"] = category }
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        if !tags.isEmpty { body["tags"] = tags }
        if let sourceExternalId = sourceExternalId { body["sourceExternalId"] = sourceExternalId }
        if let sourceUrl = sourceUrl { body["sourceUrl"] = sourceUrl }
        return body
    }
}

/// One source list (a Google Takeout CSV, a Mapstr export, a Swarm list),
/// which becomes one proposed circle.
struct ImportList {
    var name: String
    var places: [ImportPlaceCandidate]
}

enum ImportParsingError: LocalizedError {
    case unreadableFile(String)
    case unrecognizedFormat(String)
    case emptyFile(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            return "Couldn't read \"\(name)\". Make sure it's the original export file."
        case .unrecognizedFormat(let name):
            return "\"\(name)\" doesn't look like an export from this app. Check the import instructions and try again."
        case .emptyFile(let name):
            return "\"\(name)\" doesn't contain any places."
        }
    }
}

// MARK: - Parsing Service

/// Parses platform export files (Mapstr GeoJSON, Google Takeout CSVs) into
/// the normalized payload the import API expects. Parsing happens on-device
/// so the user gets an instant preview before anything is uploaded.
final class ImportParsingService {

    static let shared = ImportParsingService()
    private init() {}

    // MARK: Mapstr (GeoJSON export, emailed from Settings → Export your data)

    /// Mapstr's export is a GeoJSON FeatureCollection with [lng, lat]
    /// coordinates and free-form properties (name, tags, comment).
    func parseMapstrGeoJSON(data: Data, filename: String) throws -> [ImportList] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportParsingError.unreadableFile(filename)
        }
        guard let features = json["features"] as? [[String: Any]] else {
            throw ImportParsingError.unrecognizedFormat(filename)
        }

        var places: [ImportPlaceCandidate] = []
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any] else { continue }

            let name = (properties["name"] as? String)
                ?? (properties["title"] as? String)
                ?? ""
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var lat: Double?
            var lng: Double?
            if let geometry = feature["geometry"] as? [String: Any],
               let coordinates = geometry["coordinates"] as? [Any],
               coordinates.count >= 2 {
                lng = doubleValue(coordinates[0])
                lat = doubleValue(coordinates[1])
            }

            let address = (properties["address"] as? String)
                ?? (properties["formatted_address"] as? String)
            let notes = (properties["comment"] as? String)
                ?? (properties["description"] as? String)
                ?? (properties["note"] as? String)
            let tags = stringArray(properties["tags"])
                ?? stringArray(properties["categories"])
                ?? []

            // Stable re-import id: normalized name + rounded coordinates.
            // Readable and deterministic; the backend treats it as opaque.
            var externalId: String?
            if let lat = lat, let lng = lng {
                let slug = name.lowercased()
                    .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                externalId = String(format: "mapstr:%@:%.5f,%.5f", slug, lat, lng)
            }

            places.append(ImportPlaceCandidate(
                name: name,
                address: address,
                lat: lat,
                lng: lng,
                category: nil,
                notes: notes,
                tags: tags,
                sourceExternalId: externalId,
                sourceUrl: nil
            ))
        }

        guard !places.isEmpty else { throw ImportParsingError.emptyFile(filename) }
        return [ImportList(name: "Mapstr Places", places: places)]
    }

    // MARK: Google Takeout ("Saved" product: one CSV per list)

    /// Google Takeout Saved CSVs have columns Title,Note,URL and, in newer
    /// exports, Address (older exports used Comment). Rows carry no
    /// coordinates — dropped pins encode lat/lng in the URL, regular places
    /// carry a hex CID; everything else is resolved server-side.
    func parseGoogleTakeoutCSV(data: Data, filename: String) throws -> ImportList {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportParsingError.unreadableFile(filename)
        }

        let rows = ImportParsingService.parseCSV(text)
        guard let header = rows.first, rows.count > 1 else {
            throw ImportParsingError.emptyFile(filename)
        }

        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let titleIndex = columns.firstIndex(of: "title"), columns.contains("url") else {
            throw ImportParsingError.unrecognizedFormat(filename)
        }
        let urlIndex = columns.firstIndex(of: "url")
        let noteIndex = columns.firstIndex(of: "note")
        let addressIndex = columns.firstIndex(of: "address")
        let commentIndex = columns.firstIndex(of: "comment")

        var places: [ImportPlaceCandidate] = []
        for row in rows.dropFirst() {
            guard titleIndex < row.count else { continue }
            let name = row[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let url = urlIndex.flatMap { $0 < row.count ? row[$0] : nil }
            let address = addressIndex.flatMap { $0 < row.count ? emptyToNil(row[$0]) : nil }
            var notes = noteIndex.flatMap { $0 < row.count ? emptyToNil(row[$0]) : nil }
            if notes == nil, let commentIndex = commentIndex, commentIndex < row.count {
                notes = emptyToNil(row[commentIndex])
            }

            var candidate = ImportPlaceCandidate(
                name: name,
                address: address,
                lat: nil,
                lng: nil,
                category: nil,
                notes: notes,
                tags: [],
                sourceExternalId: nil,
                sourceUrl: emptyToNil(url ?? "")
            )

            if let url = url {
                if let coords = ImportParsingService.pinCoordinates(fromGoogleURL: url) {
                    candidate.lat = coords.lat
                    candidate.lng = coords.lng
                    candidate.sourceExternalId = String(format: "pin:%.6f,%.6f", coords.lat, coords.lng)
                } else if let cid = ImportParsingService.cid(fromGoogleURL: url) {
                    candidate.sourceExternalId = "cid:\(cid)"
                }
            }

            places.append(candidate)
        }

        guard !places.isEmpty else { throw ImportParsingError.emptyFile(filename) }

        let listName = (filename as NSString).deletingPathExtension
        return ImportList(name: listName.isEmpty ? "Google Maps" : listName, places: places)
    }

    // MARK: Google Maps URL extraction

    /// Dropped pins: https://www.google.com/maps/search/48.8566101,+2.3514992
    static func pinCoordinates(fromGoogleURL url: String) -> (lat: Double, lng: Double)? {
        let pattern = #"/maps/search/(-?\d+\.\d+),\s*\+?(-?\d+\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let latRange = Range(match.range(at: 1), in: url),
              let lngRange = Range(match.range(at: 2), in: url),
              let lat = Double(url[latRange]),
              let lng = Double(url[lngRange]),
              abs(lat) <= 90, abs(lng) <= 180 else {
            return nil
        }
        return (lat, lng)
    }

    /// Regular places: ...data=!4m2!3m1!1s0x<featureId>:0x<CID> — the second
    /// hex value is a stable place identifier.
    static func cid(fromGoogleURL url: String) -> String? {
        let pattern = #"!1s0x[0-9a-fA-F]+:0x([0-9a-fA-F]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let cidRange = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return String(url[cidRange]).lowercased()
    }

    // MARK: CSV (RFC 4180: quoted fields may contain commas, quotes, newlines)

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r":
                    break
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: Helpers

    private func doubleValue(_ value: Any) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func stringArray(_ value: Any?) -> [String]? {
        if let strings = value as? [String] { return strings }
        if let objects = value as? [[String: Any]] {
            let names = objects.compactMap { $0["name"] as? String }
            return names.isEmpty ? nil : names
        }
        return nil
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
