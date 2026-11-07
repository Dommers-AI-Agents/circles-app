import Foundation
import MapKit

/// The Add Place sheet's rules (Wes, 2026-11-07: "Search for a place / Add
/// from photos" read badly). Pure, tested.
enum AddPlaceSheetCopy {
    static let title = "Add a place"
    static let nearTitle = "You're near"
    static let searchTitle = "Search by name"
    static let searchDetail = "Any place, anywhere"
    static let mapTitle = "Pick on the map"
    static let mapDetail = "Tap the spot on a map"
    static let photosTitle = "From your photos"
    static let photosDetail = "The places your photos were taken"

    /// Places worth saving, not the things around them
    static let skipped: Set<MKPointOfInterestCategory> = [
        .parking, .atm, .publicTransport, .restroom, .evCharger, .gasStation, .police, .fireStation, .postOffice
    ]

    static let nearbyRadius: CLLocationDistance = 250
    static let nearbyCount = 5

    /// The nearest few, closest first, one per name
    static func nearest(_ places: [(name: String, distance: CLLocationDistance)], limit: Int = nearbyCount) -> [String] {
        var seen = Set<String>()
        return places.sorted { $0.distance < $1.distance }
            .filter { seen.insert($0.name.lowercased()).inserted }
            .prefix(limit).map(\.name)
    }

    static func saved(in circleName: String) -> String { "Saved to \(circleName)" }
}
