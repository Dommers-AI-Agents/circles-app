import CoreLocation

/// "From photos": which picked photos were taken at the same spot. Photos
/// keep their GPS fix and capture time even with no signal, so a day out can
/// be saved later (Wes, 2026-10-04). Pure; the Pick photos way of Add from photos reads the
/// metadata and runs the lookups.
enum PhotoPlaceGrouper {
    struct Fix: Equatable {
        let id: Int
        let coordinate: CLLocationCoordinate2D?
        let takenAt: Date?
        /// The phone's own error estimate for this fix, in meters (nil = unknown)
        var accuracy: Double? = nil

        static func == (a: Fix, b: Fix) -> Bool {
            a.id == b.id && a.takenAt == b.takenAt && a.accuracy == b.accuracy
                && a.coordinate?.latitude == b.coordinate?.latitude && a.coordinate?.longitude == b.coordinate?.longitude
        }
    }

    struct Group {
        let photoIds: [Int]                       // in the order taken
        let center: CLLocationCoordinate2D?       // nil = these photos don't say where
        let takenAt: Date?                        // the first photo's time
        var uncertainty: Double = assumedAccuracy // meters, see `estimate`
    }

    /// Where a spot really is and how sure we are (meters).
    struct Estimate: Equatable {
        let center: CLLocationCoordinate2D
        let uncertainty: Double
        static func == (a: Estimate, b: Estimate) -> Bool {
            a.uncertainty == b.uncertainty && a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
        }
    }

    /// A fix with no error estimate counts as a typical indoor one
    static let assumedAccuracy: Double = 30
    /// Fixes worse than this are dropped when the spot has any better ones
    static let worstUsefulAccuracy: Double = 100
    /// Never claim to know a spot better than this
    static let minUncertainty: Double = 8

    /// The spot from its photos' fixes, each weighted by how sure the phone
    /// was (1/accuracy²), so one 120 m indoor fix can't drag five 8 m ones
    /// (2026-10-17). Fixes far off the accuracy-weighted median for their
    /// own accuracy go first (the plain median let three rough fixes outvote
    /// two sharp ones); very rough ones go when better ones exist. Photos at one spot
    /// share most of their error (same walls, same Wi-Fi), so more photos
    /// sharpen it only up to 2×.
    static func estimate(_ fixes: [(coordinate: CLLocationCoordinate2D, accuracy: Double?)]) -> Estimate? {
        guard !fixes.isEmpty else { return nil }
        let rated = fixes.map { (c: $0.coordinate, acc: max(3, $0.accuracy.flatMap { $0 > 0 ? $0 : nil } ?? assumedAccuracy)) }
        func weightedMid(_ values: [(v: Double, w: Double)]) -> Double {
            let sorted = values.sorted { $0.v < $1.v }
            let half = sorted.reduce(0) { $0 + $1.w } / 2
            var run = 0.0
            for item in sorted { run += item.w; if run >= half { return item.v } }
            return sorted.last!.v
        }
        let middle = CLLocationCoordinate2D(latitude: weightedMid(rated.map { ($0.c.latitude, 1 / ($0.acc * $0.acc)) }),
                                            longitude: weightedMid(rated.map { ($0.c.longitude, 1 / ($0.acc * $0.acc)) }))
        var keep = rated.filter { distance($0.c, middle) <= max(3 * $0.acc, 25) }
        if keep.isEmpty { keep = rated }
        if keep.contains(where: { $0.acc <= worstUsefulAccuracy }) { keep = keep.filter { $0.acc <= worstUsefulAccuracy } }
        var wSum = 0.0, lat = 0.0, lng = 0.0
        for f in keep {
            let w = 1 / (f.acc * f.acc)
            wSum += w; lat += f.c.latitude * w; lng += f.c.longitude * w
        }
        let typical = (Double(keep.count) / wSum).squareRoot()
        let uncertainty = max(minUncertainty, typical / Double(min(keep.count, 4)).squareRoot())
        return Estimate(center: CLLocationCoordinate2D(latitude: lat / wSum, longitude: lng / wSum), uncertainty: uncertainty)
    }

    /// Photos within this distance of each other (directly or through a
    /// chain) are one place.
    static let radiusMeters: CLLocationDistance = 75

    /// Groups in the order they were taken; photos with no location last.
    static func group(_ fixes: [Fix]) -> [Group] {
        let located = fixes.filter { $0.coordinate != nil }
        let unknown = fixes.filter { $0.coordinate == nil }

        // Single-link clustering (n ≤ 30, so pairwise is fine)
        var parent = Array(located.indices)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in located.indices {
            for j in located.indices where j > i {
                if distance(located[i].coordinate!, located[j].coordinate!) <= radiusMeters {
                    parent[root(i)] = root(j)
                }
            }
        }
        var clusters: [Int: [Fix]] = [:]
        for i in located.indices { clusters[root(i), default: []].append(located[i]) }

        var groups = clusters.values.map { members -> Group in
            let ordered = members.sorted(by: earlier)
            let best = estimate(ordered.compactMap { f in f.coordinate.map { ($0, f.accuracy) } })
            return Group(photoIds: ordered.map(\.id), center: best?.center,
                         takenAt: ordered.compactMap(\.takenAt).min(), uncertainty: best?.uncertainty ?? assumedAccuracy)
        }
        groups.sort { a, b in
            switch (a.takenAt, b.takenAt) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.photoIds.first ?? 0 < b.photoIds.first ?? 0
            }
        }
        if !unknown.isEmpty {
            let ordered = unknown.sorted(by: earlier)
            groups.append(Group(photoIds: ordered.map(\.id), center: nil, takenAt: ordered.compactMap(\.takenAt).min()))
        }
        return groups
    }

    private static func earlier(_ a: Fix, _ b: Fix) -> Bool {
        switch (a.takenAt, b.takenAt) {
        case let (x?, y?): return x == y ? a.id < b.id : x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.id < b.id
        }
    }

    /// Median latitude and longitude: one stray fix doesn't drag the spot.
    static func median(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coords.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double {
            let s = values.sorted(); let n = s.count
            return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }
        return CLLocationCoordinate2D(latitude: mid(coords.map(\.latitude)), longitude: mid(coords.map(\.longitude)))
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
