import CoreLocation
import MapKit

class LocationService: NSObject {
    static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocation?) -> Void)?
    private(set) var lastKnownLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        locationCompletion = completion
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestLocation()
        } else {
            completion(nil)
        }
    }
    
    func getAddress(from location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                completion(nil)
                return
            }
            
            let address = [
                placemark.thoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.postalCode,
                placemark.country
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
            
            completion(address)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            locationCompletion?(nil)
            return
        }
        
        lastKnownLocation = location
        locationCompletion?(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
        locationCompletion?(nil)
    }
}
