import CoreLocation
import MapKit

class LocationService: NSObject {
    static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    /// Everyone waiting on the next fix. Each completion fires exactly once:
    /// the array is emptied before delivery. The old single stored closure
    /// was never cleared, so a later Core Location callback re-invoked it —
    /// and a caller wrapping it in a CheckedContinuation trapped on the
    /// second resume (two crashes on Wes's phone, 2026-09-15).
    private var pendingCompletions: [(CLLocation?) -> Void] = []
    private let pendingLock = NSLock()
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
        guard CLLocationManager.locationServicesEnabled() else {
            completion(nil)
            return
        }
        pendingLock.lock()
        pendingCompletions.append(completion)
        let isFirst = pendingCompletions.count == 1
        pendingLock.unlock()
        // One in-flight request serves every concurrent caller
        if isFirst { locationManager.requestLocation() }
    }

    /// Hands the result to everyone waiting, once, then forgets them.
    private func deliver(_ location: CLLocation?) {
        pendingLock.lock()
        let waiting = pendingCompletions
        pendingCompletions = []
        pendingLock.unlock()
        waiting.forEach { $0(location) }
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
            deliver(nil)
            return
        }
        
        lastKnownLocation = location
        deliver(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Location manager error: \(error.localizedDescription)")
        deliver(nil)
    }
}
