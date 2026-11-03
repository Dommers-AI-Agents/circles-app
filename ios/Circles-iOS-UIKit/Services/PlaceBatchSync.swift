import Foundation
import CryptoKit

/// "Only what changed" for POST places/batch (Wes, 2026-11-03: the home
/// batch re-sent all 938 of his places, 1.5 MB, on every launch to catch the
/// few that changed).
///
/// The phone keeps the server's last full answer, as raw JSON, per account
/// and set of circles, and sends when it got it (`since`). The server answers
/// with the places that changed in full, the list as it stands now (`ids`,
/// in order, so removals drop out) and which carry the red dot (`newIds`).
/// The merge is then decoded exactly like a full answer, so a merged place is
/// the same Place a full download gives.
///
/// Falls back to a full download whenever it can't be sure: no saved copy,
/// one older than a day, a different app version, or a merge with a gap.
enum PlaceBatchSync {
    /// A full download at least this often, to pick up anything a change
    /// stamp can't see (an adder renaming themselves)
    static let fullRefreshInterval: TimeInterval = 24 * 3600

    /// The changed places over the saved copy, in the server's order, with
    /// today's red dots. Nil when a listed place is in neither: the caller
    /// downloads in full instead.
    static func merge(cached: [JSONValue], changed: [JSONValue], ids: [String], newIds: [String]) -> [JSONValue]? {
        var byId: [String: JSONValue] = [:]
        for place in cached { if let id = place.placeId { byId[id] = place } }
        for place in changed { if let id = place.placeId { byId[id] = place } }
        let dotted = Set(newIds)
        var merged: [JSONValue] = []
        merged.reserveCapacity(ids.count)
        for id in ids {
            guard case .object(var fields)? = byId[id] else { return nil }
            fields["isNew"] = .bool(dotted.contains(id))
            merged.append(.object(fields))
        }
        return merged
    }

    // MARK: - The saved copy

    struct Snapshot: Codable {
        let syncedAt: String
        let savedAt: Date
        let appVersion: String
        let places: [JSONValue]
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "")(\(info?["CFBundleVersion"] ?? ""))"
    }

    private static func fileURL(userId: String, circleIds: [String]) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let key = SHA256.hash(data: Data((userId + "|" + circleIds.sorted().joined(separator: ",")).utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(32)
        return base.appendingPathComponent("PlaceBatch", isDirectory: true).appendingPathComponent("\(key).json")
    }

    /// The saved copy when it's good to merge onto
    static func load(userId: String, circleIds: [String], now: Date = Date()) -> Snapshot? {
        guard let url = fileURL(userId: userId, circleIds: circleIds),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.appVersion == appVersion,
              now.timeIntervalSince(snapshot.savedAt) < fullRefreshInterval else { return nil }
        return snapshot
    }

    /// Keeps a merged copy's original full-download time, so the daily full
    /// refresh still comes round
    static func save(_ places: [JSONValue], syncedAt: String, userId: String, circleIds: [String], fullDownload: Bool) {
        guard let url = fileURL(userId: userId, circleIds: circleIds) else { return }
        let savedAt = fullDownload ? Date() : (load(userId: userId, circleIds: circleIds)?.savedAt ?? Date())
        let snapshot = Snapshot(syncedAt: syncedAt, savedAt: savedAt, appVersion: appVersion, places: places)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Signed out: nobody else's places stay on the phone
    static func clearAll() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("PlaceBatch", isDirectory: true))
    }
}

/// The batch answer before decoding into Places (full or "changes only")
struct PlacesBatchRaw: Decodable {
    let mode: String?
    let ids: [String]?
    let places: [JSONValue]
    let newIds: [String]?
    let syncedAt: String?
}

/// JSON exactly as it came over the wire, so a saved place decodes later
/// just as it would have then. Whole numbers stay whole.
indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// A place's id as the server writes it
    var placeId: String? {
        guard case .object(let fields) = self else { return nil }
        if case .string(let id)? = fields["id"] { return id }
        if case .string(let id)? = fields["_id"] { return id }
        return nil
    }
}
