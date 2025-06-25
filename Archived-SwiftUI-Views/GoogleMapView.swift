import SwiftUI
import GoogleMaps
import GooglePlaces

struct GoogleMapView: UIViewRepresentable {
    @Binding var center: CLLocationCoordinate2D
    var zoom: Float = 15.0
    var markers: [GoogleMapMarker] = []
    var showsUserLocation: Bool = true
    var onMarkerTapped: ((GoogleMapMarker) -> Void)?
    var showUserLocationCircle: Bool = false
    var onPOITapped: ((String, String, CLLocationCoordinate2D) -> Void)? // placeID, name, coordinate
    var onCameraDidChange: ((GMSCameraPosition) -> Void)?
    var onCameraDidIdle: ((GMSCameraPosition) -> Void)?
    
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: center.latitude,
            longitude: center.longitude,
            zoom: zoom
        )
        
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = showsUserLocation
        mapView.settings.myLocationButton = showsUserLocation
        mapView.settings.compassButton = true
        mapView.delegate = context.coordinator
        
        // Log map initialization
        print("🗺️ Google Maps initialized with center: \(center.latitude), \(center.longitude)")
        print("🗺️ Map view frame: \(mapView.frame)")
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Log update
        print("🗺️ Updating map view - markers count: \(markers.count)")
        
        // Update camera position if center changed significantly
        let currentLocation = CLLocation(
            latitude: mapView.camera.target.latitude,
            longitude: mapView.camera.target.longitude
        )
        let newLocation = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        
        if currentLocation.distance(from: newLocation) > 100 {
            let camera = GMSCameraPosition.camera(
                withLatitude: center.latitude,
                longitude: center.longitude,
                zoom: zoom
            )
            mapView.animate(to: camera)
        }
        
        // Update markers
        mapView.clear()
        
        // Add user location circle if requested
        if showUserLocationCircle, let userLocation = LocationService.shared.lastKnownLocation {
            // Add a circle overlay at user location
            let circle = GMSCircle(position: userLocation.coordinate, radius: 2000) // 2km radius to match search area
            circle.fillColor = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 0.1)
            circle.strokeColor = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 0.5)
            circle.strokeWidth = 2
            circle.map = mapView
        }
        
        markers.forEach { marker in
            let gmsMarker = GMSMarker()
            gmsMarker.position = marker.coordinate
            gmsMarker.title = marker.title
            gmsMarker.snippet = marker.subtitle
            gmsMarker.userData = marker
            gmsMarker.map = mapView
            
            // Custom marker appearance
            if let customView = createMarkerView(for: marker) {
                gmsMarker.iconView = customView
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        let parent: GoogleMapView
        
        init(_ parent: GoogleMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let mapMarker = marker.userData as? GoogleMapMarker {
                parent.onMarkerTapped?(mapMarker)
            }
            
            // Animate camera to center on the marker
            let camera = GMSCameraPosition.camera(
                withLatitude: marker.position.latitude,
                longitude: marker.position.longitude,
                zoom: mapView.camera.zoom > 15 ? mapView.camera.zoom : 16
            )
            mapView.animate(to: camera)
            
            return false // Show info window
        }
        
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            // Update the binding only if the position changed significantly
            let currentLocation = CLLocation(
                latitude: parent.center.latitude,
                longitude: parent.center.longitude
            )
            let newLocation = CLLocation(
                latitude: position.target.latitude,
                longitude: position.target.longitude
            )
            
            if currentLocation.distance(from: newLocation) > 10 {
                parent.center = position.target
            }
            
            parent.onCameraDidIdle?(position)
        }
        
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            parent.onCameraDidChange?(position)
        }
        
        func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
            parent.onPOITapped?(placeID, name, location)
        }
    }
    
    private func createMarkerView(for marker: GoogleMapMarker) -> UIView? {
        // Create a Google Maps style circle marker with category icon
        let markerSize: CGFloat = 36
        let view = UIView(frame: CGRect(x: 0, y: 0, width: markerSize, height: markerSize))
        
        // Background circle
        let circleView = UIView(frame: CGRect(x: 0, y: 0, width: markerSize, height: markerSize))
        circleView.backgroundColor = .white
        circleView.layer.cornerRadius = markerSize / 2
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        circleView.layer.shadowRadius = 4
        circleView.layer.shadowOpacity = 0.3
        
        // Inner colored circle
        let innerCircle = UIView(frame: CGRect(x: 3, y: 3, width: markerSize - 6, height: markerSize - 6))
        innerCircle.backgroundColor = categoryColor(for: marker.category)
        innerCircle.layer.cornerRadius = (markerSize - 6) / 2
        
        // Category icon
        let iconView = UIImageView(frame: CGRect(x: 8, y: 8, width: 20, height: 20))
        iconView.image = UIImage(systemName: categoryIcon(for: marker.category))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        
        view.addSubview(circleView)
        circleView.addSubview(innerCircle)
        circleView.addSubview(iconView)
        
        return view
    }
    
    private func categoryColor(for category: PlaceCategory?) -> UIColor {
        guard let category = category else { return UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0) }
        
        switch category {
        case .restaurant:
            return UIColor(red: 0.898, green: 0.224, blue: 0.208, alpha: 1.0) // #E53E35
        case .cafe:
            return UIColor(red: 0.867, green: 0.42, blue: 0.125, alpha: 1.0) // #DD6B20
        case .bar:
            return UIColor(red: 0.482, green: 0.204, blue: 0.118, alpha: 1.0) // #7B341E
        case .hotel:
            return UIColor(red: 0.192, green: 0.51, blue: 0.808, alpha: 1.0) // #3182CE
        case .retail:
            return UIColor(red: 0.502, green: 0.353, blue: 0.835, alpha: 1.0) // #805AD5
        case .service:
            return UIColor(red: 0.22, green: 0.631, blue: 0.412, alpha: 1.0) // #38A169
        case .attraction:
            return UIColor(red: 0.843, green: 0.62, blue: 0.18, alpha: 1.0) // #D69E2E
        case .entertainment:
            return UIColor(red: 0.612, green: 0.259, blue: 0.129, alpha: 1.0) // #9C4221
        case .healthcare:
            return UIColor(red: 0.192, green: 0.592, blue: 0.584, alpha: 1.0) // #319795
        case .fitness:
            return UIColor(red: 0.173, green: 0.478, blue: 0.482, alpha: 1.0) // #2C7A7B
        case .education:
            return UIColor(red: 0.455, green: 0.259, blue: 0.063, alpha: 1.0) // #744210
        case .outdoor:
            return UIColor(red: 0.184, green: 0.522, blue: 0.353, alpha: 1.0) // #2F855A
        case .transport:
            return UIColor(red: 0.169, green: 0.424, blue: 0.69, alpha: 1.0) // #2B6CB0
        case .finance:
            return UIColor(red: 0.157, green: 0.369, blue: 0.38, alpha: 1.0) // #285E61
        case .other:
            return UIColor(red: 0.443, green: 0.502, blue: 0.588, alpha: 1.0) // #718096
        }
    }
    
    private func categoryIcon(for category: PlaceCategory?) -> String {
        guard let category = category else { return "mappin" }
        
        switch category {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .hotel: return "bed.double"
        case .retail: return "bag"
        case .service: return "wrench.and.screwdriver"
        case .attraction: return "star"
        case .entertainment: return "ticket"
        case .healthcare: return "cross.case"
        case .fitness: return "figure.run"
        case .education: return "book"
        case .outdoor: return "tree"
        case .transport: return "car"
        case .finance: return "dollarsign.circle"
        case .other: return "mappin"
        }
    }
}

// Marker model for Google Maps
struct GoogleMapMarker: Identifiable, Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String?
    let placeID: String?
    let category: PlaceCategory?
    
    static func == (lhs: GoogleMapMarker, rhs: GoogleMapMarker) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String? = nil, placeID: String? = nil, category: PlaceCategory? = nil) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.placeID = placeID
        self.category = category
    }
    
    init(place: Place) {
        self.coordinate = place.location?.clLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self.title = place.name
        self.subtitle = place.address
        self.placeID = place.googlePlaceId
        self.category = place.category
    }
    
    init(googlePlace: GooglePlaceDetails) {
        self.coordinate = googlePlace.coordinate
        self.title = googlePlace.name
        self.subtitle = googlePlace.address
        self.placeID = googlePlace.placeID
        self.category = nil // Google places don't have our category enum
    }
}

// SwiftUI wrapper for easier use
struct GoogleMapViewWrapper: View {
    @Binding var center: CLLocationCoordinate2D
    var markers: [GoogleMapMarker] = []
    var zoom: Float = 15.0
    var showsUserLocation: Bool = true
    var onMarkerTapped: ((GoogleMapMarker) -> Void)?
    var showUserLocationCircle: Bool = false
    
    var body: some View {
        GoogleMapView(
            center: $center,
            zoom: zoom,
            markers: markers,
            showsUserLocation: showsUserLocation,
            onMarkerTapped: onMarkerTapped,
            showUserLocationCircle: showUserLocationCircle
        )
        .ignoresSafeArea(edges: .bottom)
    }
}