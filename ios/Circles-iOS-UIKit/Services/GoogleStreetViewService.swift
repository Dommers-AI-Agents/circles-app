import Foundation
import CoreLocation

class GoogleStreetViewService {
    static let shared = GoogleStreetViewService()
    
    private let baseURL = "https://maps.googleapis.com/maps/api/streetview"
    private var apiKey: String? {
        return Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    }
    
    private init() {}
    
    struct StreetViewParameters {
        let location: CLLocationCoordinate2D
        let size: CGSize
        let heading: Double?
        let pitch: Double
        let fov: Double
        
        init(location: CLLocationCoordinate2D,
             size: CGSize = CGSize(width: 600, height: 400),
             heading: Double? = nil,
             pitch: Double = 0,
             fov: Double = 90) {
            self.location = location
            self.size = size
            self.heading = heading
            self.pitch = pitch
            self.fov = fov
        }
    }
    
    func generateStreetViewURL(parameters: StreetViewParameters) -> URL? {
        guard let apiKey = apiKey else {
            print("Google Maps API key not found in Info.plist")
            return nil
        }
        
        var components = URLComponents(string: baseURL)
        
        var queryItems = [
            URLQueryItem(name: "size", value: "\(Int(parameters.size.width))x\(Int(parameters.size.height))"),
            URLQueryItem(name: "location", value: "\(parameters.location.latitude),\(parameters.location.longitude)"),
            URLQueryItem(name: "pitch", value: "\(parameters.pitch)"),
            URLQueryItem(name: "fov", value: "\(parameters.fov)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        if let heading = parameters.heading {
            queryItems.append(URLQueryItem(name: "heading", value: "\(heading)"))
        }
        
        components?.queryItems = queryItems
        
        return components?.url
    }
    
    func checkStreetViewAvailability(at location: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) {
        guard let apiKey = apiKey else {
            completion(false)
            return
        }
        
        let metadataURL = "https://maps.googleapis.com/maps/api/streetview/metadata"
        var components = URLComponents(string: metadataURL)
        components?.queryItems = [
            URLQueryItem(name: "location", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                completion(false)
                return
            }
            
            completion(status == "OK")
        }.resume()
    }
    
    func downloadStreetViewImage(parameters: StreetViewParameters, completion: @escaping (Data?) -> Void) {
        guard let url = generateStreetViewURL(parameters: parameters) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Failed to download Street View image: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            completion(data)
        }.resume()
    }
}