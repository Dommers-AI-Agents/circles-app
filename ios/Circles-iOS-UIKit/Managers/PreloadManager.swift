import Foundation

// MARK: - Preloaded Data Container
struct PreloadedData {
    let user: User?
    let circles: [Circle]
    let allPlaces: [Place]
    let connections: [Connection]
    let unreadMessageCount: Int
    let pendingConnectionCount: Int
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
    private var totalTasks = 5  // Changed from 6 to 5 (excluding places initially)
    private var completedTasks = 0
    private var progressHandler: ((Double, String) -> Void)?
    
    // MARK: - Public Methods
    func preloadAllData(progressHandler: @escaping (Double, String) -> Void,
                       completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        
        guard !isPreloading else {
            print("🔄 PreloadManager: Already preloading, skipping duplicate request")
            return
        }
        
        isPreloading = true
        completedTasks = 0
        self.progressHandler = progressHandler
        
        print("🚀 PreloadManager: Starting data preload")
        
        // Add timeout protection - 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, self.isPreloading else { return }
            print("⏰ PreloadManager: Timeout reached, forcing completion")
            self.isPreloading = false
            let error = NSError(domain: "PreloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Loading timeout"])
            completion(.failure(error))
        }
        updateProgress(status: "Loading your profile...")
        
        // Create dispatch group for parallel loading
        let loadGroup = DispatchGroup()
        
        // Variables to store loaded data
        var loadedUser: User?
        var loadedCircles: [Circle] = []
        var loadedPlaces: [Place] = []
        var loadedConnections: [Connection] = []
        var unreadCount = 0
        var pendingCount = 0
        
        var loadError: Error?
        
        // 1. Load User Profile
        loadGroup.enter()
        AuthService.shared.fetchCurrentUser { [weak self] result in
            switch result {
            case .success(let user):
                loadedUser = user
                self?.incrementProgress(status: "Loading your circles...")
                print("✅ PreloadManager: User profile loaded")
            case .failure(let error):
                loadError = error
                print("❌ PreloadManager: Failed to load user profile: \(error)")
            }
            loadGroup.leave()
        }
        
        // 2. Load Circles
        loadGroup.enter()
        CircleService.shared.fetchUserCircles { [weak self] result in
            switch result {
            case .success(let circles):
                loadedCircles = circles
                self?.incrementProgress(status: "Loading your places...")
                print("✅ PreloadManager: Loaded \(circles.count) circles")
            case .failure(let error):
                loadError = error
                print("❌ PreloadManager: Failed to load circles: \(error)")
            }
            loadGroup.leave()
        }
        
        // 3. Load All Places (will be loaded after circles complete)
        // We'll handle this in the notify block to avoid deadlock
        
        // 4. Load Connections
        loadGroup.enter()
        NetworkManager.shared.fetchConnections { [weak self] connections, error in
            if let connections = connections {
                loadedConnections = connections.filter { $0.status == .accepted }
                self?.incrementProgress(status: "Checking messages...")
                print("✅ PreloadManager: Loaded \(connections.count) connections")
            } else if let error = error {
                loadError = error
                print("❌ PreloadManager: Failed to load connections: \(error)")
            }
            loadGroup.leave()
        }
        
        // 5. Load Unread Message Count
        loadGroup.enter()
        MessagingManager.shared.updateUnreadCount()
        // Give it a moment to update, then read the value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            unreadCount = MessagingManager.shared.unreadCount
            self?.incrementProgress(status: "Checking connection requests...")
            print("✅ PreloadManager: Unread message count: \(unreadCount)")
            loadGroup.leave()
        }
        
        // 6. Load Pending Connection Count
        loadGroup.enter()
        NetworkManager.shared.getPendingConnectionsCount { [weak self] count in
            pendingCount = count
            self?.incrementProgress(status: "Almost ready...")
            print("✅ PreloadManager: Pending connection count: \(count)")
            loadGroup.leave()
        }
        
        // Wait for initial tasks to complete
        loadGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Check for errors first
            if let error = loadError {
                self.isPreloading = false
                print("❌ PreloadManager: Preload failed with error: \(error)")
                completion(.failure(error))
                return
            }
            
            // Now load places based on the circles we got
            if !loadedCircles.isEmpty {
                self.progressHandler?(0.9, "Loading your places...")
                self.fetchAllPlacesFromCircles(circles: loadedCircles) { [weak self] places in
                    guard let self = self else { return }
                    loadedPlaces = places
                    print("✅ PreloadManager: Loaded \(places.count) places")
                    
                    // Complete the preload
                    self.completePreload(
                        user: loadedUser,
                        circles: loadedCircles,
                        places: loadedPlaces,
                        connections: loadedConnections,
                        unreadCount: unreadCount,
                        pendingCount: pendingCount,
                        completion: completion
                    )
                }
            } else {
                // No circles, complete without places
                self.completePreload(
                    user: loadedUser,
                    circles: loadedCircles,
                    places: loadedPlaces,
                    connections: loadedConnections,
                    unreadCount: unreadCount,
                    pendingCount: pendingCount,
                    completion: completion
                )
            }
        }
    }
    
    func getPreloadedData() -> PreloadedData? {
        return preloadedData
    }
    
    func clearPreloadedData() {
        preloadedData = nil
    }
    
    // MARK: - Private Methods
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
                                places: [Place], 
                                connections: [Connection],
                                unreadCount: Int,
                                pendingCount: Int,
                                completion: @escaping (Result<PreloadedData, Error>) -> Void) {
        
        let preloadedData = PreloadedData(
            user: user,
            circles: circles,
            allPlaces: places,
            connections: connections,
            unreadMessageCount: unreadCount,
            pendingConnectionCount: pendingCount
        )
        
        self.preloadedData = preloadedData
        self.progressHandler?(1.0, "Ready!")  // Show 100% completion
        self.isPreloading = false
        
        print("🎉 PreloadManager: All data preloaded successfully")
        print("   - User: \(user?.displayName ?? "nil")")
        print("   - Circles: \(circles.count)")
        print("   - Places: \(places.count)")
        print("   - Connections: \(connections.count)")
        print("   - Unread messages: \(unreadCount)")
        print("   - Pending connections: \(pendingCount)")
        
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
        
        let placeGroup = DispatchGroup()
        var allPlaces: [Place] = []
        let placesLock = NSLock()
        var loadedCount = 0
        
        for circle in circlesWithPlaces {
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
                    print("✅ PreloadManager: Loaded \(places.count) places from circle \(circle.name) (\(loadedCount)/\(circlesWithPlaces.count))")
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
}