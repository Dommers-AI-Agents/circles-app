import UIKit

class ImageService {
    static let shared = ImageService()

    private let cache = NSCache<NSString, UIImage>()
    private let mediaCacheService = MediaCacheService.shared

    // In-flight download registry: N cells asking for the same URL share ONE
    // network request instead of firing N parallel downloads of it.
    private let inFlightLock = NSLock()
    private var inFlightCompletions: [String: [(UIImage?) -> Void]] = [:]

    // Source images larger than this on their longest side are downsampled
    // before caching — feed thumbnails/avatars never need more, and full-res
    // decode was the main-thread scroll cost.
    private let maxCachedDimension: CGFloat = 1200

    init() {
        // Bound the in-memory cache (was unbounded — grew until OS eviction)
        cache.countLimit = 150
        cache.totalCostLimit = 100 * 1024 * 1024 // ~100 MB
    }

    /// Cost (approx bytes) for NSCache accounting.
    private func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    /// Decodes image data off the main thread, downsampling to
    /// `maxCachedDimension` so huge source images don't blow up memory or
    /// cost a full-res main-thread decode on first draw.
    private func decodedImage(from data: Data) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxCachedDimension * UIScreen.main.scale
        ]
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        // Fallback: full decode, forced off first-draw
        return UIImage(data: data)?.preparingForDisplay()
    }

    // Alias for loadImage to maintain compatibility
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        // Stock avatars are drawn on device, not fetched — handled here so
        // every avatar surface in the app renders them without its own branch.
        if let stock = StockAvatar.image(from: urlString, diameter: 200) {
            completion(stock)
            return
        }
        downloadImage(from: urlString, completion: completion)
    }
    
    // Load image with custom cache key for better uniqueness
    func loadImageWithKey(from urlString: String, cacheKey: String, completion: @escaping (UIImage?) -> Void) {
        if let stock = StockAvatar.image(from: urlString, diameter: 200) {
            completion(stock)
            return
        }
        let key = NSString(string: cacheKey)
        
        // Check if image is in memory cache with custom key
        if let cachedImage = cache.object(forKey: key) {
            Logger.debug("ImageService: Found image in memory cache with custom key: \(cacheKey)")
            completion(cachedImage)
            return
        }
        
        // If not in cache with custom key, download normally
        downloadImage(from: urlString) { [weak self] image in
            if let image = image, let self = self {
                // Alias entry under the custom key for the sync lookups that
                // use it. Cost 0 on purpose: the URL-key entry (stored by the
                // download path) already carries this image's real cost, and
                // both keys hold the SAME UIImage instance — double-costing
                // was halving the cache's effective capacity.
                self.cache.setObject(image, forKey: key)
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

    /// Synchronous cache lookup by the SAME custom key used in
    /// loadImageWithKey. Lets callers set a cached image immediately (no
    /// placeholder flash) and only fall back to async loading on a miss.
    func cachedImage(forKey cacheKey: String) -> UIImage? {
        return cache.object(forKey: NSString(string: cacheKey))
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
            if let image = image, let self = self {
                Logger.debug("ImageService: Found image in disk cache for \(urlString)")
                // Add to memory cache (with cost, so eviction accounting works)
                self.cache.setObject(image, forKey: cacheKey, cost: self.cost(of: image))
                completion(image)
                return
            }
            
            // If not in any cache, download from network
            self?.downloadFromNetwork(urlString: urlString, completion: completion)
        }
    }
    
    /// Delivers a finished download to every waiter registered for this URL.
    private func finishDownload(_ urlString: String, with image: UIImage?) {
        inFlightLock.lock()
        let completions = inFlightCompletions.removeValue(forKey: urlString) ?? []
        inFlightLock.unlock()
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
        }
    }

    private func downloadFromNetwork(urlString: String, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = NSString(string: urlString)

        // Deduplicate concurrent requests: if this URL is already downloading,
        // just wait for that download's result.
        inFlightLock.lock()
        if inFlightCompletions[urlString] != nil {
            inFlightCompletions[urlString]?.append(completion)
            inFlightLock.unlock()
            return
        }
        inFlightCompletions[urlString] = [completion]
        inFlightLock.unlock()

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
            finishDownload(urlString, with: nil)
            return
        }

        // Additional validation for obviously invalid hostnames
        if host.contains("..") || host.hasPrefix(".") || host.hasSuffix(".") {
            Logger.error("ImageService: Invalid hostname format: \(host)")
            finishDownload(urlString, with: nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                Logger.error("ImageService: Download error: \(error.localizedDescription)")
                self.finishDownload(urlString, with: nil)
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

                    self.finishDownload(urlString, with: nil)
                    return
                } else if httpResponse.statusCode != 200 {
                    Logger.error("ImageService: HTTP Error - Status \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        Logger.debug("ImageService: Error response: \(errorString)")
                    }
                    self.finishDownload(urlString, with: nil)
                    return
                }
            }

            guard let data = data, let image = self.decodedImage(from: data) else {
                Logger.error("ImageService: Failed to create image from data")
                self.finishDownload(urlString, with: nil)
                return
            }

            // Cache the image in memory
            self.cache.setObject(image, forKey: cacheKey, cost: self.cost(of: image))

            // Cache the image to disk
            // Determine if this is user's own content based on URL patterns
            let isUserContent = self.isUserOwnContent(urlString: finalURLString)
            self.mediaCacheService.cacheImage(image, for: urlString, userId: AuthService.shared.getUserId(), isPermanent: isUserContent)

            self.finishDownload(urlString, with: image)
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
            
            guard let self = self, let data = data, let image = self.decodedImage(from: data) else {
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
            self.cache.setObject(image, forKey: cacheKey, cost: self.cost(of: image))
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    /// Warm the REAL display caches (memory NSCache + MediaCacheService disk)
    /// for a set of URLs. Replaces CacheService.preloadImages, which
    /// downloaded every avatar into a store the display path never read —
    /// and whose per-launch-seeded hash filenames guaranteed misses across
    /// launches — so each preloaded image was downloaded twice per session.
    /// The in-flight dedup above means a cell requesting the same URL moments
    /// later shares the preload's download instead of firing its own.
    func preloadImages(from urls: [String], completion: ((Int) -> Void)? = nil) {
        guard !urls.isEmpty else {
            completion?(0)
            return
        }
        let counterLock = NSLock()
        var loaded = 0
        let group = DispatchGroup()
        for url in urls {
            group.enter()
            loadImage(from: url) { image in
                if image != nil {
                    counterLock.lock()
                    loaded += 1
                    counterLock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion?(loaded)
        }
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
    
    // A feed full of expired Google photos must not fire one GLOBAL migration
    // per image — one at a time is plenty (it migrates everything anyway).
    private var isMigrationInFlight = false

    /// Attempts to automatically migrate Google API photos to Firebase Storage
    private func attemptPhotoMigration(for originalUrl: String, completion: @escaping (UIImage?) -> Void) {
        inFlightLock.lock()
        if isMigrationInFlight {
            inFlightLock.unlock()
            Logger.debug("ImageService: Photo migration already running — skipping duplicate trigger")
            completion(nil)
            return
        }
        isMigrationInFlight = true
        inFlightLock.unlock()

        Logger.info("ImageService: Starting automatic photo migration for URL: \(originalUrl)")

        // Extract place ID from the URL if possible
        // For now, trigger global migration and retry the image
        PlaceService.shared.migrateGooglePhotosToFirebase { [weak self] result in
            self?.inFlightLock.lock()
            self?.isMigrationInFlight = false
            self?.inFlightLock.unlock()
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
                  let image = self.decodedImage(from: data),
                  error == nil else {
                Logger.info("ImageService: Migration retry failed, image still not available")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            Logger.info("ImageService: Successfully loaded image after migration")

            // Cache the image
            let cacheKey = NSString(string: urlString)
            self.cache.setObject(image, forKey: cacheKey, cost: self.cost(of: image))
            
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
