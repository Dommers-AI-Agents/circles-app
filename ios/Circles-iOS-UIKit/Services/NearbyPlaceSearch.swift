import Foundation
import MapKit

protocol NearbyPlaceSearchDelegate: AnyObject {
    /// New autocomplete suggestions arrived for the current query.
    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didUpdate completions: [MKLocalSearchCompletion])
    /// About to resolve a chosen suggestion (show a spinner if desired).
    func nearbyPlaceSearchWillResolve(_ search: NearbyPlaceSearch)
    /// A suggestion resolved to a Place — either an existing saved place or a
    /// new (unsaved) place with an empty circleId that the backend creates on
    /// submit.
    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didResolve place: Place)
    /// The completer or resolution failed.
    func nearbyPlaceSearch(_ search: NearbyPlaceSearch, didFailWith error: Error)
}

/// Shared Apple-Maps POI search used by BOTH the check-in and moment place
/// pickers so typing a place name (e.g. "Hilton") behaves identically in each.
///
/// - `MKLocalSearchCompleter` provides live suggestions as the user types.
/// - `MKLocalSearch` resolves a chosen suggestion into a `Place`. When the
///   resolved venue already matches one of the user's saved places we return
///   that existing place (avoiding a duplicate); otherwise we build a new
///   unsaved `Place` (empty circleId) carrying the coordinates the backend
///   needs to create it.
final class NearbyPlaceSearch: NSObject {

    weak var delegate: NearbyPlaceSearchDelegate?

    private let completer = MKLocalSearchCompleter()

    /// Bias suggestions/resolution toward the user's current area.
    var region: MKCoordinateRegion? {
        didSet { if let region = region { completer.region = region } }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
    }

    /// Feed the completer the latest query fragment. Pass "" to clear.
    func updateQuery(_ query: String) {
        completer.queryFragment = query
    }

    /// Resolve a chosen suggestion into a `Place`. `existingPlaces` lets us
    /// reuse a saved place instead of creating a duplicate.
    func resolve(_ completion: MKLocalSearchCompletion,
                 near location: CLLocation?,
                 existingPlaces: [Place]) {
        delegate?.nearbyPlaceSearchWillResolve(self)

        let request = MKLocalSearch.Request(completion: completion)
        if let location = location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 10000,
                longitudinalMeters: 10000
            )
        }

        MKLocalSearch(request: request).start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.delegate?.nearbyPlaceSearch(self, didFailWith: error)
                    return
                }
                guard let item = response?.mapItems.first else {
                    self.delegate?.nearbyPlaceSearch(self, didFailWith: NearbyPlaceSearchError.noDetails)
                    return
                }

                let name = item.name ?? completion.title
                let address = item.placemark.title ?? completion.subtitle

                // Prefer an existing saved place so we don't duplicate a venue
                // the user already has (matches check-in's original behavior).
                if let existing = existingPlaces.first(where: { place in
                    place.name.lowercased() == name.lowercased() &&
                    place.address.lowercased().contains(address.lowercased().prefix(20))
                }) {
                    self.delegate?.nearbyPlaceSearch(self, didResolve: existing)
                } else {
                    self.delegate?.nearbyPlaceSearch(self, didResolve: NearbyPlaceSearch.newPlace(from: item, name: name, address: address))
                }
            }
        }
    }

    /// Build an unsaved `Place` from a resolved map item. An empty `circleId`
    /// marks it as "new" so both flows know to send creation data on submit.
    static func newPlace(from item: MKMapItem, name: String, address: String) -> Place {
        let coord = item.placemark.coordinate
        return Place(
            id: UUID().uuidString,
            name: name,
            description: nil,
            address: address,
            location: GeoLocation(type: "Point", coordinates: [coord.longitude, coord.latitude]),
            website: item.url?.absoluteString,
            phone: item.phoneNumber,
            googlePlaceId: nil, photos: nil, videos: nil,
            category: .other, customCategoryId: nil, subcategory: nil,
            rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil, publicNotes: nil,
            tags: nil, reviews: nil, openingHours: nil, priceLevel: nil,
            likes: nil, likesCount: nil, commentsCount: nil,
            circleId: "", addedBy: AuthService.shared.getUserId() ?? "", addedByUser: nil,
            privacy: .public, createdAt: Date(), updatedAt: Date(), isNew: nil
        )
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension NearbyPlaceSearch: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        delegate?.nearbyPlaceSearch(self, didUpdate: completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        delegate?.nearbyPlaceSearch(self, didFailWith: error)
    }
}

enum NearbyPlaceSearchError: LocalizedError {
    case noDetails
    var errorDescription: String? {
        switch self {
        case .noDetails: return "Could not get place details"
        }
    }
}
