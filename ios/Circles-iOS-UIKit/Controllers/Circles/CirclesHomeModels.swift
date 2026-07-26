import UIKit
import Foundation

// Standalone models used by the Circles home screen: response types,
// search scope, home-screen data models, loading stages, and the
// in-memory cache. Extracted from the controller file (Wave 4).

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Response Types
struct CirclesDataResponse: Codable {
    let success: Bool
    let data: [Circle]
}

// MARK: - Search Scope
enum SearchScope: CaseIterable {
    case myPlaces
    case networkPlaces
    
    var title: String {
        switch self {
        case .myPlaces:
            return "Search your places"
        case .networkPlaces:
            return "Search all places in your network"
        }
    }
    
    var placeholder: String {
        switch self {
        case .myPlaces:
            return "Search your places..."
        case .networkPlaces:
            return "Search network places..."
        }
    }
}

// MARK: - Enhanced Home Screen Data Models
struct EnhancedHomeScreenData: Codable {
    let success: Bool
    let data: HomeScreenContent
}

struct HomeScreenContent: Codable {
    let myCircles: [Circle]
    let networkCircles: [Circle]
    let activities: [Activity]
    let userList: [UserListItem]
    let mapData: MapData?
    let stats: HomeScreenStats

    init(myCircles: [Circle], networkCircles: [Circle], activities: [Activity],
         userList: [UserListItem], mapData: MapData?, stats: HomeScreenStats) {
        self.myCircles = myCircles
        self.networkCircles = networkCircles
        self.activities = activities
        self.userList = userList
        self.mapData = mapData
        self.stats = stats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.myCircles = try container.decode(LossyDecodableArray<Circle>.self, forKey: .myCircles).elements
        self.networkCircles = try container.decode(LossyDecodableArray<Circle>.self, forKey: .networkCircles).elements
        // Lossy + drop unknown types: one malformed or unrecognized activity
        // must not blank the whole feed
        self.activities = try container.decode(LossyDecodableArray<Activity>.self, forKey: .activities).elements
            .filter { $0.type != .unknown }
        self.userList = try container.decode(LossyDecodableArray<UserListItem>.self, forKey: .userList).elements
        self.mapData = try container.decodeIfPresent(MapData.self, forKey: .mapData)
        self.stats = try container.decode(HomeScreenStats.self, forKey: .stats)
    }
}

struct UserListItem: Codable {
    let _id: String
    let displayName: String
    let profileImageUrl: String?
    let isOnline: Bool
}

struct MapData: Codable {
    let places: [MapPlace]
    let center: MapCoordinate
    let bounds: MapBounds?
}

struct MapPlace: Codable {
    let _id: String
    let name: String
    let coordinates: MapCoordinate
    let circleId: String
    let imageUrl: String?
    let category: String?
}

struct MapCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct MapBounds: Codable {
    let north: Double
    let south: Double
    let east: Double
    let west: Double
}

struct HomeScreenStats: Codable {
    let totalCircles: Int
    let totalPlaces: Int
    let totalActivities: Int
    let totalUsers: Int?
    let mapPlaces: Int?
    let loadTimeMs: Int
}

// Response type for the fast homescreen API endpoint
struct HomeScreenResponse: Codable {
    let success: Bool
    let data: HomeScreenData?
}

struct HomeScreenData: Codable {
    let userList: [UserListItem]?
    let recentActivities: [Activity]?
    let stats: FastAPIStats?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userList = (try? container.decode(LossyDecodableArray<UserListItem>.self, forKey: .userList))?.elements
        self.recentActivities = (try? container.decode(LossyDecodableArray<Activity>.self, forKey: .recentActivities))?.elements
            .filter { $0.type != .unknown }
        self.stats = try container.decodeIfPresent(FastAPIStats.self, forKey: .stats)
    }
}

struct FastAPIStats: Codable {
    let loadTimeMs: Int?
    let totalUsers: Int?
    let totalActivities: Int?
    let source: String?
}

// MARK: - Progressive Loading Stages
enum ProgressiveLoadingStage {
    case userListLoaded
    case activitiesLoaded
    case mapDataLoaded
    case allDataLoaded
}

// MARK: - Optimized Cache System
class HomeScreenCache {
    var cachedData: HomeScreenContent?
    var cacheExpiry: Date?
    let cacheValidityMinutes: TimeInterval = 3 // 3 minutes for memory cache
    
    var isValid: Bool {
        guard let expiry = cacheExpiry else { return false }
        return Date() < expiry
    }
    
    func store(_ data: HomeScreenContent) {
        // Store in memory
        cachedData = data
        cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
        Logger.debug("📦 [Memory Cache] Stored home screen data, valid until \(cacheExpiry!)")
        
        // Store in disk cache for longer persistence
        CacheService.shared.cacheHomeScreenData(data)
    }
    
    func retrieve() -> HomeScreenContent? {
        // First try memory cache
        if isValid, let data = cachedData {
            Logger.debug("📦 [Memory Cache] Retrieved valid cached data")
            return data
        }
        
        // Try disk cache as fallback
        if let diskData = CacheService.shared.getCachedHomeScreenData(maxAgeMinutes: 10) {
            Logger.debug("📦 [Disk Cache] Retrieved valid cached data from disk")
            // Store in memory for next access
            cachedData = diskData
            cacheExpiry = Date().addingTimeInterval(cacheValidityMinutes * 60)
            return diskData
        }
        
        Logger.debug("📦 [Cache] No valid cache found")
        cachedData = nil
        cacheExpiry = nil
        return nil
    }
    
    func invalidate() {
        cachedData = nil
        cacheExpiry = nil
        Logger.debug("📦 [Cache] Memory cache invalidated")
        // Note: Disk cache remains for offline scenarios
    }
}
