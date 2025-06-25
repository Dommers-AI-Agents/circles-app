import SwiftUI
import GoogleMaps
import CoreLocation

struct CirclePlacesMapView: View {
    let places: [Place]
    @Binding var mapCenter: CLLocationCoordinate2D
    let mapZoom: Float
    let onPlaceTapped: (Place) -> Void
    let onPOITapped: (String, String, CLLocationCoordinate2D) -> Void
    
    var body: some View {
        GoogleMapView(
            center: $mapCenter,
            zoom: mapZoom,
            markers: places.compactMap { place -> GoogleMapMarker? in
                guard let location = place.location?.clLocation else { return nil }
                return GoogleMapMarker(place: place)
            },
            showsUserLocation: true,
            onMarkerTapped: { marker in
                // Find the place associated with this marker
                if let place = places.first(where: { $0.id == marker.placeID }) {
                    onPlaceTapped(place)
                }
            },
            showUserLocationCircle: false,
            onPOITapped: onPOITapped
        )
    }
}

#Preview {
    CirclePlacesMapView(
        places: [],
        mapCenter: .constant(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        mapZoom: 12,
        onPlaceTapped: { _ in },
        onPOITapped: { _, _, _ in }
    )
}