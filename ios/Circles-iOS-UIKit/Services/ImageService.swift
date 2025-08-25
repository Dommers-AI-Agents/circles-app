import UIKit

class ImageService {
    static let shared = ImageService()
    
    private let cache = NSCache<NSString, UIImage>()
    private let mediaCacheService = MediaCacheService.shared
    
    // Alias for loadImage to maintain compatibility
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        downloadImage(from: urlString, completion: completion)
    }
    
    // Load image with custom cache key for better uniqueness
    func loadImageWithKey(from urlString: String, cacheKey: String, completion: @escaping (UIImage?) -> Void) {
        let key = NSString(string: cacheKey)
        
        // Check if image is in memory cache with custom key
        if let cachedImage = cache.object(forKey: key) {
            Logger.debug("ImageService: Found image in memory cache with custom key: \(cacheKey)")
            completion(cachedImage)
            return
        }
        
        // If not in cache with custom key, download normally
        downloadImage(from: urlString) { [weak self] image in
            if let image = image {
                // Store with custom cache key
                self?.cache.setObject(image, forKey: key)
            }
            completion(image)
        }
    }
    
    // Clear cache for specific URL
    func clearCacheForUrl(_ urlString: String) {
        let cacheKey = NSString(string: urlString)
        cache.removeObject(forKey: cacheKey)
        Logger.debug("ImageService: Cleared cache for URL: \(urlString)")
    }
    
    // Clear all caches
    func clearAllCaches() {
        cache.removeAllObjects()
        mediaCacheService.clearAllCache()
        Logger.debug("ImageService: Cleared all image caches")
    }
    
    // Get cached image if available (synchronous)
    func getCachedImage(for urlString: String) -> UIImage? {
        let cacheKey = NSString(string: urlString)
        return cache.object(forKey: cacheKey)
    }
    
    // MARK: - Specialized Loading Methods
    
    // Load profile image with user-specific cache key to prevent collisions
    func loadProfileImage(for userId: String, from urlString: String?, completion: @escaping (UIImage?) -> Void) {
        guard let urlString = urlString, !urlString.isEmpty else {
            completion(nil)
            return
        }
        
        // Create a namespaced cache key for profile images
        let profileCacheKey = "profile_\(userId)_\(urlString.hashValue)"
        
        // Use the loadImageWithKey method with the profile-specific cache key
        loadImageWithKey(from: urlString, cacheKey: profileCacheKey, completion: completion)
    }
    
    // Load place image with place-specific cache key to prevent collisions
    func loadPlaceImage(for placeId: String, from urlString: String?, completion: @escaping (UIImage?) -> Void) {
        guard let urlString = urlString, !urlString.isEmpty else {
            completion(nil)
            return
        }
        
        // Create a namespaced cache key for place images
        let placeCacheKey = "place_\(placeId)_\(urlString.hashValue)"
        
        // Use the loadImageWithKey method with the place-specific cache key
        loadImageWithKey(from: urlString, cacheKey: placeCacheKey, completion: completion)
    }
    
    func downloadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        // Check if this is a Google Places API URL that needs migration (not Firebase Storage)
        if (urlString.contains("googleapis.com") && !urlString.contains("firebasestorage.googleapis.com")) || urlString.contains("photoreference=") {
            Logger.warning("ImageService: Detected Google Places API URL, triggering migration: \(urlString)")
            handleGoogleAPIUrl(urlString, completion: completion)
            return
        }
        
        let cacheKey = NSString(string: urlString)
        
        // Check if image is in memory cache
        if let cachedImage = cache.object(forKey: cacheKey) {
            Logger.debug("ImageService: Found image in memory cache for \(urlString)")
            completion(cachedImage)
            return
        }
        
        // Check if image is in disk cache
        mediaCacheService.retrieveImage(for: urlString) { [weak self] image in
            if let image = image {
                Logger.debug("ImageService: Found image in disk cache for \(urlString)")
                // Add to memory cache
                self?.cache.setObject(image, forKey: cacheKey)
                completion(image)
                return
            }
            
            // If not in any cache, download from network
            self?.downloadFromNetwork(urlString: urlString, completion: completion)
        }
    }
    
    private func downloadFromNetwork(urlString: String, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = NSString(string: urlString)
        
        // Check if URL needs base URL prepended (for relative URLs)
        var finalURLString = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            // This is a relative URL, prepend the base URL
            let baseURL = "https://circles-backend-196924649787.us-central1.run.app"
            finalURLString = baseURL + (urlString.hasPrefix("/") ? "" : "/") + urlString
            Logger.debug("ImageService: Converted relative URL to absolute: \(finalURLString)")
        }
        
        // Validate URL
        guard let url = URL(string: finalURLString), 
              let host = url.host, 
              !host.isEmpty else {
            Logger.error("ImageService: Invalid URL or missing hostname: \(finalURLString)")
            completion(nil)
            return
        }
        
        // Additional validation for obviously invalid hostnames
        if host.contains("..") || host.hasPrefix(".") || host.hasSuffix(".") {
            Logger.error("ImageService: Invalid hostname format: \(host)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                Logger.error("ImageService: Download error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    Logger.warning("ImageService: HTTP 403 Forbidden - This image may be from an old Firebase project")
                    Logger.debug("ImageService: URL attempted: \(url)")
                    
                    // Check if this is an old Firebase project URL
                    if finalURLString.contains("circles-app-4902d") {
                        Logger.warning("ImageService: This is an image from the old Firebase project. It needs to be re-uploaded.")
                    }
                    
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                } else if httpResponse.statusCode != 200 {
                    Logger.error("ImageService: HTTP Error - Status \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        Logger.debug("ImageService: Error response: \(errorString)")
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
            }
            
            guard let self = self else { return }
            guard let data = data, let image = UIImage(data: data) else {
                Logger.error("ImageService: Failed to create image from data")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            Logger.debug("ImageService: Successfully downloaded image")
            
            // Cache the image in memory
            self.cache.setObject(image, forKey: cacheKey)
            
            // Cache the image to disk
            // Determine if this is user's own content based on URL patterns
            let isUserContent = self.isUserOwnContent(urlString: finalURLString)
            self.mediaCacheService.cacheImage(image, for: urlString, userId: AuthService.shared.getUserId(), isPermanent: isUserContent)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    // Helper to determine if content belongs to current user
    private func isUserOwnContent(urlString: String) -> Bool {
        // Check if URL contains user's ID or is from user's upload
        guard let userId = AuthService.shared.getUserId() else { return false }
        return urlString.contains(userId) || urlString.contains("/user/\(userId)/")
    }
    
    // Handle Google API URLs by attempting to download them once
    private func handleGoogleAPIUrl(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        // Try to download the image from Google API URL
        // This might fail if the URL is expired, but we'll try once
        guard let url = URL(string: urlString) else {
            Logger.error("ImageService: Invalid Google API URL: \(urlString)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                Logger.error("ImageService: Failed to download Google API image: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                    Logger.error("ImageService: Google API URL expired or invalid (HTTP \(httpResponse.statusCode))")
                    Logger.info("ImageService: Attempting automatic photo migration...")
                    
                    // Try to automatically migrate photos for this place
                    self?.attemptPhotoMigration(for: urlString) { migratedImage in
                        DispatchQueue.main.async {
                            completion(migratedImage)
                        }
                    }
                    return
                } else if httpResponse.statusCode != 200 {
                    Logger.error("ImageService: Google API returned HTTP \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                Logger.error("ImageService: Failed to create image from Google API data")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Successfully downloaded from Google API
            Logger.info("ImageService: Successfully downloaded image from Google API (temporary)")
            Logger.warning("ImageService: ⚠️ This place should be migrated to Firebase Storage")
            
            // Cache temporarily but don't save to permanent cache
            // since this URL will expire
            let cacheKey = NSString(string: urlString)
            self?.cache.setObject(image, forKey: cacheKey)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    // Clear cache on logout
    func clearCache() {
        cache.removeAllObjects()
        // Clear network cache but keep user's own content
        MediaCacheService.shared.clearNetworkCache()
        Logger.debug("ImageService: Cleared image cache")
    }
    
    // Clear specific image from cache
    func clearCachedImage(for urlString: String) {
        let cacheKey = NSString(string: urlString)
        cache.removeObject(forKey: cacheKey)
        // Also clear from disk cache
        mediaCacheService.clearImage(for: urlString)
        Logger.debug("ImageService: Cleared cached image for URL: \(urlString)")
    }
    
    // Clear all profile picture caches
    func clearAllProfilePictureCaches() {
        // This is a nuclear option - clear all caches to fix profile picture issues
        cache.removeAllObjects()
        Logger.debug("ImageService: Cleared all profile picture caches")
    }
    
    func clearActivityFeedCaches() {
        // Clear potentially corrupted activity feed related image caches
        Logger.info("ImageService: Clearing activity feed image caches to fix corruption")
        
        // Since NSCache doesn't provide access to all keys, we'll use a more targeted approach
        // Clear the entire memory cache and let the disk cache cleanup handle the rest
        cache.removeAllObjects()
        
        // Also clear the disk cache of potentially corrupted content
        mediaCacheService.clearNetworkCache()
        
        Logger.info("ImageService: Cleared activity feed image cache entries")
    }
    
    // MARK: - Photo Migration
    
    /// Attempts to automatically migrate Google API photos to Firebase Storage
    private func attemptPhotoMigration(for originalUrl: String, completion: @escaping (UIImage?) -> Void) {
        Logger.info("ImageService: Starting automatic photo migration for URL: \(originalUrl)")
        
        // Extract place ID from the URL if possible
        // For now, trigger global migration and retry the image
        PlaceService.shared.migrateGooglePhotosToFirebase { [weak self] result in
            switch result {
            case .success:
                Logger.info("ImageService: Photo migration completed successfully")
                
                // Wait a moment for migration to complete, then retry the original URL
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // Try to download from the original URL again in case it's been updated
                    self?.downloadImageWithoutMigration(from: originalUrl, completion: completion)
                }
                
            case .failure(let error):
                Logger.error("ImageService: Photo migration failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    /// Downloads image without triggering migration (used after migration attempt)
    private func downloadImageWithoutMigration(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let image = UIImage(data: data),
                  error == nil else {
                Logger.info("ImageService: Migration retry failed, image still not available")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            Logger.info("ImageService: Successfully loaded image after migration")
            
            // Cache the image
            let cacheKey = NSString(string: urlString)
            self.cache.setObject(image, forKey: cacheKey)
            
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
