import Foundation

/// Which of iOS's visit reports become a "visit" in My Visits (Wes,
/// 2026-11-16: visits were recorded every 5 minutes along I-10 while he was
/// driving). Only a finished CLVisit counts — iOS decides the person stopped
/// somewhere — measured from its own arrival to its own departure. Pure.
enum VisitAcceptance {

    enum Verdict: Equatable {
        case record
        /// iOS reported the arrival; the visit is recorded when it reports the departure
        case notFinished
        /// iOS didn't know when the stay began (distantPast), so its length is unknown
        case unknownArrival
        case tooShort
        /// The fix is rougher than the widest radius a visit is named within
        case tooRough
        /// The same stay was already recorded (iOS can report a visit twice)
        case duplicate
    }

    /// Matches the widest reach VisitPlaceSuggestion names a visit within.
    static let maxAccuracy: Double = 150

    /// Two reports are the same stay when they start within this long of each
    /// other and this close together.
    static let sameStayWindow: TimeInterval = 10 * 60
    static let sameStayDistance: Double = 150

    struct Stay: Equatable {
        let arrival: Date
        let latitude: Double
        let longitude: Double
    }

    static func verdict(arrival: Date, departure: Date, horizontalAccuracy: Double,
                        minDuration: TimeInterval, latitude: Double, longitude: Double,
                        recorded: [Stay]) -> Verdict {
        if departure == .distantFuture { return .notFinished }
        if arrival == .distantPast { return .unknownArrival }
        if departure.timeIntervalSince(arrival) < minDuration { return .tooShort }
        if horizontalAccuracy < 0 || horizontalAccuracy > maxAccuracy { return .tooRough }
        let duplicate = recorded.contains { stay in
            abs(stay.arrival.timeIntervalSince(arrival)) <= sameStayWindow
                && distance(stay.latitude, stay.longitude, latitude, longitude) <= sameStayDistance
        }
        return duplicate ? .duplicate : .record
    }

    /// Minutes between arrival and departure, as the server stores it.
    static func durationMinutes(arrival: Date, departure: Date) -> Int {
        max(0, Int(departure.timeIntervalSince(arrival) / 60))
    }

    /// Haversine metres; good enough at visit scale.
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
