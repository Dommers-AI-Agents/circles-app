import UIKit

class ImageService {
    static let shared = ImageService()
    
    private let cache = NSCache<NSString, UIImage>()
    
    // Alias for loadImage to maintain compatibility
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        downloadImage(from: urlString, completion: completion)
    }
    
    func downloadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = NSString(string: urlString)
        
        // Check if image is in cache
        if let cachedImage = cache.object(forKey: cacheKey) {
            Logger.debug("ImageService: Found image in cache for \(urlString)")
            completion(cachedImage)
            return
        }
        
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
            
            // Cache the image
            self.cache.setObject(image, forKey: cacheKey)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    // Clear cache on logout
    func clearCache() {
        cache.removeAllObjects()
        Logger.debug("ImageService: Cleared image cache")
    }
}
