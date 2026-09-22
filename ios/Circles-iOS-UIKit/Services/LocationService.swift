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

    private static let persistedFixKey = "LocationService.lastGoodFix"

    /// The last fix we saved to disk, with its original timestamp.
    var persistedFix: CLLocation? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedFixKey),
              let fix = try? JSONDecoder().decode(PersistedFix.self, from: data) else { return nil }
        return fix.location
    }

    /// The best position available RIGHT NOW without asking the hardware or
    /// prompting: this process's last fix, the OS's cached fix, or the one we
    /// saved last time. Works with no network and before any new fix arrives.
    var cachedLocation: CLLocation? {
        lastKnownLocation ?? locationManager.location ?? persistedFix
    }

    /// Signing out must not hand one account's whereabouts to the next.
    func clearPersistedFix() {
        UserDefaults.standard.removeObject(forKey: Self.persistedFixKey)
    }

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

    /// A fresh fix if one arrives within `timeout` seconds, otherwise the best
    /// cached position. The wait is bounded here, at the caller's completion,
    /// and never touches `deliver` — the queued completions must still fire
    /// exactly once each when the real fix lands (proximity check-in counts
    /// on a real fix, not a stale one).
    func getCurrentLocation(timeout: TimeInterval, completion: @escaping (CLLocation?) -> Void) {
        let once = OnceFlag()
        getCurrentLocation { location in
            guard once.claim() else { return }
            completion(location ?? self.cachedLocation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard once.claim() else { return }
            completion(self?.cachedLocation)
        }
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
        if SearchOriginResolver.isUsable(location.coordinate),
           let data = try? JSONEncoder().encode(PersistedFix(location)) {
            UserDefaults.standard.set(data, forKey: Self.persistedFixKey)
        }
        deliver(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Location manager error: \(error.localizedDescription)")
        deliver(nil)
    }
}
