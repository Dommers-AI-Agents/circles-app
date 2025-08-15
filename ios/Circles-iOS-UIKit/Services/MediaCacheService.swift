import Foundation
import UIKit

class MediaCacheService {
    static let shared = MediaCacheService()
    
    // Cache size limits
    private let maxNetworkCacheSize: Int64 = 500 * 1024 * 1024 // 500MB for network content
    private let cacheExpiryDays = 7 // Days before network content expires
    
    // In-memory cache for quick access
    private let memoryCache = NSCache<NSString, NSData>()
    
    // Cache directories
    private var userMomentsDirectory: URL?
    private var networkMomentsDirectory: URL?
    private var cacheMetadataURL: URL?
    
    // Cache index
    private var cacheIndex: [String: CachedMedia] = [:]
    private let cacheQueue = DispatchQueue(label: "com.circles.mediacache", attributes: .concurrent)
    
    private init() {
        setupDirectories()
        loadCacheIndex()
        memoryCache.countLimit = 50 // Keep 50 items in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB memory limit
    }
    
    // MARK: - Setup
    
    private func setupDirectories() {
        let fileManager = FileManager.default
        
        // Get Library directory (persists across app updates)
        guard let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            print("❌ MediaCacheService: Failed to get Library directory")
            return
        }
        
        // Create Moments cache directory
        let momentsDirectory = libraryDirectory.appendingPathComponent("MomentsCache")
        
        // User moments (permanent storage)
        userMomentsDirectory = momentsDirectory.appendingPathComponent("UserMoments")
        
        // Network moments (cached with expiry)
        networkMomentsDirectory = momentsDirectory.appendingPathComponent("NetworkMoments")
        
        // Cache metadata file
        cacheMetadataURL = momentsDirectory.appendingPathComponent("cache_metadata.json")
        
        // Create directories if they don't exist
        [userMomentsDirectory, networkMomentsDirectory].compactMap { $0 }.forEach { directory in
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                print("✅ MediaCacheService: Created directory at \(directory.path)")
            }
        }
    }
    
    // MARK: - Cache Management
    
    func cacheMedia(data: Data, url: String, mediaType: CachedMedia.MediaType, userId: String?, isPermanent: Bool) -> String? {
        let mediaId = generateMediaId(from: url)
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Determine storage directory
            let directory: URL?
            if isPermanent, let userDir = self.userMomentsDirectory {
                directory = userDir.appendingPathComponent(mediaType.rawValue)
            } else if let networkDir = self.networkMomentsDirectory {
                directory = networkDir.appendingPathComponent(mediaType.rawValue)
            } else {
                print("❌ MediaCacheService: No directory available for caching")
                return
            }
            
            guard let dir = directory else { return }
            
            // Create subdirectory if needed
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            
            // Generate filename
            let filename = "\(mediaId).\(self.getFileExtension(for: mediaType))"
            let fileURL = dir.appendingPathComponent(filename)
            
            // Write data to disk
            do {
                try data.write(to: fileURL)
                
                // Add to memory cache
                self.memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
                
                // Create cache entry
                let expiresAt = isPermanent ? nil : Date().addingTimeInterval(TimeInterval(self.cacheExpiryDays * 24 * 3600))
                let cachedMedia = CachedMedia(
                    id: mediaId,
                    url: url,
                    localPath: fileURL.path,
                    mediaType: mediaType,
                    userId: userId,
                    fileSize: Int64(data.count),
                    cachedAt: Date(),
                    lastAccessedAt: Date(),
                    expiresAt: expiresAt,
                    isPermanent: isPermanent
                )
                
                // Update cache index
                self.cacheIndex[mediaId] = cachedMedia
                self.saveCacheIndex()
                
                print("✅ MediaCacheService: Cached \(mediaType.rawValue) (\(data.count / 1024)KB) for \(isPermanent ? "user" : "network")")
                
            } catch {
                print("❌ MediaCacheService: Failed to cache media: \(error)")
            }
        }
        
        return mediaId
    }
    
    func retrieveMedia(for url: String, completion: @escaping (Data?) -> Void) {
        let mediaId = generateMediaId(from: url)
        
        // Check memory cache first
        if let cachedData = memoryCache.object(forKey: mediaId as NSString) {
            print("✅ MediaCacheService: Retrieved from memory cache")
            completion(cachedData as Data)
            return
        }
        
        // Check disk cache
        cacheQueue.async { [weak self] in
            guard let self = self,
                  var cachedMedia = self.cacheIndex[mediaId] else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Check if expired (skip for permanent content)
            if !cachedMedia.isPermanent && cachedMedia.isExpired {
                print("⚠️ MediaCacheService: Cache expired for \(mediaId)")
                self.removeFromCache(mediaId: mediaId)
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Read from disk
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: cachedMedia.localPath))
                
                // Update last accessed time
                cachedMedia.markAccessed()
                self.cacheIndex[mediaId] = cachedMedia
                
                // Add to memory cache
                self.memoryCache.setObject(data as NSData, forKey: mediaId as NSString, cost: data.count)
                
                print("✅ MediaCacheService: Retrieved from disk cache (\(data.count / 1024)KB)")
                
                DispatchQueue.main.async {
                    completion(data)
                }
            } catch {
                print("❌ MediaCacheService: Failed to read cached media: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    func cacheImage(_ image: UIImage, for url: String, userId: String?, isPermanent: Bool) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        _ = cacheMedia(data: data, url: url, mediaType: .image, userId: userId, isPermanent: isPermanent)
    }
    
    func retrieveImage(for url: String, completion: @escaping (UIImage?) -> Void) {
        retrieveMedia(for: url) { data in
            if let data = data, let image = UIImage(data: data) {
                completion(image)
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - Cache Cleanup
    
    func cleanupExpiredCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var removedCount = 0
            var freedSpace: Int64 = 0
            
            // Remove expired items
            for (mediaId, cachedMedia) in self.cacheIndex {
                if !cachedMedia.isPermanent && cachedMedia.isExpired {
                    if self.removeFromDisk(cachedMedia: cachedMedia) {
                        self.cacheIndex.removeValue(forKey: mediaId)
                        removedCount += 1
                        freedSpace += cachedMedia.fileSize
                    }
                }
            }
            
            // Check total cache size and remove oldest if needed
            let networkCacheSize = self.calculateNetworkCacheSize()
            if networkCacheSize > self.maxNetworkCacheSize {
                self.evictOldestNetworkContent(targetSize: self.maxNetworkCacheSize / 2)
            }
            
            self.saveCacheIndex()
            
            print("✅ MediaCacheService: Cleanup complete. Removed \(removedCount) items, freed \(freedSpace / 1024 / 1024)MB")
        }
    }
    
    private func evictOldestNetworkContent(targetSize: Int64) {
        // Sort network content by last accessed date
        let networkItems = cacheIndex.values
            .filter { !$0.isPermanent }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        
        var currentSize = calculateNetworkCacheSize()
        
        for item in networkItems {
            if currentSize <= targetSize {
                break
            }
            
            if removeFromDisk(cachedMedia: item) {
                cacheIndex.removeValue(forKey: item.id)
                currentSize -= item.fileSize
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateMediaId(from url: String) -> String {
        // Create a unique ID from URL
        return url.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
    }
    
    private func getFileExtension(for mediaType: CachedMedia.MediaType) -> String {
        switch mediaType {
        case .image, .thumbnail:
            return "jpg"
        case .video, .videoPreview:
            return "mp4"
        }
    }
    
    private func removeFromCache(mediaId: String) {
        if let cachedMedia = cacheIndex[mediaId] {
            removeFromDisk(cachedMedia: cachedMedia)
            cacheIndex.removeValue(forKey: mediaId)
            memoryCache.removeObject(forKey: mediaId as NSString)
        }
    }
    
    @discardableResult
    private func removeFromDisk(cachedMedia: CachedMedia) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: cachedMedia.localPath)
            return true
        } catch {
            print("❌ MediaCacheService: Failed to remove file: \(error)")
            return false
        }
    }
    
    private func calculateNetworkCacheSize() -> Int64 {
        return cacheIndex.values
            .filter { !$0.isPermanent }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    private func calculateUserCacheSize() -> Int64 {
        return cacheIndex.values
            .filter { $0.isPermanent }
            .reduce(0) { $0 + $1.fileSize }
    }
    
    // MARK: - Persistence
    
    private func loadCacheIndex() {
        guard let metadataURL = cacheMetadataURL,
              FileManager.default.fileExists(atPath: metadataURL.path) else {
            print("⚠️ MediaCacheService: No cache index found")
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            cacheIndex = try JSONDecoder().decode([String: CachedMedia].self, from: data)
            print("✅ MediaCacheService: Loaded cache index with \(cacheIndex.count) items")
        } catch {
            print("❌ MediaCacheService: Failed to load cache index: \(error)")
        }
    }
    
    private func saveCacheIndex() {
        guard let metadataURL = cacheMetadataURL else { return }
        
        do {
            let data = try JSONEncoder().encode(cacheIndex)
            try data.write(to: metadataURL)
        } catch {
            print("❌ MediaCacheService: Failed to save cache index: \(error)")
        }
    }
    
    // MARK: - Public Interface
    
    func getCacheStatistics() -> CacheMetadata {
        return CacheMetadata(
            totalSize: calculateUserCacheSize() + calculateNetworkCacheSize(),
            itemCount: cacheIndex.count,
            lastCleanup: Date(),
            userContentSize: calculateUserCacheSize(),
            networkContentSize: calculateNetworkCacheSize()
        )
    }
    
    func clearNetworkCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let networkItems = self.cacheIndex.values.filter { !$0.isPermanent }
            for item in networkItems {
                self.removeFromDisk(cachedMedia: item)
                self.cacheIndex.removeValue(forKey: item.id)
            }
            
            self.saveCacheIndex()
            print("✅ MediaCacheService: Cleared network cache")
        }
    }
    
    func clearAllCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Remove all files
            if let userDir = self.userMomentsDirectory {
                try? FileManager.default.removeItem(at: userDir)
            }
            if let networkDir = self.networkMomentsDirectory {
                try? FileManager.default.removeItem(at: networkDir)
            }
            
            // Clear index
            self.cacheIndex.removeAll()
            self.memoryCache.removeAllObjects()
            
            // Recreate directories
            self.setupDirectories()
            self.saveCacheIndex()
            
            print("✅ MediaCacheService: Cleared all cache")
        }
    }
}