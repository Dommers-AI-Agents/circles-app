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

        func processNext() {
            guard workIndex < work.count else {
                completion(resolvedLists)
                return
            }
            let item = work[workIndex]
            workIndex += 1
            progress("Locating your places… \(workIndex) of \(work.count)")

            let candidate = resolvedLists[item.listIndex].places[item.placeIndex]
            search(candidate) { resolved in
                if let resolved = resolved {
                    resolvedLists[item.listIndex].places[item.placeIndex] = resolved
                    locatedCount += 1
                }
                DispatchQueue.main.async {
                    processNext()
                }
            }
        }

        processNext()
    }

    private static func hasValidCoordinates(_ place: ImportPlaceCandidate) -> Bool {
        guard let lat = place.lat, let lng = place.lng else { return false }
        return !(lat == 0 && lng == 0)
    }

    private static func search(
        _ candidate: ImportPlaceCandidate,
        completion: @escaping (ImportPlaceCandidate?) -> Void
    ) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [candidate.name, candidate.address]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        request.resultTypes = .pointOfInterest

        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else {
                completion(nil)
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
            completion(updated)
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
