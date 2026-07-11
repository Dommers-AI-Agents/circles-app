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
    private var totalTasks = 6  // Reduced from 8 - combining related API calls
    private var completedTasks = 0
    private var progressHandler: ((Double, String) -> Void)?
    
    // Cache properties
    private let cacheExpiryInterval: TimeInterval = 900 // 15 minutes (reduced from 5)
    // Window in which stale cached data may still paint the UI at launch;
    // the home screen refetches immediately, so this only bounds the first frame.
    private let staleCacheMaxAge: TimeInterval = 7 * 24 * 3600 // 7 days
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
                    if AuthService.isDefinitiveAuthFailure(error) {
                        // Server rejected the token - session is genuinely dead
                        let refreshError = NSError(domain: "PreloadManager", code: -3, userInfo: [
                            NSLocalizedDescriptionKey: "Your session has expired. Please log in again.",
                            NSUnderlyingErrorKey: error
                        ])
                        completion(.failure(refreshError))
                    } else {
                        // Transient failure (network/server): the token may still be valid
                        // server-side (client-side expiry uses a conservative fallback).
                        // Proceed optimistically; if the token is truly dead, individual
                        // requests will 401 and the APIService handler takes over.
                        print("⚠️ PreloadManager: Transient refresh failure, proceeding with existing token")
                        self.performPreloadAfterTokenRefresh(progressHandler: progressHandler, completion: completion)
                    }
                }
            }
            return
        }
        
        // Use the new extracted method for the main preload logic
        continuePreloadProcess(progressHandler: progressHandler, completion: completion)
    }
    
    /// Memory-or-disk cached data for instant launch. Never hits the network.
    /// allowStale widens the acceptance window to staleCacheMaxAge - callers using
    /// it must refresh in the background (the home screen refetches on appear).
    func getCachedData(allowStale: Bool = false) -> PreloadedData? {
        if let data = preloadedData {
            return data
        }
        if let disk = loadFromCache(maxAge: allowStale ? staleCacheMaxAge : nil) {
            preloadedData = disk
            return disk
        }
        return nil
    }

    /// Re-runs the preload pipeline silently, bypassing the cache-hit early return,
    /// to rewrite the memory + disk cache for the next launch. No UI is updated -
    /// the home screen fetches its own fresh content on appear. Failures are
    /// silent: a definitive 401 already routes through APIService's token handling.
    func refreshInBackground() {
        guard !isPreloading else {
            print("🔄 PreloadManager: Already preloading, skipping background refresh")
            return
        }
        print("🔄 PreloadManager: Starting silent background refresh")
        isPreloading = true
        completedTasks = 0
        taskErrors.removeAll()
        taskCompletionTimes.removeAll()
        retryAttempts.removeAll()
        continuePreloadProcess(progressHandler: { _, _ in }) { result in
            if case .success = result {
                print("✅ PreloadManager: Background refresh complete, cache updated")
            } else {
                print("⚠️ PreloadManager: Background refresh failed (silent)")
            }
        }
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
    
    private func loadFromCache(maxAge: TimeInterval? = nil) -> PreloadedData? {
        // Check cache timestamp
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            print("📭 PreloadManager: No cache timestamp found")
            return nil
        }
        let age = Date().timeIntervalSince(timestamp)
        guard age < (maxAge ?? cacheExpiryInterval) else {
            print("⏰ PreloadManager: Cache expired (age: \(Int(age))s)")
            // Only physically delete once the data is too old even for stale display
            if age >= staleCacheMaxAge {
                clearCache()
            }
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
    
    /// True when the disk cache is within the freshness window - used at launch
    /// to decide whether a background cache refresh is worth the network traffic.
    func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheExpiryInterval
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
        // Critical subset: user + circles. The splash only truly blocks on these;
        // everything else gets a short grace period and the home screen fetches
        // whatever is missing on demand.
        let criticalGroup = DispatchGroup()
        
        // Variables to store loaded data
        var loadedUser: User?
        var loadedCircles: [Circle] = []
        var loadedNetworkCircles: [Circle] = []
        var loadedConnections: [Connection] = []
        var loadedActivities: [Activity] = []
        var loadedMoments: [PlaceVideo] = []
        var unreadCount = 0
        var pendingCount = 0
        
        var loadError: Error?
        var didFinish = false

        // Single completion funnel: first caller wins (full completion, critical-
        // group grace period, or timeout), later callers are no-ops.
        func finishPreload() {
            guard !didFinish else { return }
            didFinish = true

            if let error = loadError {
                self.isPreloading = false
                print("❌ PreloadManager: Preload failed with error: \(error)")
                self.logDetailedErrorInfo()
                completion(.failure(error))
                return
            }

            // Places are intentionally NOT loaded here: the home screen discards
            // preloaded places and refetches them itself, so blocking the splash
            // on the heaviest network call was pure waste.
            self.completePreload(
                user: loadedUser,
                circles: loadedCircles,
                networkCircles: loadedNetworkCircles,
                places: [],
                connections: loadedConnections,
                unreadCount: unreadCount,
                pendingCount: pendingCount,
                activities: loadedActivities,
                moments: loadedMoments,
                completion: completion
            )
        }

        // Timeout protection - 30 seconds (only guards the critical user+circles wave)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            guard !didFinish else { return }

            print("⏰ PreloadManager: Loading timeout reached (30 seconds)")
            self.logDetailedErrorInfo()

            didFinish = true
            self.isPreloading = false
            let error = NSError(domain: "PreloadManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Loading is taking longer than expected. This may be due to a slow network connection."
            ])
            completion(.failure(error))
        }

        // 1. Load User Profile (with retry) - critical
        loadGroup.enter()
        criticalGroup.enter()
        let userStartTime = Date()

        retryTask(taskName: "user", operation: { completion in
            AuthService.shared.fetchCurrentUser(completion: completion)
        }) { [weak self] result in
            defer {
                loadGroup.leave()
                criticalGroup.leave()
            }
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

        // 2. Load Circles (with retry) - critical
        loadGroup.enter()
        criticalGroup.enter()
        let circlesStartTime = Date()

        retryTask(taskName: "circles", operation: { completion in
            CircleService.shared.fetchUserCircles(completion: completion)
        }) { [weak self] result in
            defer {
                loadGroup.leave()
                criticalGroup.leave()
            }
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
                // Non-fatal: the home screen reloads connections on appear
                // (userListView.refresh()), so don't sink the whole preload.
                print("⚠️ PreloadManager: Failed to load connections, continuing without them")
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
        
        // Ideal path: everything (including non-critical tasks) finished.
        loadGroup.notify(queue: .main) {
            print("🏁 PreloadManager: All tasks completed")
            finishPreload()
        }

        // Fast path: once the critical tasks (user + circles) are done, give the
        // non-critical stragglers a short grace period, then finish with whatever
        // has arrived. The home screen fetches anything missing on demand.
        criticalGroup.notify(queue: .main) {
            if loadError != nil {
                finishPreload() // fail fast - no point waiting for stragglers
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if !didFinish {
                    print("⏳ PreloadManager: Grace period elapsed, finishing with partial non-critical data")
                }
                finishPreload()
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
        
        completion(.success(preloadedData))
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