import Foundation
import CoreLocation

/// Recent answers to search lookups, so backing up a letter, flipping
/// Places/People or a re-sort after a location fix costs nothing instead of
/// another round trip per channel. Small, short-lived and per session —
/// stale-while-revalidate is not the point here; repeat keystrokes are.
final class SearchResultCache<Value> {
    struct Key: Hashable {
        let channel: String
        let query: String
        /// The search origin snapped to a ~500 m cell; nil = no origin
        let cell: String?

        init(channel: String, query: String, origin: CLLocationCoordinate2D?) {
            self.channel = channel
            self.query = PlaceSearchText.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
            self.cell = origin.map(Self.cell(for:))
        }

        /// ~0.005° ≈ 550 m of latitude: a walk across the street keeps the cache.
        static func cell(for coordinate: CLLocationCoordinate2D) -> String {
            let step = 0.005
            let lat = (coordinate.latitude / step).rounded()
            let lng = (coordinate.longitude / step).rounded()
            return "\(Int(lat)):\(Int(lng))"
        }
    }

    private struct Entry { let value: Value; let storedAt: Date }

    let capacity: Int
    let ttl: TimeInterval
    private let now: () -> Date
    private var entries: [Key: Entry] = [:]
    /// Least recently used first
    private var order: [Key] = []

    init(capacity: Int = 50, ttl: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.capacity = capacity
        self.ttl = ttl
        self.now = now
    }

    var count: Int { entries.count }

    func value(for key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) <= ttl else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.value
    }

    func store(_ value: Value, for key: Key) {
        entries[key] = Entry(value: value, storedAt: now())
        touch(key)
        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
    }

    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func remove(_ key: Key) {
        entries[key] = nil
        order.removeAll { $0 == key }
    }
}
