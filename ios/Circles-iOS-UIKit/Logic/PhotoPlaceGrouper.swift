import CoreLocation

/// "From photos": which picked photos were taken at the same spot. Photos
/// keep their GPS fix and capture time even with no signal, so a day out can
/// be saved later (Wes, 2026-10-04). Pure; PhotoPlacesViewController reads the
/// metadata and runs the lookups.
enum PhotoPlaceGrouper {
    struct Fix: Equatable {
        let id: Int
        let coordinate: CLLocationCoordinate2D?
        let takenAt: Date?

        static func == (a: Fix, b: Fix) -> Bool {
            a.id == b.id && a.takenAt == b.takenAt
                && a.coordinate?.latitude == b.coordinate?.latitude && a.coordinate?.longitude == b.coordinate?.longitude
        }
    }

    struct Group {
        let photoIds: [Int]                       // in the order taken
        let center: CLLocationCoordinate2D?       // nil = these photos don't say where
        let takenAt: Date?                        // the first photo's time
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
            return Group(photoIds: ordered.map(\.id), center: median(ordered.compactMap(\.coordinate)),
                         takenAt: ordered.compactMap(\.takenAt).min())
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
