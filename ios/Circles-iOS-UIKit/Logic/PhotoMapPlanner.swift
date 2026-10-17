import Foundation
import CoreLocation

/// "Build my map from my photos" (Wes, 2026-10-16): which photo spots to try
/// first, and the words on the progress screen. Pure, so the order is tested.
///
/// Nearest first: the free 25 must land around where the person is now (or
/// where they live), so the first map they see is their own neighborhood.
enum PhotoMapPlanner {
    /// Around here, the wider area, then everything else (trips)
    static let nearMeters: CLLocationDistance = 15 * 1609.344
    static let areaMeters: CLLocationDistance = 50 * 1609.344
    /// Places per request (the server takes at most 25)
    static let batchSize = 5

    /// Where "near" is measured from: the phone now, else home, else nowhere.
    static func origin(current: CLLocationCoordinate2D?, home: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        current ?? home
    }

    /// A spot's stable id on this phone (~100 m grid), so a re-run skips it.
    static func key(_ spot: PhotoLibraryMath.Spot) -> String {
        String(format: "%.3f,%.3f", spot.center.latitude, spot.center.longitude)
    }

    /// 0 = within 15 mi, 1 = within 50 mi, 2 = farther. Everything is tier 0
    /// when there's no origin.
    static func tier(_ spot: PhotoLibraryMath.Spot, from origin: CLLocationCoordinate2D?) -> Int {
        guard let origin else { return 0 }
        let d = PhotoLibraryMath.distance(spot.center, origin)
        if d <= nearMeters { return 0 }
        if d <= areaMeters { return 1 }
        return 2
    }

    /// Distinct days a spot was photographed: a regular place beats a one-off.
    static func days(_ spot: PhotoLibraryMath.Spot, calendar: Calendar = .current) -> Int {
        Set(spot.shots.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Nearest tier first; within a tier, places visited on more days, then
    /// the most recent. With no origin: the most-photographed first.
    static func ordered(_ spots: [PhotoLibraryMath.Spot], origin: CLLocationCoordinate2D?,
                        calendar: Calendar = .current) -> [PhotoLibraryMath.Spot] {
        spots.sorted { a, b in
            let ta = tier(a, from: origin), tb = tier(b, from: origin)
            if ta != tb { return ta < tb }
            if origin == nil, a.shots.count != b.shots.count { return a.shots.count > b.shots.count }
            let da = days(a, calendar: calendar), db = days(b, calendar: calendar)
            if da != db { return da > db }
            return a.end > b.end
        }
    }

    /// Spots that may become places: not home or an existing save, not done
    /// on an earlier run.
    static func candidates(_ spots: [PhotoLibraryMath.Spot], home: CLLocationCoordinate2D?,
                           saved: [CLLocationCoordinate2D], done: Set<String>) -> [PhotoLibraryMath.Spot] {
        spots.filter { !PhotoLibraryMath.isSkippable($0, home: home, saved: saved) && !done.contains(key($0)) }
    }

    // MARK: - Words

    static func progressLine(added: Int, checked: Int, total: Int) -> String {
        guard total > 0 else { return "Looking through your photos\u{2026}" }
        return "Added \(added) place\(added == 1 ? "" : "s") \u{00B7} checked \(checked) of \(total) spots"
    }

    static func limitLine(added: Int, freeMax: Int, more: Int) -> String {
        let firstPart = added > 0
            ? "\(added) place\(added == 1 ? "" : "s") added. "
            : "Your \(freeMax) free places are on your map. "
        guard more > 0 else { return firstPart + "Add the rest of your photos' places with Premium." }
        return firstPart + "\(more) more spot\(more == 1 ? "" : "s") in your photos can go on your map with Premium."
    }

    static func doneLine(added: Int) -> String {
        added == 0
            ? "No new places this time. Everything in your photos is already on your map, or wasn't a business."
            : "Added \(added) place\(added == 1 ? "" : "s") to \u{201C}Places from my photos.\u{201D}"
    }
}

/// Spots already handled on this phone, per account.
enum PhotoMapProgressStore {
    private static func key(_ uid: String) -> String { "photoMap.done.\(uid)" }

    static func done(uid: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(uid)) ?? [])
    }

    static func markDone(_ keys: [String], uid: String, defaults: UserDefaults = .standard) {
        guard !keys.isEmpty else { return }
        defaults.set(Array(done(uid: uid, defaults: defaults).union(keys)), forKey: key(uid))
    }
}
