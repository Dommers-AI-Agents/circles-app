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
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    /// A stop: photos taken together at one spot
    struct Spot: Equatable {
        let shots: [Shot]           // in the order taken
        let center: CLLocationCoordinate2D
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
            guard let center = PhotoPlaceGrouper.median(current.map(\.coordinate)) else { return }
            let minutes = (current.last!.date.timeIntervalSince(current.first!.date)) / 60
            if current.count >= 2 || minutes >= minStopMinutes { out.append(Spot(shots: current, center: center)) }
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

    /// Where you live, as far as the photos say: the ~1 km cell photographed
    /// on the most different days.
    static func home(_ shots: [Shot], calendar: Calendar = .current) -> CLLocationCoordinate2D? {
        var days: [String: Set<DateComponents>] = [:]
        var sums: [String: (lat: Double, lng: Double, n: Double)] = [:]
        for s in shots {
            let key = "\((s.lat * 100).rounded()):\((s.lng * 100).rounded())"
            days[key, default: []].insert(calendar.dateComponents([.year, .month, .day], from: s.date))
            let acc = sums[key] ?? (0, 0, 0)
            sums[key] = (acc.lat + s.lat, acc.lng + s.lng, acc.n + 1)
        }
        guard let best = days.max(by: { $0.value.count < $1.value.count })?.key, let acc = sums[best], acc.n > 0 else { return nil }
        return CLLocationCoordinate2D(latitude: acc.lat / acc.n, longitude: acc.lng / acc.n)
    }

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
        if let home, distance(spot.center, home) <= 150 { return true }
        return saved.contains { distance($0, spot.center) <= placeRadius }
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
