import Foundation
import CoreLocation

/// Where "near me" is measured from.
///
/// The home search once took the map's centre as its origin whenever the
/// phone had no fresh fix. That centre is the region fitted to the person's
/// pins, so someone standing in Charlotte with a New Jersey-heavy map got
/// Belmar first. The phone nearly always knows better than that — a fix from
/// a minute ago, the OS's own cache, the last good fix we saved, even the
/// server's last known position — and the map centre must only ever be the
/// answer when there is nothing else.
enum SearchOriginResolver {
    enum Source: String {
        /// A fix this process received from Core Location.
        case serviceFix
        /// CLLocationManager's own cache: survives launches, needs no network.
        case osCachedFix
        /// The last good fix we persisted, in case the OS cache is empty.
        case persistedFix
        /// What the app last told the server on open.
        case serverLastKnown
        /// The server's guess from where the person saves places.
        case serverAssumed
        /// The map's centre. Last resort only.
        case mapRegion
    }

    struct Candidate: Equatable {
        let location: CLLocation
        let source: Source

        static func == (lhs: Candidate, rhs: Candidate) -> Bool {
            lhs.source == rhs.source
                && lhs.location.coordinate.latitude == rhs.location.coordinate.latitude
                && lhs.location.coordinate.longitude == rhs.location.coordinate.longitude
        }
    }

    struct Resolution: Equatable {
        let location: CLLocation
        let source: Source

        static func == (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.source == rhs.source
                && lhs.location.coordinate.latitude == rhs.location.coordinate.latitude
                && lhs.location.coordinate.longitude == rhs.location.coordinate.longitude
        }
    }

    /// A device fix younger than this beats anything the server remembers.
    static let deviceFixMaxAge: TimeInterval = 24 * 60 * 60

    private static let deviceSources: [Source] = [.serviceFix, .osCachedFix, .persistedFix]

    static func isUsable(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate) && !(coordinate.latitude == 0 && coordinate.longitude == 0)
    }

    static func resolve(_ candidates: [Candidate], now: Date = Date()) -> Resolution? {
        let usable = candidates.filter { isUsable($0.location.coordinate) }
        let device = usable
            .filter { deviceSources.contains($0.source) && now.timeIntervalSince($0.location.timestamp) <= deviceFixMaxAge }
            .max { $0.location.timestamp < $1.location.timestamp }
        if let device { return Resolution(location: device.location, source: device.source) }
        for source in [Source.serverLastKnown, .serverAssumed, .mapRegion] {
            if let hit = usable.first(where: { $0.source == source }) {
                return Resolution(location: hit.location, source: source)
            }
        }
        return nil
    }
}

/// The last good fix, kept across launches so the first search after a cold
/// start already knows roughly where the phone is.
struct PersistedFix: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
    }

    init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    /// Rebuilt with its ORIGINAL timestamp, so its age is judged honestly.
    var location: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                   altitude: 0, horizontalAccuracy: 100, verticalAccuracy: -1, timestamp: timestamp)
    }
}
