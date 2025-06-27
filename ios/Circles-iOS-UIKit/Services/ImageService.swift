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
        
        // Debug logging
        print("ImageService: Attempting to load image from URL: \(urlString)")
        
        // Check if image is in cache
        if let cachedImage = cache.object(forKey: cacheKey) {
            print("ImageService: Found image in cache")
            completion(cachedImage)
            return
        }
        
        // Check if URL needs base URL prepended (for relative URLs)
        var finalURLString = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            // This is a relative URL, prepend the base URL
            let baseURL = "https://circles-backend-196924649787.us-central1.run.app"
            finalURLString = baseURL + (urlString.hasPrefix("/") ? "" : "/") + urlString
            print("ImageService: Converted relative URL to absolute: \(finalURLString)")
        }
        
        // Download image
        guard let url = URL(string: finalURLString) else {
            print("ImageService: Invalid URL: \(finalURLString)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("ImageService: Download error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("ImageService: HTTP Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 403 {
                    print("ImageService: ⚠️ HTTP 403 Forbidden - This image may be from an old Firebase project")
                    print("ImageService: URL attempted: \(url)")
                    
                    // Check if this is an old Firebase project URL
                    if finalURLString.contains("circles-app-4902d") {
                        print("ImageService: 🔄 This is an image from the old Firebase project. It needs to be re-uploaded.")
                    }
                    
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                } else if httpResponse.statusCode != 200 {
                    print("ImageService: HTTP Error - Status \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("ImageService: Error response: \(errorString)")
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
            }
            
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                print("ImageService: Failed to create image from data")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            print("ImageService: Successfully downloaded image")
            
            // Cache the image
            self.cache.setObject(image, forKey: cacheKey)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}
