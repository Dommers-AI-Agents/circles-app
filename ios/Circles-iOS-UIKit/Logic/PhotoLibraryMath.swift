import Foundation
import CoreLocation

/// The photo library as places (Wes, 2026-10-09): which of your photos were
/// taken at a place, where you stopped on a day out, where home is, and which
/// days were trips. Pure; Services/PhotoLibraryIndex supplies the shots.
enum PhotoLibraryMath {
    /// One photo: where and when it was taken (`id` = the library's asset id)
    struct Shot: Codable, Equatable {
        let id: String
        let lat: Double
        let lng: Double
        let date: Date
        /// The phone's error estimate for the fix, meters (nil = not recorded)
        var acc: Double? = nil
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    /// A stop: photos taken together at one spot
    struct Spot: Equatable {
        let shots: [Shot]           // in the order taken
        /// Weighted by each fix's accuracy (PhotoPlaceGrouper.estimate)
        let center: CLLocationCoordinate2D
        /// How far off `center` may be, meters
        var uncertainty: Double = PhotoPlaceGrouper.assumedAccuracy
        var start: Date { shots.first!.date }
        var end: Date { shots.last!.date }
        static func == (a: Spot, b: Spot) -> Bool { a.shots == b.shots }
    }

    /// Days away from home, back to back
    struct Trip: Equatable {
        let start: Date
        let end: Date
        let shots: [Shot]
        let center: CLLocationCoordinate2D
        static func == (a: Trip, b: Trip) -> Bool { a.shots == b.shots }
    }

    static let placeRadius: CLLocationDistance = 75
    static let stopRadius: CLLocationDistance = 75
    /// A stop is real with 2+ photos or 10+ minutes there — not one shot from the car
    static let minStopMinutes: Double = 10
    /// A day counts as away when its photos are mostly this far from home
    static let awayKm: Double = 50

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Photos taken within `radius` of a place, newest first.
    static func near(_ shots: [Shot], center: CLLocationCoordinate2D, radius: CLLocationDistance = placeRadius,
                     limit: Int = 24) -> [Shot] {
        Array(shots.filter { distance($0.coordinate, center) <= radius }.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Stops, walking the photos in time order: a new stop starts once a
    /// photo is more than `stopRadius` from the current one's center. Linear,
    /// so a year of photos is fine.
    static func spots(_ shots: [Shot]) -> [Spot] {
        var out: [Spot] = []
        var current: [Shot] = []
        func flush() {
            guard let best = PhotoPlaceGrouper.estimate(current.map { ($0.coordinate, $0.acc) }) else { return }
            let minutes = (current.last!.date.timeIntervalSince(current.first!.date)) / 60
            if current.count >= 2 || minutes >= minStopMinutes {
                out.append(Spot(shots: current, center: best.center, uncertainty: best.uncertainty))
            }
        }
        for shot in shots.sorted(by: { $0.date < $1.date }) {
            if let center = PhotoPlaceGrouper.median(current.map(\.coordinate)), distance(center, shot.coordinate) > stopRadius {
                flush()
                current = []
            }
            current.append(shot)
        }
        flush()
        return out
    }

    /// Where they live: the ~110 m square photographed on the most distinct
    /// days, centred on the median of the photos in it and its neighbours.
    /// (It used ~1 km squares and their average, which drifted toward the
    /// neighborhood's cafés and let home itself through as a "place" again
    /// and again; Wes, 2026-10-17.)
    static func home(_ shots: [Shot], calendar: Calendar = .current) -> CLLocationCoordinate2D? {
        func cell(_ s: Shot) -> (Int, Int) { (Int((s.lat * 1000).rounded()), Int((s.lng * 1000).rounded())) }
        var days: [String: Set<DateComponents>] = [:]
        for s in shots {
            let c = cell(s)
            days["\(c.0):\(c.1)", default: []].insert(calendar.dateComponents([.year, .month, .day], from: s.date))
        }
        guard let best = days.max(by: { $0.value.count < $1.value.count })?.key else { return nil }
        let parts = best.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let near = shots.filter { abs(cell($0).0 - parts[0]) <= 1 && abs(cell($0).1 - parts[1]) <= 1 }
        return PhotoPlaceGrouper.median(near.map(\.coordinate))
    }

    /// How far around home a stop is treated as home (GPS indoors drifts)
    static let homeRadius: CLLocationDistance = 200

    /// Trips: days whose photos are mostly `awayKm`+ from home, joined when
    /// back to back (one quiet day between is still the same trip). Newest first.
    static func trips(_ shots: [Shot], home: CLLocationCoordinate2D, calendar: Calendar = .current, minShots: Int = 3) -> [Trip] {
        let byDay = Dictionary(grouping: shots) { calendar.startOfDay(for: $0.date) }
        let awayDays = byDay.filter { _, dayShots in
            let far = dayShots.filter { distance($0.coordinate, home) >= awayKm * 1000 }.count
            return Double(far) / Double(dayShots.count) > 0.5
        }.keys.sorted()
        var runs: [[Date]] = []
        for day in awayDays {
            if let last = runs.last?.last, let gap = calendar.dateComponents([.day], from: last, to: day).day, gap <= 2 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.compactMap { run -> Trip? in
            let tripShots = run.flatMap { byDay[$0] ?? [] }
                .filter { distance($0.coordinate, home) >= awayKm * 1000 }
                .sorted { $0.date < $1.date }
            guard tripShots.count >= minShots, let center = PhotoPlaceGrouper.median(tripShots.map(\.coordinate)) else { return nil }
            return Trip(start: run.first!, end: run.last!, shots: tripShots, center: center)
        }.sorted { $0.start > $1.start }
    }

    /// Stops near home or an existing save don't become new places.
    static func isSkippable(_ spot: Spot, home: CLLocationCoordinate2D?, saved: [CLLocationCoordinate2D]) -> Bool {
        if let home, distance(spot.center, home) <= homeRadius { return true }
        return saved.contains { distance($0, spot.center) <= placeRadius }
    }

    /// How good the library's locations are, for one analytics event per
    /// scan (tunes the accuracy rules from real phones): photo counts by the
    /// phone's error estimate, and the middle spot's uncertainty in meters.
    static func accuracyReport(shots: [Shot], spotUncertainties: [Double]) -> [String: String] {
        var buckets = ["acc_le10": 0, "acc_le30": 0, "acc_le65": 0, "acc_gt65": 0, "acc_none": 0]
        for shot in shots {
            guard let acc = shot.acc else { buckets["acc_none", default: 0] += 1; continue }
            let key = acc <= 10 ? "acc_le10" : acc <= 30 ? "acc_le30" : acc <= 65 ? "acc_le65" : "acc_gt65"
            buckets[key, default: 0] += 1
        }
        var out = buckets.mapValues(String.init)
        let sorted = spotUncertainties.sorted()
        out["spot_uncertainty_median"] = sorted.isEmpty ? "0" : String(Int(sorted[sorted.count / 2].rounded()))
        out["spots"] = String(sorted.count)
        return out
    }

    /// "Charleston · Sep 2026" / "Sep 12–15, 2026"
    static func circleName(place: String?, start: Date, end: Date, calendar: Calendar = .current) -> String {
        let month = DateFormatter()
        month.calendar = calendar
        month.setLocalizedDateFormatFromTemplate("MMM yyyy")
        if let place, !place.isEmpty { return "\(place) · \(month.string(from: start))" }
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: end)
    }
}
