import Foundation
import CoreLocation

/// Decides, from real location fixes, whether the phone has ARRIVED at a
/// saved place — walked in the door — or merely passed it.
///
/// iOS region monitoring can't fire reliably under ~100 m and computes entry
/// from coarse cell/WiFi position, so a region entry alone says "somewhere
/// near". `DwellCheckInMonitor` uses the entry only as a wake-up, then feeds
/// the fixes it takes to this verifier, which answers the moment two
/// consecutive good fixes put the phone within `arrivalRadius` of the pin at
/// walking pace. Nothing here waits on a timer, and a fix that says the
/// phone is driving, or already outside, ends the question at once.
///
/// Pure so the thresholds are testable; the monitor owns the location
/// manager and the notification.
struct ArrivalVerifier {
    enum Thresholds {
        /// From the venue pin: "at the door", not "on the block".
        static let arrivalRadius: CLLocationDistance = 30
        /// A fix must be at least this good to count towards arrival.
        static let arrivalAccuracy: CLLocationDistance = 30
        /// At or under this the phone is walking or standing.
        static let walkingSpeed: CLLocationSpeed = 2.0
        /// Consecutive fixes that must agree before arriving or driving.
        static let confirmingFixes = 2
        /// Over this on consecutive fixes the phone is in a vehicle.
        static let drivingSpeed: CLLocationSpeed = 3.0
        /// A fix this poor says nothing about anything.
        static let unusableAccuracy: CLLocationDistance = 150
        /// The accuracy allowance when judging "outside", capped so a poor
        /// fix can't keep a departed phone "inside" forever.
        static let outsideSlackCap: CLLocationDistance = 50
        /// Core Location replays its cached fix first; anything older than
        /// this before the watch began is that replay, not a reading.
        static let staleFixGrace: TimeInterval = 15
        /// Give up after this: nothing fires, nothing is consumed.
        static let maxWatch: TimeInterval = 4 * 60
    }

    enum Verdict: Equatable {
        case watching
        case arrived
        case leftRegion
        case driving
        case inconclusive
    }

    let center: CLLocation
    let radius: CLLocationDistance
    let startedAt: Date
    private(set) var verdict: Verdict = .watching

    private var previousUsable: CLLocation?
    private var arrivalStreak = 0
    private var drivingStreak = 0

    init(center: CLLocationCoordinate2D, radius: CLLocationDistance, startedAt: Date) {
        self.center = CLLocation(latitude: center.latitude, longitude: center.longitude)
        self.radius = radius
        self.startedAt = startedAt
    }

    /// Feed one fix. The verdict is terminal once it leaves `.watching`.
    @discardableResult
    mutating func observe(_ fix: CLLocation) -> Verdict {
        guard verdict == .watching else { return verdict }
        let accuracy = fix.horizontalAccuracy
        guard accuracy >= 0, accuracy <= Thresholds.unusableAccuracy,
              fix.timestamp >= startedAt.addingTimeInterval(-Thresholds.staleFixGrace) else { return verdict }

        let distance = fix.distance(from: center)
        let speed = Self.speed(of: fix, after: previousUsable)
        previousUsable = fix

        if distance > radius + min(accuracy, Thresholds.outsideSlackCap) {
            verdict = .leftRegion
            return verdict
        }

        if let speed, speed > Thresholds.drivingSpeed {
            drivingStreak += 1
            if drivingStreak >= Thresholds.confirmingFixes { verdict = .driving; return verdict }
        } else {
            drivingStreak = 0
        }

        let atTheDoor = distance <= Thresholds.arrivalRadius
            && accuracy <= Thresholds.arrivalAccuracy
            && (speed ?? 0) <= Thresholds.walkingSpeed
        if atTheDoor {
            arrivalStreak += 1
            if arrivalStreak >= Thresholds.confirmingFixes { verdict = .arrived }
        } else {
            arrivalStreak = 0
        }
        return verdict
    }

    /// The watch's own clock: past `maxWatch` with no answer is no answer.
    @discardableResult
    mutating func deadlineReached(at now: Date) -> Verdict {
        guard verdict == .watching else { return verdict }
        if now >= startedAt.addingTimeInterval(Thresholds.maxWatch) { verdict = .inconclusive }
        return verdict
    }

    /// The fix's own speed when it has one; otherwise derived from the
    /// previous usable fix. WiFi/cell fixes — and every simulated one — carry
    /// no speed, and without this the phone could never be seen driving.
    /// nil for the first fix.
    static func speed(of fix: CLLocation, after previous: CLLocation?) -> CLLocationSpeed? {
        if fix.speed >= 0 { return fix.speed }
        guard let previous else { return nil }
        let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard dt >= 1 else { return nil }
        return fix.distance(from: previous) / dt
    }
}
