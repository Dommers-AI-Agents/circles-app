import Foundation
import UIKit
import CoreLocation

class StreetViewService {
    static let shared = StreetViewService()
    
    private let apiKey: String? = ProcessInfo.processInfo.environment["GOOGLE_STREET_VIEW_API_KEY"]
    private let imageCache = NSCache<NSString, UIImage>()
    
    private init() {
        imageCache.countLimit = 50 // Cache up to 50 images
    }
    
    // MARK: - Get Street View Image URL
    
    func getStreetViewImageURL(
        latitude: Double,
        longitude: Double,
        size: CGSize = CGSize(width: 600, height: 400),
        heading: Int? = nil,
        fov: Int = 90,
        pitch: Int = 0
    ) -> URL? {
        guard let apiKey = apiKey else {
            print("⚠️ Google Street View API key not configured")
            return nil
        }
        
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview")
        components?.queryItems = [
            URLQueryItem(name: "size", value: "\(Int(size.width))x\(Int(size.height))"),
            URLQueryItem(name: "location", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "fov", value: "\(fov)"),
            URLQueryItem(name: "pitch", value: "\(pitch)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        if let heading = heading {
            components?.queryItems?.append(URLQueryItem(name: "heading", value: "\(heading)"))
        }
        
        return components?.url
    }
    
    // MARK: - Fetch Street View Image
    
    func fetchStreetViewImage(
        latitude: Double,
        longitude: Double,
        size: CGSize = CGSize(width: 600, height: 400),
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        // Check cache first
        let cacheKey = "\(latitude),\(longitude)" as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            completion(.success(cachedImage))
            return
        }
        
        guard let url = getStreetViewImageURL(latitude: latitude, longitude: longitude, size: size) else {
            completion(.failure(StreetViewError.apiKeyMissing))
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(.failure(StreetViewError.invalidImageData))
                }
                return
            }
            
            // Cache the image
            self?.imageCache.setObject(image, forKey: cacheKey)
            
            DispatchQueue.main.async {
                completion(.success(image))
            }
        }.resume()
    }
    
    // MARK: - Check Street View Availability
    
    func checkStreetViewAvailability(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Bool) -> Void
    ) {
        guard let apiKey = apiKey else {
            completion(false)
            return
        }
        
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview/metadata")
        components?.queryItems = [
            URLQueryItem(name: "location", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(status == "OK")
            }
        }.resume()
    }
    
    // MARK: - Get Best Street View Image
    
    func getBestStreetViewImage(
        for place: Place,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        guard let location = place.location else {
            completion(.failure(StreetViewError.noLocation))
            return
        }
        
        let latitude = location.coordinates[1]
        let longitude = location.coordinates[0]
        
        // First check if Street View is available
        checkStreetViewAvailability(latitude: latitude, longitude: longitude) { [weak self] isAvailable in
            if isAvailable {
                self?.fetchStreetViewImage(
                    latitude: latitude,
                    longitude: longitude,
                    completion: completion
                )
            } else {
                // Try to get a static map image as fallback
                self?.fetchStaticMapImage(
                    latitude: latitude,
                    longitude: longitude,
                    completion: completion
                )
            }
        }
    }
    
    // MARK: - Static Map Fallback
    
    private func fetchStaticMapImage(
        latitude: Double,
        longitude: Double,
        zoom: Int = 17,
        size: CGSize = CGSize(width: 600, height: 400),
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        guard let apiKey = apiKey else {
            completion(.failure(StreetViewError.apiKeyMissing))
            return
        }
        
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")
        components?.queryItems = [
            URLQueryItem(name: "center", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "zoom", value: "\(zoom)"),
            URLQueryItem(name: "size", value: "\(Int(size.width))x\(Int(size.height))"),
            URLQueryItem(name: "markers", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            completion(.failure(StreetViewError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(.failure(StreetViewError.invalidImageData))
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(.success(image))
            }
        }.resume()
    }
    
    // MARK: - Upload Street View to Backend
    
    func uploadStreetViewImage(
        for place: Place,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        getBestStreetViewImage(for: place) { result in
            switch result {
            case .success(let image):
                // Convert to JPEG with compression
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    completion(.failure(StreetViewError.imageCompressionFailed))
                    return
                }
                
                // Upload using existing image upload service
                let base64String = imageData.base64EncodedString()
                let body: [String: Any] = [
                    "image": base64String,
                    "filename": "streetview-\(place.id).jpg"
                ]
                
                APIService.shared.request(
                    endpoint: "upload/image",
                    method: .post,
                    body: body,
                    requiresAuth: true
                ) { (result: Result<ImageUploadResponse, APIError>) in
                    switch result {
                    case .success(let response):
                        completion(.success(response.url))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Errors

enum StreetViewError: LocalizedError {
    case apiKeyMissing
    case noLocation
    case invalidURL
    case invalidImageData
    case imageCompressionFailed
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Google Street View API key is not configured"
        case .noLocation:
            return "Place has no location coordinates"
        case .invalidURL:
            return "Invalid URL generated for Street View"
        case .invalidImageData:
            return "Failed to load image data"
        case .imageCompressionFailed:
            return "Failed to compress image for upload"
        }
    }
}