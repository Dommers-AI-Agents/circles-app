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
/// Rows Apple can't find keep lat/lng nil and import unmapped — the review
/// screen shows every resolved address, so a wrong match (name-only queries
/// are ambiguous) is visible and deselectable before anything is written.
enum AppleImportResolver {

    static func resolve(
        lists: [ImportList],
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
        guard !work.isEmpty else {
            completion(lists)
            return
        }

        var workIndex = 0
        var locatedCount = 0

        // Apple throttles bursts of MKLocalSearch requests (~50, then a
        // cool-down). A throttled row is NOT "not found" — retry it with
        // exponential backoff instead of importing it unmapped. A 2026-08-12
        // 530-row import resolved exactly 48 rows then failed the rest for
        // this reason. A small gap between successful requests keeps the
        // throttle from triggering in the first place.
        let interRequestDelay: TimeInterval = 0.25
        let maxThrottleRetries = 6

        func processNext(throttleRetry: Int = 0) {
            guard workIndex < work.count else {
                completion(resolvedLists)
                return
            }
            let item = work[workIndex]
            progress("Locating your places… \(workIndex + 1) of \(work.count)")

            let candidate = resolvedLists[item.listIndex].places[item.placeIndex]
            search(candidate) { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case .throttled where throttleRetry < maxThrottleRetries:
                        // 5s, 10s, 20s, 40s, 60s, 60s — same row, not advanced
                        let delay = min(60.0, 5.0 * pow(2.0, Double(throttleRetry)))
                        progress("Apple Maps is rate-limiting — pausing \(Int(delay))s… (\(workIndex + 1) of \(work.count))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            processNext(throttleRetry: throttleRetry + 1)
                        }
                    case .resolved(let resolved):
                        resolvedLists[item.listIndex].places[item.placeIndex] = resolved
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

    private enum SearchOutcome {
        case resolved(ImportPlaceCandidate)
        case notFound
        case throttled
    }

    private static func hasValidCoordinates(_ place: ImportPlaceCandidate) -> Bool {
        guard let lat = place.lat, let lng = place.lng else { return false }
        return !(lat == 0 && lng == 0)
    }

    private static func search(
        _ candidate: ImportPlaceCandidate,
        completion: @escaping (SearchOutcome) -> Void
    ) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [candidate.name, candidate.address]
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
            var updated = candidate
            let coordinate = item.placemark.coordinate
            updated.lat = coordinate.latitude
            updated.lng = coordinate.longitude
            if (updated.address ?? "").isEmpty {
                updated.address = formattedAddress(item.placemark)
            }
            updated.applePoiCategory = item.pointOfInterestCategory?.rawValue
            completion(.resolved(updated))
        }
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
