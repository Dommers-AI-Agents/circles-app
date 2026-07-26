import Foundation
import MapKit
import CoreLocation

// PlaceSearchDelegate protocol and PlaceSearchAnnotation model used by
// AddPlaceViewController. Extracted from the controller file (Wave 4).

protocol PlaceSearchDelegate: AnyObject {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?)
    // Optional method for selecting user's saved places
    func didSelectExistingPlace(_ place: Place)
}

// Provide default implementation to make it effectively optional
extension PlaceSearchDelegate {
    func didSelectExistingPlace(_ place: Place) {
        // Default implementation does nothing
        // Classes that don't need this functionality don't have to implement it
    }
}

// Custom annotation class for place search
class PlaceSearchAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    var title: String?
    var subtitle: String?
    var placeId: String?
    var mapItem: MKMapItem?
    var isTemporary: Bool = false
}

