import Foundation
import WebKit
import MapKit
import CoreLocation
import GooglePlaces

class PlaceEnrichmentService {
    static let shared = PlaceEnrichmentService()
    
    private init() {}
    
    // MARK: - Enrich Place Details
    
    func enrichPlaceDetails(
        name: String,
        address: String,
        category: PlaceCategory,
        coordinate: (latitude: Double, longitude: Double),
        completion: @escaping (Result<WebEnrichedPlaceDetails, Error>) -> Void
    ) {
        // First try to get rating from Google Places
        fetchGooglePlacesRating(name: name, coordinate: coordinate) { [weak self] ratingResult in
            var baseDetails = WebEnrichedPlaceDetails()
            
            // Add rating if available
            if case .success(let ratingInfo) = ratingResult {
                baseDetails.rating = ratingInfo.rating
                baseDetails.userRatingsTotal = ratingInfo.userRatingsTotal
            }
            
            // Create search query for web enrichment
            let searchQuery = "\(name) \(address)"
            let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            
            // Search for place information using DuckDuckGo (privacy-focused)
            let searchURL = "https://duckduckgo.com/?q=\(encodedQuery)"
            
            // For now, we'll use a web view to fetch structured data
            self?.fetchWebPageData(url: searchURL) { result in
                switch result {
                case .success(let html):
                    var enrichedDetails = self?.parseEnrichedDetails(from: html, placeName: name) ?? WebEnrichedPlaceDetails()
                    
                    // Add rating data from Google Places
                    enrichedDetails.rating = baseDetails.rating
                    enrichedDetails.userRatingsTotal = baseDetails.userRatingsTotal
                    
                    // Try to get additional details from a business search
                    self?.searchBusinessDetails(name: name, address: address) { businessResult in
                        switch businessResult {
                        case .success(let businessDetails):
                            // Merge details
                            var finalDetails = enrichedDetails
                            finalDetails.website = businessDetails.website ?? enrichedDetails.website
                            finalDetails.phone = businessDetails.phone ?? enrichedDetails.phone
                            finalDetails.hours = businessDetails.hours ?? enrichedDetails.hours
                            // Prefer Google Places rating over web-scraped rating
                            if finalDetails.rating == nil {
                                finalDetails.rating = businessDetails.rating
                            }
                            completion(.success(finalDetails))
                        case .failure:
                            // Return what we have
                            completion(.success(enrichedDetails))
                        }
                    }
                case .failure(let error):
                    // Still return rating data even if web enrichment fails
                    completion(.success(baseDetails))
                }
            }
        }
    }
    
    // MARK: - Google Places Rating Fetch
    
    private func fetchGooglePlacesRating(
        name: String,
        coordinate: (latitude: Double, longitude: Double),
        completion: @escaping (Result<(rating: Double?, userRatingsTotal: Int?), Error>) -> Void
    ) {
        // Find the place using Google Places search
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        print("🌟 Fetching rating for: \(name) at \(coordinate)")
        
        GooglePlacesService.shared.searchPlaces(query: name, location: location) { result in
            switch result {
            case .success(let predictions):
                if let firstPrediction = predictions.first {
                    // We found a matching place, now get its details including rating
                    GooglePlacesService.shared.fetchPlaceDetails(placeID: firstPrediction.placeID) { detailsResult in
                        switch detailsResult {
                        case .success(let place):
                            let rating = place.rating > 0 ? Double(place.rating) : nil
                            let userRatingsTotal = place.userRatingsTotal > 0 ? Int(place.userRatingsTotal) : nil
                            print("✅ Got rating: \(rating ?? 0) from \(userRatingsTotal ?? 0) reviews")
                            completion(.success((rating: rating, userRatingsTotal: userRatingsTotal)))
                        case .failure(let error):
                            print("❌ Failed to fetch place details for rating: \(error)")
                            // Don't fail the entire enrichment process
                            completion(.success((rating: nil, userRatingsTotal: nil)))
                        }
                    }
                } else {
                    // No matching place found
                    print("⚠️ No matching place found for rating lookup")
                    completion(.success((rating: nil, userRatingsTotal: nil)))
                }
            case .failure(let error):
                print("❌ Failed to search for place: \(error)")
                // Don't fail the entire enrichment process, just return nil ratings
                completion(.success((rating: nil, userRatingsTotal: nil)))
            }
        }
    }
    
    // MARK: - Business Search
    
    private func searchBusinessDetails(
        name: String,
        address: String,
        completion: @escaping (Result<BusinessDetails, Error>) -> Void
    ) {
        // Use a business directory API or web scraping
        // For now, we'll simulate with basic web search
        let searchQuery = "\(name) \(address) hours phone"
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Search using a different approach - look for structured data
        let businessSearchURL = "https://www.bing.com/search?q=\(encodedQuery)"
        
        fetchWebPageData(url: businessSearchURL) { [weak self] result in
            switch result {
            case .success(let html):
                let details = self?.parseBusinessDetails(from: html) ?? BusinessDetails()
                completion(.success(details))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Web Data Fetching
    
    private func fetchWebPageData(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: url) else {
            completion(.failure(PlaceEnrichmentError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(.failure(PlaceEnrichmentError.noData))
                return
            }
            
            completion(.success(html))
        }.resume()
    }
    
    // MARK: - Parsing Methods
    
    private func parseEnrichedDetails(from html: String, placeName: String) -> WebEnrichedPlaceDetails {
        var details = WebEnrichedPlaceDetails()
        
        // Look for common patterns in search results
        // Phone number pattern
        if let phoneMatch = html.range(of: #"(\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})"#, options: .regularExpression) {
            details.phone = String(html[phoneMatch])
        }
        
        // Website pattern - look for official website mentions
        if let websiteMatch = html.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) {
            let urlString = String(html[websiteMatch])
            // Filter out search engine URLs
            if !urlString.contains("duckduckgo") && !urlString.contains("bing") && !urlString.contains("google") {
                details.website = urlString
            }
        }
        
        // Hours pattern - look for business hours
        if let hoursMatch = html.range(of: #"(Monday|Mon|Tuesday|Tue|Wednesday|Wed|Thursday|Thu|Friday|Fri|Saturday|Sat|Sunday|Sun)[^<]{0,50}(AM|PM|am|pm)"#, options: .regularExpression) {
            details.hours = String(html[hoursMatch])
        }
        
        return details
    }
    
    private func parseBusinessDetails(from html: String) -> BusinessDetails {
        var details = BusinessDetails()
        
        // Look for structured data in search results
        // Bing often shows business info in a card format
        
        // Phone number
        if let phoneMatch = html.range(of: #"tel:(\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})"#, options: .regularExpression) {
            let fullMatch = String(html[phoneMatch])
            details.phone = fullMatch.replacingOccurrences(of: "tel:", with: "")
        }
        
        // Website - look for official website link
        if let websiteSection = html.range(of: #"Official website[^>]*>([^<]+)<"#, options: [.regularExpression, .caseInsensitive]) {
            let match = String(html[websiteSection])
            if let urlMatch = match.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) {
                details.website = String(match[urlMatch])
            }
        }
        
        // Business hours - look for structured hours data
        var hoursArray: [String] = []
        let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        
        for day in daysOfWeek {
            if let dayRange = html.range(of: "\(day)[^<]{0,30}(\\d{1,2}:\\d{2}\\s*(AM|PM|am|pm))[^<]{0,30}(\\d{1,2}:\\d{2}\\s*(AM|PM|am|pm))", options: .regularExpression) {
                hoursArray.append(String(html[dayRange]))
            }
        }
        
        if !hoursArray.isEmpty {
            details.hours = hoursArray.joined(separator: "\n")
        }
        
        return details
    }
    
    // MARK: - Google Street View Integration
    
    func getStreetViewImageURL(
        latitude: Double,
        longitude: Double,
        heading: Int = 0,
        fov: Int = 90,
        pitch: Int = 0
    ) -> String? {
        // Note: This requires a Google Street View API key to be configured
        // For now, return nil as we need API key setup
        
        // When API key is available:
        // let apiKey = "YOUR_GOOGLE_STREET_VIEW_API_KEY"
        // return "https://maps.googleapis.com/maps/api/streetview?size=600x400&location=\(latitude),\(longitude)&heading=\(heading)&fov=\(fov)&pitch=\(pitch)&key=\(apiKey)"
        
        return nil
    }
    
    // Alternative: Use Apple's Look Around (iOS 16+)
    @available(iOS 16.0, *)
    func checkLookAroundAvailability(
        coordinate: CLLocationCoordinate2D,
        completion: @escaping (Bool) -> Void
    ) {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        request.getSceneWithCompletionHandler { scene, error in
            DispatchQueue.main.async {
                completion(scene != nil)
            }
        }
    }
}

// MARK: - Supporting Types

struct WebEnrichedPlaceDetails {
    var website: String?
    var phone: String?
    var hours: String?
    var description: String?
    var priceRange: String?
    var features: [String]?
    var rating: Double?
    var userRatingsTotal: Int?
}

struct BusinessDetails {
    var website: String?
    var phone: String?
    var hours: String?
    var rating: Double?
    var reviewCount: Int?
}

enum PlaceEnrichmentError: LocalizedError {
    case invalidURL
    case noData
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .noData:
            return "No data received from web request"
        case .parsingError:
            return "Failed to parse web data"
        }
    }
}