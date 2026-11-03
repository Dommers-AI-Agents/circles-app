import Foundation
import CryptoKit

/// "Only what changed" for the lists Home loads at every launch (Wes,
/// 2026-11-03): places/batch, network/places/viewport and
/// network/my-network-circles re-sent everything (1.8 MB, 460 KB, 350 KB
/// for Wes) to catch the few things that changed.
///
/// The phone keeps the server's last full list, as raw JSON, per account and
/// request (`Feed` + key), and sends when it got it (`since`). The server
/// answers with the changed items in full and the list as it stands now
/// (`ids`, in order, so removals drop out), plus per-feed extras (the red
/// dots, owner cards). The merge is decoded exactly like a full answer, so a
/// merged item is the same one a full download gives.
///
/// Falls back to a full download whenever it can't be sure: no saved copy,
/// one older than a day, a different app version, or a merge with a gap.
enum DeltaSync {
    /// The lists that sync this way. `listKey` is where the server puts the list.
    enum Feed: String {
        case placesBatch, networkViewport, networkCircles

        var listKey: String { self == .networkCircles ? "data" : "places" }
        /// Saved copies kept per account (map views mint a new key per region)
        var keepCopies: Int { self == .networkViewport ? 20 : 8 }
    }

    /// A full download at least this often, to pick up anything a change
    /// stamp can't see (an adder renaming themselves)
    static let fullRefreshInterval: TimeInterval = 24 * 3600

    /// The changed items over the saved copy, in the server's order, each
    /// passed through `restamp` (today's red dot, today's owner card). Nil
    /// when a listed item is in neither: the caller downloads in full instead.
    static func merge(cached: [JSONValue], changed: [JSONValue], ids: [String],
                      restamp: (_ id: String, _ fields: inout [String: JSONValue]) -> Void = { _, _ in }) -> [JSONValue]? {
        var byId: [String: JSONValue] = [:]
        for item in cached { if let id = item.itemId { byId[id] = item } }
        for item in changed { if let id = item.itemId { byId[id] = item } }
        var merged: [JSONValue] = []
        merged.reserveCapacity(ids.count)
        for id in ids {
            guard case .object(var fields)? = byId[id] else { return nil }
            restamp(id, &fields)
            merged.append(.object(fields))
        }
        return merged
    }

    // MARK: - Fetching

    /// GET or POST `endpoint` the changed-only way and hand back the full
    /// answer as `{"success": true, <listKey>: [...]}` JSON, ready to decode
    /// into the caller's usual response type. `restamp` rewrites each merged
    /// item from the delta answer's extras.
    static func fetch(_ feed: Feed, endpoint: String, method: RequestMethod, body: [String: Any] = [:], cacheKey: String,
                      restamp: ((_ answer: [String: JSONValue]) -> ((String, inout [String: JSONValue]) -> Void))? = nil,
                      allowDelta: Bool = true, completion: @escaping (Result<Data, Error>) -> Void) {
        let userId = AuthService.shared.getUserId()
        let saved = allowDelta ? userId.flatMap { load(feed, userId: $0, key: cacheKey) } : nil
        var requestBody = body
        var requestEndpoint = endpoint
        if let saved {
            if method == .get {
                let encoded = saved.syncedAt.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? saved.syncedAt
                requestEndpoint += (endpoint.contains("?") ? "&" : "?") + "since=\(encoded)"
            } else {
                requestBody["since"] = saved.syncedAt
            }
        }
        let handle: (Result<[String: JSONValue], APIError>) -> Void = { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let answer):
                let list: [JSONValue] = { if case .array(let items)? = answer[feed.listKey] { return items } else { return [] } }()
                let isDelta: Bool = { if case .string("delta")? = answer["mode"] { return true } else { return false } }()
                var merged: [JSONValue]? = list
                if isDelta {
                    if let saved, let ids = answer["ids"]?.stringArray {
                        merged = merge(cached: saved.items, changed: list, ids: ids, restamp: restamp?(answer) ?? { _, _ in })
                    } else {
                        merged = nil
                    }
                }
                // A gap in the merge (or no copy to merge onto): download in full
                guard let merged else {
                    Logger.info("🔄 \(feed.rawValue): changes-only merge incomplete, downloading in full")
                    fetch(feed, endpoint: endpoint, method: method, body: body, cacheKey: cacheKey, restamp: restamp,
                          allowDelta: false, completion: completion)
                    return
                }
                if let userId, case .string(let syncedAt)? = answer["syncedAt"] {
                    save(feed, merged, syncedAt: syncedAt, userId: userId, key: cacheKey, fullDownload: !isDelta)
                }
                if isDelta { Logger.debug("🔄 \(feed.rawValue): \(list.count) changed of \(merged.count)") }
                do {
                    completion(.success(try JSONEncoder().encode(JSONValue.object(["success": .bool(true), feed.listKey: .array(merged)]))))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        APIService.shared.request(endpoint: requestEndpoint, method: method, body: method == .get ? nil : requestBody,
                                  requiresAuth: true, completion: handle)
    }

    // MARK: - The saved copies

    struct Snapshot: Codable {
        let syncedAt: String
        let savedAt: Date
        let appVersion: String
        let items: [JSONValue]

        private enum CodingKeys: String, CodingKey { case syncedAt, savedAt, appVersion, items, places }
        init(syncedAt: String, savedAt: Date, appVersion: String, items: [JSONValue]) {
            self.syncedAt = syncedAt; self.savedAt = savedAt; self.appVersion = appVersion; self.items = items
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            syncedAt = try c.decode(String.self, forKey: .syncedAt)
            savedAt = try c.decode(Date.self, forKey: .savedAt)
            appVersion = try c.decode(String.self, forKey: .appVersion)
            // Copies saved by the first build (places/batch only) called the list `places`
            items = try c.decodeIfPresent([JSONValue].self, forKey: .items) ?? c.decode([JSONValue].self, forKey: .places)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(syncedAt, forKey: .syncedAt); try c.encode(savedAt, forKey: .savedAt)
            try c.encode(appVersion, forKey: .appVersion); try c.encode(items, forKey: .items)
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "")(\(info?["CFBundleVersion"] ?? ""))"
    }

    private static var baseURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DeltaSync", isDirectory: true)
    }

    private static func fileURL(_ feed: Feed, userId: String, key: String) -> URL? {
        let hash = SHA256.hash(data: Data((userId + "|" + key).utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return baseURL?.appendingPathComponent(feed.rawValue, isDirectory: true).appendingPathComponent("\(hash).json")
    }

    /// The saved copy when it's good to merge onto
    static func load(_ feed: Feed, userId: String, key: String, now: Date = Date()) -> Snapshot? {
        guard let url = fileURL(feed, userId: userId, key: key),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.appVersion == appVersion,
              now.timeIntervalSince(snapshot.savedAt) < fullRefreshInterval else { return nil }
        return snapshot
    }

    /// Keeps a merged copy's original full-download time, so the daily full
    /// refresh still comes round; prunes the oldest copies past the feed's cap
    static func save(_ feed: Feed, _ items: [JSONValue], syncedAt: String, userId: String, key: String, fullDownload: Bool) {
        guard let url = fileURL(feed, userId: userId, key: key) else { return }
        let savedAt = fullDownload ? Date() : (load(feed, userId: userId, key: key)?.savedAt ?? Date())
        let snapshot = Snapshot(syncedAt: syncedAt, savedAt: savedAt, appVersion: appVersion, items: items)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune(folder, keep: feed.keepCopies)
    }

    private static func prune(_ folder: URL, keep: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard files.count > keep else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keep) { try? FileManager.default.removeItem(at: file) }
    }

    /// Signed out: nobody else's lists stay on the phone
    static func clearAll() {
        guard let base = baseURL else { return }
        try? FileManager.default.removeItem(at: base)
        // The first build kept places/batch copies here
        if let old = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PlaceBatch", isDirectory: true) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}

/// JSON exactly as it came over the wire, so a saved item decodes later
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

    /// An item's id as the server writes it
    var itemId: String? {
        guard case .object(let fields) = self else { return nil }
        if case .string(let id)? = fields["id"] { return id }
        if case .string(let id)? = fields["_id"] { return id }
        return nil
    }

    var stringArray: [String] {
        guard case .array(let values) = self else { return [] }
        return values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }
}
