import CoreLocation
import UIKit

class VisitDetectionService: NSObject {
    static let shared = VisitDetectionService()
    
    private let locationManager = CLLocationManager()
    private var locationPermissionCompletion: ((Bool) -> Void)?
    
    // Configuration
    private var minVisitDuration: TimeInterval = 300 // 5 minutes
    
    // User preferences
    var isTrackingEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "visitTrackingEnabled")
    }
    
    private override init() {
        super.init()
        setupLocationManager()
        loadMinimumDuration()
    }
    
    private func loadMinimumDuration() {
        let savedDuration = UserDefaults.standard.integer(forKey: "minVisitDuration")
        if savedDuration > 0 {
            minVisitDuration = TimeInterval(savedDuration * 60) // Convert minutes to seconds
        }
    }
    
    private func setupLocationManager() {
        Logger.info("📍 Setting up location manager")
        locationManager.delegate = self
        // Visits come only from iOS's own visit monitoring (CLVisit), which
        // needs no GPS stream or background location updates.
        
        // Only ask for location here when the user has actually enabled
        // visit tracking — an unconditional request fired a system dialog at
        // every fresh launch, colliding with onboarding screens and the
        // tutorial. requestLocationPermissions() handles the ask when the
        // user turns the feature on.
        let status = locationManager.authorizationStatus
        Logger.info("📍 Current location authorization status: \(status.rawValue)")
        if status == .notDetermined && isTrackingEnabled {
            Logger.info("📍 Requesting always authorization (visit tracking enabled)")
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Public Methods
    
    func configure() {
        // Initial configuration called from AppDelegate
        Logger.info("📍 VisitDetectionService.configure() called")
        loadSettings()
        checkLocationAuthorization()
        // Visits saved while offline go out now, and again whenever the
        // connection comes back — not only on the rare background fetch.
        syncPendingVisits()
        // Visits still named for their street get their business later
        VisitNamer.shared.start()
        NotificationCenter.default.addObserver(forName: .networkReachabilityDidChange, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?[NetworkMonitor.isConnectedKey] as? Bool == true else { return }
            self?.syncPendingVisits()
        }
    }
    
    func requestLocationPermissions(completion: @escaping (Bool) -> Void) {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            completion(true)
        case .notDetermined:
            // Store completion handler to call after authorization
            self.locationPermissionCompletion = completion
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func loadSettings() {
        // Load user preferences
        Logger.info("📍 Loading visit tracking settings - enabled: \(isTrackingEnabled)")
        if isTrackingEnabled {
            startTracking()
        } else {
            Logger.info("📍 Visit tracking is disabled in settings")
        }
    }
    
    private func checkLocationAuthorization() {
        let status = locationManager.authorizationStatus
        Logger.info("📍 Checking location authorization - status: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways:
            Logger.info("📍 Location authorization: Always allowed ✅")
            if isTrackingEnabled {
                startTracking()
            }
        case .authorizedWhenInUse:
            // Escalate to Always ONLY when visit tracking is on — the
            // unconditional upgrade prompt ("also use your location when
            // you're not using the app?") fired at launch right after the
            // user's first when-in-use grant, stacking over onboarding.
            if isTrackingEnabled {
                Logger.warning("📍 Only 'When In Use' — visit tracking is on, requesting 'Always'")
                locationManager.requestAlwaysAuthorization()
            } else {
                Logger.info("📍 When-In-Use granted; Always deferred until visit tracking is enabled")
            }
        case .notDetermined:
            // Will request when user enables the feature
            Logger.info("📍 Location authorization not determined yet")
            break
        case .denied, .restricted:
            // Cannot use visit detection
            Logger.error("📍 Location access denied or restricted ❌")
        @unknown default:
            Logger.warning("📍 Unknown location authorization status")
            break
        }
    }
    
    func startTracking() {
        guard isTrackingEnabled else { 
            Logger.debug("📍 Visit tracking is disabled")
            return 
        }
        
        guard locationManager.authorizationStatus == .authorizedAlways else {
            Logger.warning("📍 Always location authorization not granted - current status: \(locationManager.authorizationStatus.rawValue)")
            return
        }
        
        Logger.info("📍 Starting visit tracking (iOS CLVisit) 🚀")
        // Visits were once also guessed from significant-location-change
        // fixes plus a 5-minute timer, which recorded a "visit" every 5
        // minutes of a drive (Wes, 2026-11-16, I-10). Only iOS's own visit
        // detection counts now; earlier builds' SLC monitoring is stopped.
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
    }
    
    func stopTracking() {
        Logger.info("📍 Stopping visit tracking 🛑")
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
    }
    
    func setTrackingEnabled(_ enabled: Bool) {
        Logger.info("📍 Setting tracking enabled: \(enabled)")
        UserDefaults.standard.set(enabled, forKey: "visitTrackingEnabled")
        
        if enabled {
            startTracking()
        } else {
            stopTracking()
        }
    }
    
    func updateMinimumDuration(_ duration: TimeInterval) {
        Logger.info("📍 Updating minimum visit duration to: \(Int(duration))s")
        minVisitDuration = duration
    }
    
    // MARK: - Recording a visit

    private func createVisit(at location: CLLocation, arrival startTime: Date, departure: Date) {
        Logger.info("📍 Creating visit record at \(location.coordinate.latitude), \(location.coordinate.longitude)")
        Logger.info("📍 Location accuracy: \(location.horizontalAccuracy)m")
        
        // Reverse geocode to get place details
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            if let error = error {
                Logger.error("📍 Reverse geocoding failed: \(error)")
                return
            }
            
            guard let placemarks = placemarks, !placemarks.isEmpty else { 
                Logger.error("📍 No placemarks found")
                return 
            }
            
            // Analyze all placemarks and choose the best one
            Logger.info("📍 Found \(placemarks.count) placemarks")
            
            // Log all placemarks for debugging
            for (index, placemark) in placemarks.enumerated() {
                Logger.debug("📍 Placemark \(index): name=\(placemark.name ?? "nil"), subThoroughfare=\(placemark.subThoroughfare ?? "nil"), thoroughfare=\(placemark.thoroughfare ?? "nil"), areasOfInterest=\(placemark.areasOfInterest?.joined(separator: ", ") ?? "nil")")
            }
            
            let bestPlacemark = self.selectBestPlacemark(from: placemarks)
            
            // Extract the most specific name and address
            let (geocodedName, placeAddress) = self.extractPlaceInfo(from: bestPlacemark)

            // Geocoding names the street, not the business inside it: name
            // the visit for the business Apple Maps lists there, allowing for
            // how rough the visit's fix is. A failed or unsure lookup keeps
            // the address; VisitNamer tries again with the app open.
            guard VisitPlaceSuggestion.looksLikeAddress(geocodedName, address: placeAddress) else {
                return self.recordVisit(at: location, startTime: startTime, departure: departure, name: geocodedName,
                                        address: placeAddress, category: bestPlacemark.areasOfInterest?.first)
            }
            VisitPlaceSuggester.candidates(latitude: location.coordinate.latitude,
                                           longitude: location.coordinate.longitude) { [weak self] candidates in
                let best = VisitPlaceSuggestion.autoName(from: candidates, accuracy: location.horizontalAccuracy)
                self?.recordVisit(at: location, startTime: startTime, departure: departure, name: best?.name ?? geocodedName,
                                  address: placeAddress, category: best?.category ?? bestPlacemark.areasOfInterest?.first)
            }
        }
    }

    private func recordVisit(at location: CLLocation, startTime: Date, departure: Date, name placeName: String,
                             address placeAddress: String, category: String?) {
        do {
            let visit = PlaceVisit(
                id: UUID().uuidString,
                userId: AuthService.shared.getUserId() ?? "",
                placeName: placeName,
                placeAddress: placeAddress,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                category: category,
                visitedAt: startTime,
                duration: VisitAcceptance.durationMinutes(arrival: startTime, departure: departure),
                autoDetected: true,
                reviewed: false,
                dismissed: false,
                horizontalAccuracy: location.horizontalAccuracy
            )
            
            Logger.info("📍 Created visit: \(visit.placeName) at \(visit.placeAddress)")
            
            // Save locally first
            self.saveVisitLocally(visit)
            
            // Then sync to server
            self.syncVisitToServer(visit)
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        // Build a more specific address with street number
        var addressComponents: [String] = []
        
        // Add street number and name if available
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            addressComponents.append("\(streetNumber) \(streetName)")
        } else if let streetName = placemark.thoroughfare {
            addressComponents.append(streetName)
        }
        
        // Add city
        if let locality = placemark.locality {
            addressComponents.append(locality)
        }
        
        // Add state and postal code
        if let state = placemark.administrativeArea {
            addressComponents.append(state)
        }
        
        if let postalCode = placemark.postalCode {
            addressComponents.append(postalCode)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    private func selectBestPlacemark(from placemarks: [CLPlacemark]) -> CLPlacemark {
        // Score each placemark based on specificity
        let scoredPlacemarks = placemarks.map { placemark -> (placemark: CLPlacemark, score: Int) in
            var score = 0
            
            // Prefer placemarks with specific names (businesses, POIs)
            if placemark.name != nil && placemark.name != placemark.thoroughfare {
                score += 10
            }
            
            // Prefer placemarks with areas of interest
            if placemark.areasOfInterest != nil {
                score += 8
            }
            
            // Prefer placemarks with street numbers
            if placemark.subThoroughfare != nil {
                score += 5
            }
            
            // Prefer placemarks with street names
            if placemark.thoroughfare != nil {
                score += 3
            }
            
            // Log scoring for debugging
            Logger.debug("📍 Placemark: \(placemark.name ?? "nil") | Street: \(placemark.subThoroughfare ?? "") \(placemark.thoroughfare ?? "") | Score: \(score)")
            
            return (placemark, score)
        }
        
        // Return the highest scoring placemark
        return scoredPlacemarks.max(by: { $0.score < $1.score })?.placemark ?? placemarks.first!
    }
    
    private func extractPlaceInfo(from placemark: CLPlacemark) -> (name: String, address: String) {
        var placeName: String
        var placeAddress: String
        
        // Determine the best name to use
        if let name = placemark.name,
           name != placemark.thoroughfare && !name.isEmpty {
            // Use the specific place name (business, POI, etc.)
            placeName = name
            placeAddress = formatAddress(from: placemark)
        } else if let areaOfInterest = placemark.areasOfInterest?.first {
            // Use area of interest as name
            placeName = areaOfInterest
            placeAddress = formatAddress(from: placemark)
        } else if let streetNumber = placemark.subThoroughfare,
                  let streetName = placemark.thoroughfare {
            // Use street address as name
            placeName = "\(streetNumber) \(streetName)"
            placeAddress = formatAddress(from: placemark)
        } else {
            // Fallback
            placeName = placemark.thoroughfare ?? placemark.locality ?? "Unknown Place"
            placeAddress = formatAddress(from: placemark)
        }
        
        Logger.info("📍 Extracted place info - Name: \(placeName), Address: \(placeAddress)")
        return (placeName, placeAddress)
    }
    
    // MARK: - Storage & Sync
    
    private func saveVisitLocally(_ visit: PlaceVisit) {
        Logger.info("📍 Saving visit locally: \(visit.placeName)")
        
        // Save to UserDefaults for now (could use Core Data later)
        var visits = getLocalVisits()
        
        // Update existing or add new
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = visit
        } else {
            visits.append(visit)
        }
        
        // Keep only last 100 visits locally
        if visits.count > 100 {
            visits = Array(visits.suffix(100))
        }
        
        if let encoded = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(encoded, forKey: "localPlaceVisits")
            Logger.debug("📍 Visit saved locally - total visits: \(visits.count)")
        } else {
            Logger.error("📍 Failed to encode visits for local storage")
        }
    }
    
    private func getLocalVisits() -> [PlaceVisit] {
        guard let data = UserDefaults.standard.data(forKey: "localPlaceVisits"),
              let visits = try? JSONDecoder().decode([PlaceVisit].self, from: data) else {
            return []
        }
        return visits
    }
    
    private func syncVisitToServer(_ visit: PlaceVisit) {
        guard NetworkMonitor.shared.isConnected else {
            Logger.debug("📍 No network connection, visit will sync later")
            return
        }
        
        Logger.info("📍 Syncing visit to server: \(visit.placeName)")
        
        var visitData: [String: Any] = [
            "placeName": visit.placeName,
            "placeAddress": visit.placeAddress,
            "latitude": visit.latitude,
            "longitude": visit.longitude,
            "category": visit.category ?? "",
            "visitedAt": ISO8601DateFormatter().string(from: visit.visitedAt),
            "duration": visit.duration,
            "autoDetected": visit.autoDetected,
            "reviewed": visit.reviewed,
            "dismissed": visit.dismissed
        ]
        
        // Include accuracy if available
        if let accuracy = visit.horizontalAccuracy {
            visitData["horizontalAccuracy"] = accuracy
        }
        
        Logger.debug("📍 Visit data to sync: \(visitData)")
        
        APIService.shared.request(
            endpoint: "visits/track",
            method: .post,
            body: visitData,
            requiresAuth: true
        ) { [weak self] (result: Result<VisitResponse, APIError>) in
            switch result {
            case .success(let response):
                Logger.info("📍 Visit synced successfully: \(response.data.id) ✅")
                // Update local visit with server ID
                self?.markVisitAsSynced(localId: visit.id, serverId: response.data.id)
                
            case .failure(let error):
                Logger.error("📍 Failed to sync visit: \(error.localizedDescription) ❌")
                // Retried on the next launch and when the connection returns
            }
        }
    }
    
    private func markVisitAsSynced(localId: String, serverId: String) {
        var visits = getLocalVisits()
        if let index = visits.firstIndex(where: { $0.id == localId }) {
            // Update with server ID and mark as synced
            visits[index].id = serverId
            visits[index].synced = true
            
            if let encoded = try? JSONEncoder().encode(visits) {
                UserDefaults.standard.set(encoded, forKey: "localPlaceVisits")
                Logger.info("📍 Updated visit ID from \(localId) to \(serverId)")
            }
        }
    }
    
    // Sync all unsynced visits
    func syncPendingVisits() {
        let visits = getLocalVisits().filter { !$0.synced }
        
        for visit in visits {
            syncVisitToServer(visit)
        }
    }
    
    // MARK: - Exclusion Logic
    
    private func shouldExcludeLocation(_ location: CLLocation) -> Bool {
        let excludeHome = UserDefaults.standard.bool(forKey: "excludeHomeFromVisits")
        let excludeWork = UserDefaults.standard.bool(forKey: "excludeWorkFromVisits")
        
        guard excludeHome || excludeWork else { return false }
        
        // For now, use a simpler distance-based check to avoid blocking
        // This will be improved in a future update with geocoding cache
        
        if excludeHome, let homeCoordinates = getStoredCoordinates(for: "home") {
            let homeLocation = CLLocation(latitude: homeCoordinates.latitude, longitude: homeCoordinates.longitude)
            if location.distance(from: homeLocation) < 100 { // Within 100 meters
                Logger.info("📍 Location excluded - within 100m of home")
                return true
            }
        }
        
        if excludeWork, let workCoordinates = getStoredCoordinates(for: "work") {
            let workLocation = CLLocation(latitude: workCoordinates.latitude, longitude: workCoordinates.longitude)
            if location.distance(from: workLocation) < 100 { // Within 100 meters
                Logger.info("📍 Location excluded - within 100m of work")
                return true
            }
        }
        
        return false
    }
    
    private func getStoredCoordinates(for type: String) -> (latitude: Double, longitude: Double)? {
        let latKey = "\(type)Latitude"
        let lonKey = "\(type)Longitude"
        
        let lat = UserDefaults.standard.double(forKey: latKey)
        let lon = UserDefaults.standard.double(forKey: lonKey)
        
        // Check if coordinates are valid (not 0,0)
        if lat != 0 && lon != 0 {
            return (latitude: lat, longitude: lon)
        }
        
        return nil
    }
    
    // Helper method to geocode and store coordinates for home/work addresses
    func updateStoredCoordinates() {
        let geocoder = CLGeocoder()
        
        if let homeAddress = UserDefaults.standard.string(forKey: "userHomeAddress") {
            geocoder.geocodeAddressString(homeAddress) { placemarks, error in
                if let location = placemarks?.first?.location {
                    UserDefaults.standard.set(location.coordinate.latitude, forKey: "homeLatitude")
                    UserDefaults.standard.set(location.coordinate.longitude, forKey: "homeLongitude")
                    Logger.info("📍 Stored home coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                }
            }
        }
        
        if let workAddress = UserDefaults.standard.string(forKey: "userWorkAddress") {
            // Small delay to avoid geocoding rate limits
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                geocoder.geocodeAddressString(workAddress) { placemarks, error in
                    if let location = placemarks?.first?.location {
                        UserDefaults.standard.set(location.coordinate.latitude, forKey: "workLatitude")
                        UserDefaults.standard.set(location.coordinate.longitude, forKey: "workLongitude")
                        Logger.info("📍 Stored work coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    }
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension VisitDetectionService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Logger.info("📍 Location authorization changed to: \(status.rawValue)")
        
        // Handle authorization changes
        switch status {
        case .authorizedAlways:
            Logger.info("📍 Authorization changed to: Always ✅")
            locationPermissionCompletion?(true)
        case .authorizedWhenInUse:
            Logger.warning("📍 Authorization changed to: When In Use ⚠️")
            locationPermissionCompletion?(true)
        case .denied, .restricted:
            Logger.error("📍 Authorization changed to: Denied/Restricted ❌")
            locationPermissionCompletion?(false)
        case .notDetermined:
            Logger.info("📍 Authorization still not determined")
            break
        @unknown default:
            locationPermissionCompletion?(false)
        }
        
        // Clear the completion handler
        locationPermissionCompletion = nil
        
        // Update tracking based on new authorization
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Logger.info("📍 CLVisit: \(visit.coordinate.latitude), \(visit.coordinate.longitude) arrival \(visit.arrivalDate) departure \(visit.departureDate) ±\(Int(visit.horizontalAccuracy))m")
        guard isTrackingEnabled else { return }

        let location = CLLocation(
            coordinate: visit.coordinate,
            altitude: 0,
            horizontalAccuracy: visit.horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: visit.arrivalDate
        )
        if shouldExcludeLocation(location) {
            Logger.info("📍 CLVisit skipped - location is excluded (home/work)")
            return
        }

        let recorded = getLocalVisits().map {
            VisitAcceptance.Stay(arrival: $0.visitedAt, latitude: $0.latitude, longitude: $0.longitude)
        }
        let verdict = VisitAcceptance.verdict(
            arrival: visit.arrivalDate, departure: visit.departureDate,
            horizontalAccuracy: visit.horizontalAccuracy, minDuration: minVisitDuration,
            latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude,
            recorded: recorded)
        guard verdict == .record else {
            Logger.info("📍 CLVisit not recorded: \(verdict)")
            return
        }
        createVisit(at: location, arrival: visit.arrivalDate, departure: visit.departureDate)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Logger.info("📍 Location manager authorization changed (new delegate method)")
        switch manager.authorizationStatus {
        case .authorizedAlways:
            Logger.info("📍 Always location authorization granted ✅")
            if isTrackingEnabled {
                startTracking()
            }
        case .authorizedWhenInUse:
            Logger.warning("📍 Only when-in-use authorization granted, visit tracking limited ⚠️")
        case .denied, .restricted:
            Logger.error("📍 Location authorization denied ❌")
            stopTracking()
        case .notDetermined:
            Logger.info("📍 Location authorization not determined")
            break
        @unknown default:
            Logger.warning("📍 Unknown authorization status")
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.error("📍 Location manager failed with error: \(error)")
    }
}

