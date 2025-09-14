import Foundation
import UIKit

// MARK: - Disk Cache Service for Home Screen Performance
class CacheService {
    static let shared = CacheService()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let homeScreenCacheKey = "homescreen_data"
    private let imagesCacheKey = "cached_images"
    
    private init() {
        // Create cache directory in Documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsPath.appendingPathComponent("CirclesCache")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        print("📁 [CacheService] Initialized with directory: \(cacheDirectory.path)")
    }
    
    // MARK: - Home Screen Data Cache
    func cacheHomeScreenData(_ data: HomeScreenContent) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedData = try encoder.encode(data)
            
            let cacheFile = cacheDirectory.appendingPathComponent("\(homeScreenCacheKey).json")
            try encodedData.write(to: cacheFile)
            
            // Store timestamp for expiry check
            let timestampFile = cacheDirectory.appendingPathComponent("\(homeScreenCacheKey)_timestamp.txt")
            let timestamp = Date().timeIntervalSince1970
            try String(timestamp).write(to: timestampFile, atomically: true, encoding: .utf8)
            
            print("💾 [CacheService] Home screen data cached to disk")
        } catch {
            print("❌ [CacheService] Failed to cache home screen data: \(error)")
        }
    }
    
    func getCachedHomeScreenData(maxAgeMinutes: TimeInterval = 10) -> HomeScreenContent? {
        do {
            let cacheFile = cacheDirectory.appendingPathComponent("\(homeScreenCacheKey).json")
            let timestampFile = cacheDirectory.appendingPathComponent("\(homeScreenCacheKey)_timestamp.txt")
            
            // Check if files exist
            guard fileManager.fileExists(atPath: cacheFile.path),
                  fileManager.fileExists(atPath: timestampFile.path) else {
                print("📁 [CacheService] No cached home screen data found")
                return nil
            }
            
            // Check if cache is still valid
            let timestampString = try String(contentsOf: timestampFile)
            guard let timestamp = Double(timestampString) else { return nil }
            
            let cacheAge = Date().timeIntervalSince1970 - timestamp
            let maxAgeSeconds = maxAgeMinutes * 60
            
            if cacheAge > maxAgeSeconds {
                print("📁 [CacheService] Cached data expired (age: \(Int(cacheAge/60))min)")
                return nil
            }
            
            // Load and decode data
            let cachedData = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let homeScreenData = try decoder.decode(HomeScreenContent.self, from: cachedData)
            
            print("📁 [CacheService] Retrieved valid cached data (age: \(Int(cacheAge/60))min)")
            return homeScreenData
            
        } catch {
            print("❌ [CacheService] Failed to retrieve cached data: \(error)")
            return nil
        }
    }
    
    // MARK: - Enhanced Image Cache with Optimization
    func cacheImage(_ imageData: Data, for url: String) {
        // Optimize image before caching
        guard let optimizedData = optimizeImageData(imageData) else {
            print("❌ [CacheService] Failed to optimize image")
            return
        }
        
        let filename = url.hash.description + ".jpg"
        let imageFile = cacheDirectory.appendingPathComponent("images").appendingPathComponent(filename)
        
        // Create images directory if needed
        let imagesDir = cacheDirectory.appendingPathComponent("images")
        if !fileManager.fileExists(atPath: imagesDir.path) {
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        
        do {
            try optimizedData.write(to: imageFile)
            let originalSize = imageData.count
            let optimizedSize = optimizedData.count
            let savings = ((originalSize - optimizedSize) * 100) / originalSize
            print("📷 [CacheService] Image cached: \(filename) (saved \(savings)%)")
        } catch {
            print("❌ [CacheService] Failed to cache image: \(error)")
        }
    }
    
    func getCachedImage(for url: String) -> Data? {
        let filename = url.hash.description + ".jpg"
        let imageFile = cacheDirectory.appendingPathComponent("images").appendingPathComponent(filename)
        
        guard fileManager.fileExists(atPath: imageFile.path) else {
            return nil
        }
        
        do {
            let imageData = try Data(contentsOf: imageFile)
            print("📷 [CacheService] Retrieved cached image: \(filename)")
            return imageData
        } catch {
            print("❌ [CacheService] Failed to retrieve cached image: \(error)")
            return nil
        }
    }
    
    // MARK: - Image Optimization
    private func optimizeImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // Calculate optimal size (max 800px width, maintain aspect ratio)
        let maxWidth: CGFloat = 800
        let scale = min(maxWidth / image.size.width, 1.0)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        // Resize image using modern UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Compress with quality 0.8 for good balance between quality and size
        return resizedImage.jpegData(compressionQuality: 0.8)
    }
    
    // MARK: - Image Preloading
    func preloadImages(from urls: [String], completion: @escaping (Int) -> Void) {
        guard !urls.isEmpty else {
            completion(0)
            return
        }
        
        print("📷 [CacheService] Preloading \(urls.count) images")
        var loadedCount = 0
        let group = DispatchGroup()
        
        for url in urls {
            // Skip if already cached
            if getCachedImage(for: url) != nil {
                loadedCount += 1
                continue
            }
            
            group.enter()
            
            // Download and cache image
            guard let imageUrl = URL(string: url) else {
                group.leave()
                continue
            }
            
            URLSession.shared.dataTask(with: imageUrl) { [weak self] data, response, error in
                defer { group.leave() }
                
                guard let data = data, error == nil else {
                    print("❌ [CacheService] Failed to preload image: \(url)")
                    return
                }
                
                // Cache the image
                self?.cacheImage(data, for: url)
                loadedCount += 1
                
            }.resume()
        }
        
        group.notify(queue: .main) {
            print("📷 [CacheService] Preloaded \(loadedCount)/\(urls.count) images")
            completion(loadedCount)
        }
    }
    
    // MARK: - Smart Image Loading
    func loadImageWithCache(from url: String, completion: @escaping (UIImage?) -> Void) {
        // Check cache first
        if let cachedData = getCachedImage(for: url),
           let image = UIImage(data: cachedData) {
            print("📷 [CacheService] Loaded image from cache: \(url)")
            completion(image)
            return
        }
        
        // Download if not cached
        guard let imageUrl = URL(string: url) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        URLSession.shared.dataTask(with: imageUrl) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Cache the image
            self?.cacheImage(data, for: url)
            
            // Return image
            DispatchQueue.main.async {
                completion(UIImage(data: data))
            }
            
        }.resume()
    }
    
    // MARK: - Cache Management
    func clearCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in contents {
                try fileManager.removeItem(at: file)
            }
            print("🗑️ [CacheService] Cache cleared")
        } catch {
            print("❌ [CacheService] Failed to clear cache: \(error)")
        }
    }
    
    func getCacheSize() -> String {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [])
            let totalSize = contents.reduce(0) { total, url in
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                return total + (resourceValues?.fileSize ?? 0)
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB, .useBytes]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(totalSize))
        } catch {
            return "Unknown"
        }
    }
    
    func cleanExpiredCache() {
        // Remove files older than 24 hours
        let maxAge: TimeInterval = 24 * 60 * 60 // 24 hours
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            for file in contents {
                let resourceValues = try file.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
                    try fileManager.removeItem(at: file)
                    print("🗑️ [CacheService] Removed expired file: \(file.lastPathComponent)")
                }
            }
        } catch {
            print("❌ [CacheService] Failed to clean expired cache: \(error)")
        }
    }
}