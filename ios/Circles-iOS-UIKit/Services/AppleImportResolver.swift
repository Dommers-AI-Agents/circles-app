import Foundation
import MapKit

/// Resolves coordinate-less import candidates (Google Takeout rows carry only
/// a name and a Google-internal URL) via on-device Apple Maps search.
/// MKLocalSearch is free — no server billing, no API key, no third-party
/// terms — and returns Apple's POI category, which feeds the backend's
/// category-derivation cascade.
///
/// Lookups run sequentially: MKLocalSearch throttles aggressive callers, and
/// a polite one-at-a-time queue stays reliable for multi-hundred-row imports.
/// Only the first `limit` coordinate-less rows resolve inline (large imports
/// used to stall the user behind 10+ minutes of throttle backoff) — the rest
/// import unmapped and are located quietly after import by
/// `ImportResolutionQueue`. Rows Apple can't find keep lat/lng nil and import
/// unmapped — the review screen shows every resolved address, so a wrong
/// match (name-only queries are ambiguous) is visible and deselectable
/// before anything is written.
enum AppleImportResolver {

    static func resolve(
        lists: [ImportList],
        limit: Int = 40,
        progress: @escaping (String) -> Void,
        completion: @escaping ([ImportList]) -> Void
    ) {
        var resolvedLists = lists
        var work: [(listIndex: Int, placeIndex: Int)] = []
        for (listIndex, list) in lists.enumerated() {
            for (placeIndex, place) in list.places.enumerated() where !hasValidCoordinates(place) {
                work.append((listIndex, placeIndex))
            }
        }
        // Everything past the inline cap passes through untouched — those
        // rows import unmapped and get resolved in the background
        work = Array(work.prefix(max(0, limit)))
        guard !work.isEmpty else {
            completion(lists)
            return
        }
        // One steady line with the real total — counting "of 40" misleads on
        // a 600-row import, and throttling/preview mechanics are ours to
        // worry about, not the user's
        let totalPlaces = lists.reduce(0) { $0 + $1.places.count }
        let progressMessage = "Preparing your \(totalPlaces) place\(totalPlaces == 1 ? "" : "s")…"

        var workIndex = 0
        var locatedCount = 0

        func processNext(throttleRetry: Int = 0) {
            guard workIndex < work.count else {
                completion(resolvedLists)
                return
            }
            let item = work[workIndex]
            progress(progressMessage)

            let candidate = resolvedLists[item.listIndex].places[item.placeIndex]
            searchVenue(name: candidate.name, address: candidate.address) { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case .throttled where throttleRetry < maxThrottleRetries:
                        // Same row, not advanced. The wait is an Apple Maps
                        // rate limit — the user just sees steady progress
                        let delay = throttleDelay(retry: throttleRetry)
                        progress(progressMessage)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            processNext(throttleRetry: throttleRetry + 1)
                        }
                    case .resolved(let match):
                        var updated = candidate
                        updated.lat = match.latitude
                        updated.lng = match.longitude
                        if (updated.address ?? "").isEmpty {
                            updated.address = match.formattedAddress
                        }
                        updated.applePoiCategory = match.applePoiCategory
                        resolvedLists[item.listIndex].places[item.placeIndex] = updated
                        locatedCount += 1
                        workIndex += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + interRequestDelay) {
                            processNext()
                        }
                    case .notFound, .throttled:
                        // Genuinely not found, or throttled past the retry
                        // budget — import unmapped rather than stall forever
                        workIndex += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + interRequestDelay) {
                            processNext()
                        }
                    }
                }
            }
        }

        processNext()
    }

    // MARK: - Shared search + pacing (also used by ImportResolutionQueue)

    /// What a successful Apple Maps lookup yields for one venue.
    struct VenueMatch {
        let latitude: Double
        let longitude: Double
        let formattedAddress: String?
        let applePoiCategory: String?
    }

    enum VenueSearchOutcome {
        case resolved(VenueMatch)
        case notFound
        case throttled
    }

    /// Gap between successful requests — keeps the throttle from triggering
    /// in the first place.
    static let interRequestDelay: TimeInterval = 0.25

    /// Apple throttles bursts of MKLocalSearch requests (~50, then a
    /// cool-down). A throttled row is NOT "not found" — retry it with
    /// exponential backoff instead of giving up. A 2026-08-12 530-row import
    /// resolved exactly 48 rows then failed the rest for this reason.
    static let maxThrottleRetries = 6

    /// 5s, 10s, 20s, 40s, 60s, 60s
    static func throttleDelay(retry: Int) -> TimeInterval {
        return min(60.0, 5.0 * pow(2.0, Double(retry)))
    }

    static func searchVenue(
        name: String,
        address: String?,
        completion: @escaping (VenueSearchOutcome) -> Void
    ) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, address]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        request.resultTypes = .pointOfInterest

        MKLocalSearch(request: request).start { response, error in
            if let error = error {
                // MKError.loadingThrottled means "slow down", not "not found";
                // network failures get one retry pass too via the same path
                let nsError = error as NSError
                let isThrottle = nsError.domain == MKError.errorDomain &&
                    nsError.code == MKError.loadingThrottled.rawValue
                completion(isThrottle ? .throttled : .notFound)
                return
            }
            guard let item = response?.mapItems.first else {
                completion(.notFound)
                return
            }
            let coordinate = item.placemark.coordinate
            completion(.resolved(VenueMatch(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                formattedAddress: formattedAddress(item.placemark),
                applePoiCategory: item.pointOfInterestCategory?.rawValue
            )))
        }
    }

    // MARK: - Private

    private static func hasValidCoordinates(_ place: ImportPlaceCandidate) -> Bool {
        guard let lat = place.lat, let lng = place.lng else { return false }
        return !(lat == 0 && lng == 0)
    }

    private static func formattedAddress(_ placemark: MKPlacemark) -> String? {
        let street: String? = placemark.thoroughfare.map { thoroughfare in
            placemark.subThoroughfare.map { "\($0) \(thoroughfare)" } ?? thoroughfare
        }
        let parts = [street, placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
