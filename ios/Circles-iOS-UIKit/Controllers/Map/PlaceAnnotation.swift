import MapKit

// Custom map annotation class for places
class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place
    
    var coordinate: CLLocationCoordinate2D {
        if let location = place.location?.clLocation {
            return location.coordinate
        }
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    var title: String? {
        // Add "NEW" prefix if this is a new place
        return (place.isNew == true ? "🆕 " : "") + place.name
    }
    
    var subtitle: String? {
        // Always show who added the place
        return "Added by \(place.addedByDisplayName)"
    }
    
    init(place: Place) {
        self.place = place
        super.init()
    }
}

// Helper to make Place work with MapKit
extension Place {
    func asMapAnnotation() -> PlaceAnnotation {
        return PlaceAnnotation(place: self)
    }
}
