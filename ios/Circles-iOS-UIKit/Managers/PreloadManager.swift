import Foundation

// MARK: - Preloaded Data Container
struct PreloadedData: Codable {
    let user: User?
    let circles: [Circle]
    let networkCircles: [Circle]  // Circles shared with the user by others
    let allPlaces: [Place]
    let connections: [Connection]
    let unreadMessageCount: Int
    let pendingConnectionCount: Int
    let activities: [Activity]  // Activity feed items
    let moments: [PlaceVideo]   // Moments/reels feed items
}

// MARK: - Preload Manager
class PreloadManager {
    
    // MARK: - Singleton
    static let shared = PreloadManager()
    private init() {}
    
    // MARK: - Properties
    private var isPreloading = false
    private var preloadedData: PreloadedData?
    
    // Progress tracking
    private var totalTasks = 8  // Including network circles, activities, and moments now
    private var completedTasks = 0
    private var progressHandler: ((Double, String) -> Void)?
    
    // Cache properties
    private let cacheExpiryInterval: TimeInterval = 300 // 5 minutes
    private var cacheKey: String {
        guard let userId = AuthService.shared.getUserId() else {
            return "PreloadedDataCache_Unknown"
        }
        return "PreloadedDataCache_\(userId)"
    }
    private var cacheTimestampKey: String {
        guard let userId = AuthService.shared.getUserId() else {
            return "PreloadedDataCacheTimestamp_Unknown"
        }
        return "PreloadedDataCacheTimestamp_\(userId)"
    }
    
    // Enhanced logging and error tracking
    private var taskErrors: [String: Error] = [:]
    private var taskCompletionTimes: [String: Date] = [:]
    private let startTime = Date()
    
    // Retry logic configuration
    private let maxRetries = 2
    private var retryAttempts: [String: Int] = [:]
    
    // MARK: - Public Methods
    func preloadAllData(progressHandler: @escaping (Double, String) -> Void,
                       completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        
        guard !isPreloading else {
            print("🔄 PreloadManager: Already preloading, skipping duplicate request")
            return
        }
        
        // CRITICAL: Clear any stale data first
        if let existingData = preloadedData,
           let existingUserId = existingData.user?.id,
           let currentUserId = AuthService.shared.getUserId(),
           existingUserId != currentUserId {
            print("⚠️ PreloadManager: Detected user change, clearing stale data")
            print("   Previous user: \(existingUserId)")
            print("   Current user: \(currentUserId)")
            clearPreloadedData()
        }
        
        // Check cache first
        if let cachedData = loadFromCache() {
            print("🚀 PreloadManager: Using cached data, skipping network requests")
            self.preloadedData = cachedData
            progressHandler(1.0, "Ready!")
            completion(.success(cachedData))
            return
        }
        
        isPreloading = true
        completedTasks = 0
        taskErrors.removeAll()
        taskCompletionTimes.removeAll()
        retryAttempts.removeAll()
        self.progressHandler = progressHandler
        
        print("🚀 PreloadManager: Starting data preload")
        
        // Validate authentication state before proceeding
        guard AuthService.shared.isLoggedIn else {
            print("❌ PreloadManager: User not logged in, aborting preload")
            isPreloading = false
            let error = NSError(domain: "PreloadManager", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "You are not logged in. Please log in again."
            ])
            completion(.failure(error))
            return
        }
        
        // Check if token is expired and handle appropriately
        if AuthService.shared.isTokenExpired() {
            print("⚠️ PreloadManager: Token is expired, attempting refresh before preload")
            AuthService.shared.refreshToken { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success():
                    print("✅ PreloadManager: Token refreshed successfully, proceeding with preload")
                    // Important: Reset the isPreloading flag before continuing
                    self.isPreloading = false
                    // Continue with the preload process inline rather than recursively
                    self.performPreloadAfterTokenRefresh(progressHandler: progressHandler, completion: completion)
                case .failure(let error):
                    print("❌ PreloadManager: Token refresh failed: \(error)")
                    self.isPreloading = false
                    let refreshError = NSError(domain: "PreloadManager", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Your session has expired. Please log in again.",
                        NSUnderlyingErrorKey: error
                    ])
                    completion(.failure(refreshError))
                }
            }
            return
        }
        
        // Use the new extracted method for the main preload logic
        continuePreloadProcess(progressHandler: progressHandler, completion: completion)
    }
    
    func getPreloadedData() -> PreloadedData? {
        return preloadedData
    }
    
    func clearPreloadedData() {
        preloadedData = nil
        clearCache()
        clearAllUserCaches() // Clear all potential user-specific caches
    }
    
    // Clear all potential user-specific caches from UserDefaults
    private func clearAllUserCaches() {
        let userDefaults = UserDefaults.standard
        let dictionary = userDefaults.dictionaryRepresentation()
        
        // Remove all keys that match our cache pattern
        for key in dictionary.keys {
            if key.hasPrefix("PreloadedDataCache_") || key.hasPrefix("PreloadedDataCacheTimestamp_") {
                userDefaults.removeObject(forKey: key)
                print("🗑️ PreloadManager: Removed cached data for key: \(key)")
            }
        }
    }
    
    // MARK: - Cache Management
    
    private func saveToCache(_ data: PreloadedData) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(data)
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            print("💾 PreloadManager: Saved preloaded data to cache")
        } catch {
            print("❌ PreloadManager: Failed to cache preloaded data: \(error)")
        }
    }
    
    private func loadFromCache() -> PreloadedData? {
        // Check cache timestamp
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date,
              Date().timeIntervalSince(timestamp) < cacheExpiryInterval else {
            print("⏰ PreloadManager: Cache expired or not found")
            clearCache()
            return nil
        }
        
        // Load cached data
        guard let cached = UserDefaults.standard.data(forKey: cacheKey) else {
            print("📭 PreloadManager: No cached data found")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let data = try decoder.decode(PreloadedData.self, from: cached)
            
            // CRITICAL: Validate that cached data belongs to current user
            guard let currentUserId = AuthService.shared.getUserId(),
                  let cachedUserId = data.user?.id,
                  currentUserId == cachedUserId else {
                print("⚠️ PreloadManager: Cached data belongs to different user, clearing cache")
                print("   Current user: \(AuthService.shared.getUserId() ?? "nil")")
                print("   Cached user: \(data.user?.id ?? "nil")")
                clearCache()
                clearAllUserCaches()
                return nil
            }
            
            print("💾 PreloadManager: Loaded preloaded data from cache (age: \(Int(Date().timeIntervalSince(timestamp)))s)")
            return data
        } catch {
            print("❌ PreloadManager: Failed to decode cached data: \(error)")
            clearCache()
            return nil
        }
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        
        // Also clear any legacy non-user-specific cache
        UserDefaults.standard.removeObject(forKey: "PreloadedDataCache")
        UserDefaults.standard.removeObject(forKey: "PreloadedDataCacheTimestamp")
        
        print("🗑️ PreloadManager: Cleared cache for user \(AuthService.shared.getUserId() ?? "Unknown")")
    }
    
    func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheExpiryInterval
    }
    
    func refreshCacheIfNeeded(progressHandler: @escaping (Double, String) -> Void,
                             completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        // If cache is still valid, use it
        if isCacheValid(), let cachedData = preloadedData {
            print("✅ PreloadManager: Cache still valid, using existing data")
            completion(.success(cachedData))
            return
        }
        
        // Otherwise, reload data
        print("🔄 PreloadManager: Cache expired or not available, reloading data")
        clearPreloadedData()
        preloadAllData(progressHandler: progressHandler, completion: completion)
    }
    
    // MARK: - Private Methods
    
    private func performPreloadAfterTokenRefresh(progressHandler: @escaping (Double, String) -> Void,
                                                completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        // Check cache first (in case it was populated during token refresh)
        if let cachedData = loadFromCache() {
            print("🚀 PreloadManager: Using cached data after token refresh")
            self.preloadedData = cachedData
            progressHandler(1.0, "Ready!")
            completion(.success(cachedData))
            return
        }
        
        // Restart the preload process
        isPreloading = true
        completedTasks = 0
        taskErrors.removeAll()
        taskCompletionTimes.removeAll()
        retryAttempts.removeAll()
        self.progressHandler = progressHandler
        
        print("🚀 PreloadManager: Starting data preload after token refresh")
        
        // Continue with the normal preload flow
        continuePreloadProcess(progressHandler: progressHandler, completion: completion)
    }
    
    private func continuePreloadProcess(progressHandler: @escaping (Double, String) -> Void,
                                       completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        // This contains the main preload logic extracted from preloadAllData
        updateProgress(status: "Loading your profile...")
        
        // Create dispatch group for parallel loading
        let loadGroup = DispatchGroup()
        
        // Variables to store loaded data
        var loadedUser: User?
        var loadedCircles: [Circle] = []
        var loadedNetworkCircles: [Circle] = []
        var loadedPlaces: [Place] = []
        var loadedConnections: [Connection] = []
        var loadedActivities: [Activity] = []
        var loadedMoments: [PlaceVideo] = []
        var unreadCount = 0
        var pendingCount = 0
        
        var loadError: Error?
        
        // Add timeout protection - 45 seconds (extended to handle slow networks)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self = self else { return }
            guard self.isPreloading else { return }
            
            print("⏰ PreloadManager: Loading timeout reached (45 seconds)")
            self.logDetailedErrorInfo()
            
            self.isPreloading = false
            let error = NSError(domain: "PreloadManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Loading is taking longer than expected. This may be due to a slow network connection."
            ])
            completion(.failure(error))
        }
        
        // [Rest of the preload logic goes here - copy from original preloadAllData method]
        // 1. Load User Profile (with retry)
        loadGroup.enter()
        let userStartTime = Date()
        
        retryTask(taskName: "user", operation: { completion in
            AuthService.shared.fetchCurrentUser(completion: completion)
        }) { [weak self] result in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(userStartTime)
            self?.taskCompletionTimes["user"] = Date()
            
            switch result {
            case .success(let user):
                loadedUser = user
                self?.incrementProgress(status: "Loading your circles and network data...")
                print("✅ PreloadManager: User profile loaded")
            case .failure(let error):
                self?.taskErrors["user"] = error
                loadError = error
                print("❌ PreloadManager: Failed to load user profile: \(error.localizedDescription)")
            }
        }
        
        // 2. Load Circles (with retry)
        loadGroup.enter()
        let circlesStartTime = Date()
        
        retryTask(taskName: "circles", operation: { completion in
            CircleService.shared.fetchUserCircles(completion: completion)
        }) { [weak self] result in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(circlesStartTime)
            self?.taskCompletionTimes["circles"] = Date()
            
            switch result {
            case .success(let circles):
                loadedCircles = circles
                self?.incrementProgress(status: "Loading network circles...")
                print("✅ PreloadManager: Loaded \(circles.count) circles")
            case .failure(let error):
                self?.taskErrors["circles"] = error
                loadError = error
                print("❌ PreloadManager: Failed to load circles: \(error.localizedDescription)")
            }
        }
        
        // 3. Load Network Circles (circles shared with user by others)
        loadGroup.enter()
        let networkCirclesStartTime = Date()
        
        struct NetworkCirclesResponse: Codable {
            let success: Bool
            let data: [Circle]
        }
        
        retryTask(taskName: "networkCircles", operation: { (completion: @escaping (Result<[Circle], Error>) -> Void) in
            APIService.shared.request(
                endpoint: "network/circles-shared-with-me",
                method: .get,
                requiresAuth: true,
                completion: { (result: Result<NetworkCirclesResponse, APIError>) in
                    switch result {
                    case .success(let response):
                        completion(.success(response.data))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            )
        }) { [weak self] result in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(networkCirclesStartTime)
            self?.taskCompletionTimes["networkCircles"] = Date()
            
            switch result {
            case .success(let circles):
                loadedNetworkCircles = circles
                self?.incrementProgress(status: "Checking connection requests...")
                print("✅ PreloadManager: Loaded \(circles.count) network circles")
            case .failure(let error):
                self?.taskErrors["networkCircles"] = error
                // Don't fail entire preload for network circles
                print("⚠️ PreloadManager: Failed to load network circles, continuing without them")
            }
        }
        
        // 5. Load Connections (with retry)
        loadGroup.enter()
        let connectionsStartTime = Date()
        retryTask(taskName: "connections", operation: { (completion: @escaping (Result<[Connection], Error>) -> Void) in
            NetworkManager.shared.fetchConnections { connections, error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(connections ?? []))
                }
            }
        }) { [weak self] result in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(connectionsStartTime)
            self?.taskCompletionTimes["connections"] = Date()
            
            switch result {
            case .success(let connections):
                loadedConnections = connections.filter { $0.status == ConnectionStatus.accepted }
                self?.incrementProgress(status: "Checking messages...")
                print("✅ PreloadManager: Loaded \(loadedConnections.count) connections")
            case .failure(let error):
                self?.taskErrors["connections"] = error
                loadError = error
                print("❌ PreloadManager: Failed to load connections")
            }
        }
        
        // 6. Load Unread Message Count
        loadGroup.enter()
        let messagesStartTime = Date()
        MessagingManager.shared.updateUnreadCount()
        // Give it a moment to update, then read the value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(messagesStartTime)
            self?.taskCompletionTimes["messages"] = Date()
            
            unreadCount = MessagingManager.shared.unreadCount
            self?.incrementProgress(status: "Checking connection requests...")
            print("✅ PreloadManager: Unread messages: \(unreadCount)")
        }
        
        // 7. Load Pending Connection Count
        loadGroup.enter()
        let pendingStartTime = Date()
        NetworkManager.shared.getPendingConnectionsCount { [weak self] count in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(pendingStartTime)
            self?.taskCompletionTimes["pending"] = Date()
            
            pendingCount = count
            self?.incrementProgress(status: "Loading activities...")
            print("✅ PreloadManager: Pending connections: \(count)")
        }
        
        // 8. Load Activities
        loadGroup.enter()
        let activitiesStartTime = Date()
        
        ActivityService.shared.getNetworkActivities(limit: 20, offset: 0) { [weak self] result in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(activitiesStartTime)
            self?.taskCompletionTimes["activities"] = Date()
            
            switch result {
            case .success(let response):
                loadedActivities = response.activities
                self?.incrementProgress(status: "Loading moments...")
                print("✅ PreloadManager: Loaded \(response.activities.count) activities")
            case .failure(let error):
                // Don't fail the entire preload for activities
                print("⚠️ PreloadManager: Failed to load activities: \(error)")
                self?.taskErrors["activities"] = error
            }
        }
        
        // 9. Load Moments/Reels
        loadGroup.enter()
        let momentsStartTime = Date()
        
        struct VideosResponse: Codable {
            let success: Bool
            let data: [PlaceVideo]
            let hasMore: Bool
        }
        
        APIService.shared.request(
            endpoint: "videos/reels/feed?limit=20&offset=0",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<VideosResponse, APIError>) in
            defer { loadGroup.leave() }
            let duration = Date().timeIntervalSince(momentsStartTime)
            self?.taskCompletionTimes["moments"] = Date()
            
            switch result {
            case .success(let response):
                loadedMoments = response.data
                self?.incrementProgress(status: "Almost ready...")
                print("✅ PreloadManager: Loaded \(response.data.count) moments")
            case .failure(let error):
                // Don't fail the entire preload for moments
                print("⚠️ PreloadManager: Failed to load moments: \(error)")
                self?.taskErrors["moments"] = error
            }
        }
        
        // Wait for initial tasks to complete
        loadGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            let mainTasksDuration = Date().timeIntervalSince(self.startTime)
            print("🏁 PreloadManager: Main tasks completed")
            
            // Check for errors first
            if let error = loadError {
                self.isPreloading = false
                print("❌ PreloadManager: Preload failed with error: \(error)")
                self.logDetailedErrorInfo()
                completion(.failure(error))
                return
            }
            
            // Now load places based on the circles we got (both user's and network circles)
            let allCircles = loadedCircles + loadedNetworkCircles
            if !allCircles.isEmpty {
                self.progressHandler?(0.9, "Loading places from your circles...")
                self.fetchAllPlacesFromCircles(circles: allCircles) { places in
                    loadedPlaces = places
                    print("✅ PreloadManager: Loaded \(places.count) places from \(allCircles.count) circles")
                    
                    // Complete the preload
                    self.completePreload(
                        user: loadedUser,
                        circles: loadedCircles,
                        networkCircles: loadedNetworkCircles,
                        places: loadedPlaces,
                        connections: loadedConnections,
                        unreadCount: unreadCount,
                        pendingCount: pendingCount,
                        activities: loadedActivities,
                        moments: loadedMoments,
                        completion: completion
                    )
                }
            } else {
                // No circles, complete without places
                self.completePreload(
                    user: loadedUser,
                    circles: loadedCircles,
                    networkCircles: loadedNetworkCircles,
                    places: loadedPlaces,
                    connections: loadedConnections,
                    unreadCount: unreadCount,
                    pendingCount: pendingCount,
                    activities: loadedActivities,
                    moments: loadedMoments,
                    completion: completion
                )
            }
        }
    }
    
    private func incrementProgress(status: String) {
        completedTasks += 1
        updateProgress(status: status)
    }
    
    private func updateProgress(status: String) {
        let progress = min(Double(completedTasks) / Double(totalTasks), 0.9)  // Cap at 90% until places are loaded
        progressHandler?(progress, status)
    }
    
    private func completePreload(user: User?, 
                                circles: [Circle], 
                                networkCircles: [Circle],
                                places: [Place], 
                                connections: [Connection],
                                unreadCount: Int,
                                pendingCount: Int,
                                activities: [Activity],
                                moments: [PlaceVideo],
                                completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        
        let preloadedData = PreloadedData(
            user: user,
            circles: circles,
            networkCircles: networkCircles,
            allPlaces: places,
            connections: connections,
            unreadMessageCount: unreadCount,
            pendingConnectionCount: pendingCount,
            activities: activities,
            moments: moments
        )
        
        self.preloadedData = preloadedData
        self.progressHandler?(1.0, "Almost ready...")  // Show 100% completion
        self.isPreloading = false
        
        // Save to cache for future use
        self.saveToCache(preloadedData)
        
        print("🎉 PreloadManager: All data preloaded successfully")
        print("   - User: \(user?.displayName ?? "nil")")
        print("   - Circles: \(circles.count)")
        print("   - Network circles: \(networkCircles.count)")
        print("   - Places: \(places.count)")
        print("   - Connections: \(connections.count)")
        print("   - Unread messages: \(unreadCount)")
        print("   - Pending connections: \(pendingCount)")
        print("   - Activities: \(activities.count)")
        print("   - Moments: \(moments.count)")
        
        // Add small delay to ensure UI updates are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(.success(preloadedData))
        }
    }
    
    private func fetchAllPlacesFromCircles(circles: [Circle], completion: @escaping ([Place]) -> Void) {
        print("🔍 PreloadManager: Starting to fetch places from \(circles.count) circles")
        
        // If no circles or all circles are empty, complete immediately
        let circlesWithPlaces = circles.filter { circle in
            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
            return placeCount > 0
        }
        
        guard !circlesWithPlaces.isEmpty else {
            print("ℹ️ PreloadManager: No circles with places, completing with empty array")
            completion([])
            return
        }
        
        // Use the new batch endpoint to fetch all places in one request
        let circleIds = circlesWithPlaces.map { $0.id }
        print("🚀 PreloadManager: Using batch endpoint to fetch places from \(circleIds.count) circles")
        
        let startTime = Date()
        PlaceService.shared.fetchPlacesByMultipleCircles(circleIds: circleIds) { result in
            let duration = Date().timeIntervalSince(startTime)
            
            switch result {
            case .success(let places):
                print("✅ PreloadManager: Loaded \(places.count) places")
                completion(places)
            case .failure(let error):
                print("❌ PreloadManager: Failed to batch fetch places: \(error)")
                // Fallback to sequential loading
                print("⚠️ PreloadManager: Falling back to sequential place loading")
                self.fallbackSequentialPlaceLoading(circles: circlesWithPlaces, completion: completion)
            }
        }
    }
    
    private func fallbackSequentialPlaceLoading(circles: [Circle], completion: @escaping ([Place]) -> Void) {
        let placeGroup = DispatchGroup()
        var allPlaces: [Place] = []
        let placesLock = NSLock()
        var loadedCount = 0
        
        for circle in circles {
            placeGroup.enter()
            print("🔄 PreloadManager: Fetching places for circle: \(circle.name)")
            
            PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                defer { placeGroup.leave() }
                
                switch result {
                case .success(let places):
                    placesLock.lock()
                    allPlaces.append(contentsOf: places)
                    loadedCount += 1
                    placesLock.unlock()
                    print("✅ PreloadManager: Loaded \(places.count) places from circle \(circle.name) (\(loadedCount)/\(circles.count))")
                case .failure(let error):
                    print("❌ PreloadManager: Failed to fetch places for circle \(circle.name): \(error)")
                }
            }
        }
        
        placeGroup.notify(queue: .main) {
            print("🏁 PreloadManager: Finished loading all places. Total: \(allPlaces.count)")
            completion(allPlaces)
        }
    }
    
    // MARK: - Retry Logic Methods
    
    private func retryTask<T>(
        taskName: String,
        operation: @escaping (@escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let currentAttempt = (retryAttempts[taskName] ?? 0) + 1
        retryAttempts[taskName] = currentAttempt
        
        operation { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let value):
                // Success - clear retry attempts and complete
                self.retryAttempts[taskName] = nil
                completion(.success(value))
                
            case .failure(let error):
                // Check if we should retry
                if currentAttempt < self.maxRetries && self.shouldRetryError(error) {
                    let delay = self.calculateRetryDelay(attempt: currentAttempt)
                    print("🔄 PreloadManager: Retrying \(taskName) (attempt \(currentAttempt))")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.retryTask(taskName: taskName, operation: operation, completion: completion)
                    }
                } else {
                    // Max retries reached or non-retryable error
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func shouldRetryError(_ error: Error) -> Bool {
        // Retry network-related errors but not auth errors
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return false // Don't retry auth errors
            case .noInternet, .requestFailed, .serverError, .unknown:
                return true // Retry network/server errors
            case .httpError(let statusCode, _):
                // Don't retry client errors (4xx) except for 429 (rate limit)
                if statusCode >= 400 && statusCode < 500 && statusCode != 429 {
                    return false
                }
                return true
            default:
                return true
            }
        }
        
        if let nsError = error as? NSError {
            // Retry network errors but not auth/validation errors
            return nsError.domain == NSURLErrorDomain
        }
        
        return true // Default to retrying unknown errors
    }
    
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s...
        return pow(2.0, Double(attempt - 1))
    }
    
    // MARK: - Enhanced Logging Methods
    
    private func logTaskCompletionSummary() {
        // Task completion logging removed for cleaner output
    }
    
    private func logDetailedErrorInfo() {
        if !taskErrors.isEmpty {
            print("❌ PreloadManager: Failed tasks:")
            for (task, error) in taskErrors {
                print("   - \(task): \(error.localizedDescription)")
            }
        }
    }
}