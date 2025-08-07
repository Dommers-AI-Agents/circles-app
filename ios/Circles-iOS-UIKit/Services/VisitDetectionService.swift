import CoreLocation
import UIKit

class VisitDetectionService: NSObject {
    static let shared = VisitDetectionService()
    
    private let locationManager = CLLocationManager()
    private var currentVisit: PlaceVisit?
    private var visitStartTime: Date?
    private var lastLocation: CLLocation?
    private var visitTimer: Timer?
    private var locationPermissionCompletion: ((Bool) -> Void)?
    
    // Configuration
    private var minVisitDuration: TimeInterval = 300 // 5 minutes
    private let visitRadius: CLLocationDistance = 50 // 50 meters
    
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
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Request always authorization for visit detection
        let status = locationManager.authorizationStatus
        Logger.info("📍 Current location authorization status: \(status.rawValue)")
        if status == .notDetermined {
            Logger.info("📍 Requesting always authorization")
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Public Methods
    
    func configure() {
        // Initial configuration called from AppDelegate
        Logger.info("📍 VisitDetectionService.configure() called")
        loadSettings()
        checkLocationAuthorization()
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
            // Request always authorization for visit detection
            Logger.warning("📍 Only 'When In Use' authorization - requesting 'Always'")
            locationManager.requestAlwaysAuthorization()
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
        
        Logger.info("📍 Starting visit tracking 🚀")
        Logger.info("📍 - Monitoring significant location changes")
        Logger.info("📍 - Monitoring visits (iOS CLVisit)")
        
        // Start monitoring significant location changes for battery efficiency
        locationManager.startMonitoringSignificantLocationChanges()
        
        // Also start monitoring visits (iOS feature)
        locationManager.startMonitoringVisits()
        
        // Request initial location to verify it's working
        locationManager.requestLocation()
    }
    
    func stopTracking() {
        Logger.info("📍 Stopping visit tracking 🛑")
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        visitTimer?.invalidate()
        currentVisit = nil
        visitStartTime = nil
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
    
    // MARK: - Visit Detection Logic
    
    private func detectVisit(at location: CLLocation) {
        guard isTrackingEnabled else { 
            Logger.debug("📍 Visit detection skipped - tracking disabled")
            return 
        }
        
        // Check if location should be excluded
        if shouldExcludeLocation(location) {
            Logger.info("📍 Visit detection skipped - location is excluded (home/work)")
            return
        }
        
        Logger.info("📍 Detecting visit at location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Check if this is a continuation of current visit
        if let lastLoc = lastLocation,
           let startTime = visitStartTime,
           location.distance(from: lastLoc) <= visitRadius {
            
            // Still at the same place, check duration
            let duration = Date().timeIntervalSince(startTime)
            Logger.debug("📍 Still at same location - duration: \(Int(duration))s")
            
            if duration >= minVisitDuration && currentVisit == nil {
                // Visit duration threshold met, create visit record
                Logger.info("📍 Visit duration threshold met! Creating visit record")
                createVisit(at: location, startTime: startTime)
            }
            
        } else {
            // New location, end current visit if exists
            if let visit = currentVisit {
                Logger.info("📍 Location changed - ending current visit")
                endVisit(visit)
            }
            
            // Start tracking new potential visit
            visitStartTime = Date()
            lastLocation = location
            Logger.info("📍 Started tracking potential visit at new location")
            
            // Set timer to check if user stays at this location
            visitTimer?.invalidate()
            visitTimer = Timer.scheduledTimer(withTimeInterval: minVisitDuration, repeats: false) { [weak self] _ in
                Logger.info("📍 Visit timer fired - checking for visit")
                self?.checkForVisit()
            }
        }
        
        lastLocation = location
    }
    
    private func checkForVisit() {
        guard let location = lastLocation,
              let startTime = visitStartTime else { 
            Logger.debug("📍 checkForVisit - no location or start time")
            return 
        }
        
        let duration = Date().timeIntervalSince(startTime)
        Logger.info("📍 Checking for visit - duration: \(Int(duration))s, threshold: \(Int(minVisitDuration))s")
        if duration >= minVisitDuration {
            Logger.info("📍 Creating visit after timer check")
            createVisit(at: location, startTime: startTime)
        }
    }
    
    private func createVisit(at location: CLLocation, startTime: Date) {
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
            let (placeName, placeAddress) = self.extractPlaceInfo(from: bestPlacemark)
            
            let visit = PlaceVisit(
                id: UUID().uuidString,
                userId: AuthService.shared.getUserId() ?? "",
                placeName: placeName,
                placeAddress: placeAddress,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                category: bestPlacemark.areasOfInterest?.first,
                visitedAt: startTime,
                duration: Int(Date().timeIntervalSince(startTime) / 60), // minutes
                autoDetected: true,
                reviewed: false,
                dismissed: false,
                horizontalAccuracy: location.horizontalAccuracy
            )
            
            Logger.info("📍 Created visit: \(visit.placeName) at \(visit.placeAddress)")
            self.currentVisit = visit
            
            // Save locally first
            self.saveVisitLocally(visit)
            
            // Then sync to server
            self.syncVisitToServer(visit)
        }
    }
    
    private func endVisit(_ visit: PlaceVisit) {
        guard let startTime = visitStartTime else { return }
        
        // Update visit duration
        var updatedVisit = visit
        updatedVisit.duration = Int(Date().timeIntervalSince(startTime) / 60)
        
        // Update local storage
        saveVisitLocally(updatedVisit)
        
        // Sync to server
        syncVisitToServer(updatedVisit)
        
        // Reset state
        currentVisit = nil
        visitStartTime = nil
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
                // Will retry on next app launch or network change
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Logger.info("📍 Location update received: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        detectVisit(at: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // iOS detected a visit
        Logger.info("📍 iOS CLVisit detected! Coordinates: \(visit.coordinate.latitude), \(visit.coordinate.longitude)")
        Logger.info("📍 - Arrival: \(visit.arrivalDate)")
        Logger.info("📍 - Departure: \(visit.departureDate)")
        Logger.info("📍 - Accuracy: \(visit.horizontalAccuracy)m")
        
        let location = CLLocation(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude
        )
        
        // Check if location should be excluded
        if shouldExcludeLocation(location) {
            Logger.info("📍 CLVisit skipped - location is excluded (home/work)")
            return
        }
        
        // Use iOS visit detection
        if visit.departureDate == Date.distantFuture {
            // Arrival at location
            Logger.info("📍 CLVisit arrival detected")
            visitStartTime = visit.arrivalDate
            lastLocation = location
        } else {
            // Departure from location
            Logger.info("📍 CLVisit departure detected")
            if let startTime = visitStartTime {
                let duration = visit.departureDate.timeIntervalSince(startTime)
                Logger.info("📍 Visit duration: \(Int(duration))s")
                if duration >= minVisitDuration {
                    Logger.info("📍 CLVisit meets duration threshold - creating visit")
                    // Create a CLLocation with the visit's accuracy
                    let locationWithAccuracy = CLLocation(
                        coordinate: visit.coordinate,
                        altitude: 0,
                        horizontalAccuracy: visit.horizontalAccuracy,
                        verticalAccuracy: -1,
                        timestamp: visit.arrivalDate
                    )
                    createVisit(at: locationWithAccuracy, startTime: startTime)
                } else {
                    Logger.info("📍 CLVisit too short (\(Int(duration))s < \(Int(minVisitDuration))s)")
                }
            }
        }
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

