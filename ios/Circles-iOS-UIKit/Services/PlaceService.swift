import Foundation
import CoreLocation
import UIKit

// IMPORTANT API USAGE POLICY:
// - Use Apple Maps API for EVERYTHING except photos
// - Only use Google Places API for fetching place photos
// - Apple Maps is more cost-efficient than Google Maps
// - See APIUsageGuidelines.md for detailed policy

enum PlaceError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    case creationFailed
    case updateFailed
    case deleteFailed
    case invalidLocation
    case locationNotFound
    case networkError(Error)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Place not found"
        case .permissionDenied:
            return "You don't have permission to access this place"
        case .invalidData:
            return "Invalid place data"
        case .creationFailed:
            return "Failed to create place"
        case .updateFailed:
            return "Failed to update place"
        case .deleteFailed:
            return "Failed to delete place"
        case .invalidLocation:
            return "Invalid location coordinates"
        case .locationNotFound:
            return "Couldn't find location for the provided address"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class PlaceService {
    static let shared = PlaceService()
    
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    // MARK: - Fetch Places
    
    func fetchPlacesByCircleId(circleId: String, completion: @escaping (Result<[Place], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/places",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<PlacesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.places))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func fetchPlaceById(id: String, completion: @escaping (Result<Place, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func searchPlaces(query: String, category: PlaceCategory? = nil, completion: @escaping (Result<[Place], Error>) -> Void) {
        var queryParams: [String: String] = [
            "q": query
        ]
        
        if let category = category {
            queryParams["category"] = category.rawValue
        }
        
        APIService.shared.request(
            endpoint: "places/search",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { [weak self] (result: Result<PlacesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.places))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    // MARK: - Create, Update, Delete
    
    func createPlaceFromGoogleData(_ googleData: [String: Any], completion: @escaping (Result<Place, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places",
            method: .post,
            body: googleData,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.creationFailed))
            }
        }
    }
    
    func createPlace(name: String, description: String?, address: String, category: PlaceCategory, customCategory: String? = nil, subcategory: String? = nil, circleId: String, privacy: PlacePrivacy = .followCirclePrivacy, website: String? = nil, phone: String? = nil, tags: [String]? = nil, photos: [Data]? = nil, photoUrls: [String]? = nil, location: CLLocationCoordinate2D? = nil, googlePlaceId: String? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        
        // Use provided location or geocode the address
        if let providedLocation = location {
            // If we have location and googlePlaceId but no photos, use addPlaceFromPOI to fetch photos
            if googlePlaceId != nil && (photoUrls?.isEmpty ?? true) && (photos?.isEmpty ?? true) {
                Logger.debug("Using addPlaceFromPOI to fetch photos for Google Place ID: \(googlePlaceId!)")
                let geoLocation = GeoLocation(type: "Point", coordinates: [providedLocation.longitude, providedLocation.latitude])
                self.addPlaceFromPOI(
                    name: name,
                    address: address,
                    location: geoLocation,
                    category: category,
                    website: website,
                    phone: phone,
                    description: description,
                    circleId: circleId,
                    notes: nil,
                    googlePlaceId: googlePlaceId,
                    preUploadedPhotoUrls: photoUrls,
                    completion: completion
                )
                return
            }
            
            // Otherwise, continue with standard flow
            continueCreatePlace(
                name: name,
                description: description,
                address: address,
                location: providedLocation,
                category: category,
                customCategory: customCategory,
                subcategory: subcategory,
                circleId: circleId,
                privacy: privacy,
                website: website,
                phone: phone,
                tags: tags,
                photos: photos,
                photoUrls: photoUrls,
                completion: completion
            )
        } else {
            // Geocode the address to get coordinates
            geocodeAddress(address) { [weak self] result in
                switch result {
                case .success(let location):
                    self?.continueCreatePlace(
                        name: name,
                        description: description,
                        address: address,
                        location: location,
                        category: category,
                        customCategory: customCategory,
                        subcategory: subcategory,
                        circleId: circleId,
                        privacy: privacy,
                        website: website,
                        phone: phone,
                        tags: tags,
                        photos: photos,
                        photoUrls: photoUrls,
                        completion: completion
                    )
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func continueCreatePlace(name: String, description: String?, address: String, location: CLLocationCoordinate2D, category: PlaceCategory, customCategory: String?, subcategory: String?, circleId: String, privacy: PlacePrivacy, website: String?, phone: String?, tags: [String]?, photos: [Data]?, photoUrls: [String]?, completion: @escaping (Result<Place, Error>) -> Void) {
        // If we already have photo URLs, use them directly
        if let urls = photoUrls, !urls.isEmpty {
            Logger.debug("Using \(urls.count) pre-uploaded photo URLs")
            self.performCreatePlace(
                name: name,
                description: description,
                address: address,
                location: location,
                category: category,
                customCategory: customCategory,
                subcategory: subcategory,
                circleId: circleId,
                privacy: privacy,
                website: website,
                phone: phone,
                tags: tags,
                photoUrls: urls,
                completion: completion
            )
        }
        // Otherwise upload photos if provided
        else if let photoDataArray = photos, !photoDataArray.isEmpty {
            Logger.info("Uploading \(photoDataArray.count) photos")
            self.uploadMultipleImages(photoDataArray) { photoUrlsResult in
                switch photoUrlsResult {
                case .success(let photoUrls):
                    // Create place with location and photo URLs
                    self.performCreatePlace(
                        name: name,
                        description: description,
                        address: address,
                        location: location,
                        category: category,
                        customCategory: customCategory,
                        subcategory: subcategory,
                        circleId: circleId,
                        privacy: privacy,
                        website: website,
                        phone: phone,
                        tags: tags,
                        photoUrls: photoUrls,
                        completion: completion
                    )
                case .failure(let error):
                    Logger.error("PlaceService: Failed to upload images: \(error)")
                    Logger.warning("PlaceService: Will create place without images")
                    // Continue creating the place without photos
                    self.performCreatePlace(
                        name: name,
                        description: description,
                        address: address,
                        location: location,
                        category: category,
                        customCategory: customCategory,
                        subcategory: subcategory,
                        circleId: circleId,
                        privacy: privacy,
                        website: website,
                        phone: phone,
                        tags: tags,
                        photoUrls: nil,
                        completion: completion
                    )
                }
            }
        } else {
            // Create place with location but no photos
            Logger.debug("Creating place without photos")
            self.performCreatePlace(
                name: name,
                description: description,
                address: address,
                location: location,
                category: category,
                customCategory: customCategory,
                subcategory: subcategory,
                circleId: circleId,
                privacy: privacy,
                website: website,
                phone: phone,
                tags: tags,
                photoUrls: nil,
                completion: completion
            )
        }
    }
    
    private func performCreatePlace(name: String, description: String?, address: String, location: CLLocationCoordinate2D, category: PlaceCategory, customCategory: String?, subcategory: String?, circleId: String, privacy: PlacePrivacy, website: String?, phone: String?, tags: [String]?, photoUrls: [String]?, completion: @escaping (Result<Place, Error>) -> Void) {
        
        var body: [String: Any] = [
            "name": name,
            "address": address,
            "location": [
                "type": "Point",
                "coordinates": [location.longitude, location.latitude]
            ],
            "category": category.rawValue,
            "circleId": circleId,
            "privacy": privacy.rawValue
        ]
        
        if let description = description {
            body["description"] = description
        }
        
        if let customCategory = customCategory {
            body["customCategory"] = customCategory
        }
        
        if let subcategory = subcategory {
            body["subcategory"] = subcategory
        }
        
        if let website = website {
            body["website"] = website
        }
        
        if let phone = phone {
            body["phone"] = phone
        }
        
        if let tags = tags {
            body["tags"] = tags
        }
        
        if let photoUrls = photoUrls, !photoUrls.isEmpty {
            body["photos"] = photoUrls
        }
        
        APIService.shared.request(
            endpoint: "places",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.creationFailed))
            }
        }
    }
    
    func updatePlace(id: String, privateNotes: String? = nil, publicNotes: String? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let privateNotes = privateNotes { body["privateNotes"] = privateNotes }
        if let publicNotes = publicNotes { body["publicNotes"] = publicNotes }
        
        APIService.shared.request(
            endpoint: "places/\(id)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.updateFailed))
            }
        }
    }
    
    // MARK: - Add Place from POI
    
    func addPlaceFromPOI(name: String, address: String, location: GeoLocation?, category: PlaceCategory, website: String? = nil, phone: String? = nil, description: String? = nil, circleId: String, notes: String?, googlePlaceId: String? = nil, preUploadedPhotoUrls: [String]? = nil, rating: Double? = nil, userRatingsTotal: Int? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        Logger.debug("PlaceService.addPlaceFromPOI called with name: \(name), googlePlaceId: \(googlePlaceId ?? "nil"), photos: \(preUploadedPhotoUrls?.count ?? 0)")
        
        var body: [String: Any] = [
            "name": name,
            "address": address,
            "category": category.rawValue,
            "circleId": circleId,
            "privacy": PlacePrivacy.followCirclePrivacy.rawValue
        ]
        
        if let location = location {
            body["location"] = [
                "type": location.type,
                "coordinates": location.coordinates
            ]
        }
        
        if let notes = notes {
            body["privateNotes"] = notes
        }
        
        if let website = website {
            body["website"] = website
        }
        
        if let phone = phone {
            body["phone"] = phone
        }
        
        if let description = description {
            body["description"] = description
        }
        
        if let googlePlaceId = googlePlaceId {
            body["googlePlaceId"] = googlePlaceId
        }
        
        if let rating = rating {
            body["rating"] = rating
        }
        
        if let userRatingsTotal = userRatingsTotal {
            body["userRatingsTotal"] = userRatingsTotal
        }
        
        // Start with pre-uploaded photos if available
        var collectedImageUrls: [String] = []
        if let preUploadedUrls = preUploadedPhotoUrls, !preUploadedUrls.isEmpty {
            Logger.debug("Starting with \(preUploadedUrls.count) pre-uploaded photos")
            collectedImageUrls.append(contentsOf: preUploadedUrls)
        }
        
        // Always try to collect Apple Look Around in addition to any pre-uploaded photos
        let imageCollectionGroup = DispatchGroup()
        
        // Try to get Apple Look Around image if location is available
        if let location = location, location.coordinates.count >= 2 {
            let latitude = location.coordinates[1]
            let longitude = location.coordinates[0]
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            // Collect Apple Look Around image
            if #available(iOS 16.0, *) {
                Logger.debug("Checking Apple Look Around availability at \(coordinate)")
                imageCollectionGroup.enter()
                Task {
                    let hasLookAround = await AppleLookAroundService.shared.checkLookAroundAvailability(at: coordinate)
                    
                    if hasLookAround {
                        Logger.debug("Look Around is available")
                        do {
                            // Get the Look Around snapshot
                            let lookAroundImage = try await AppleLookAroundService.shared.getLookAroundSnapshot(at: coordinate)
                            Logger.debug("Got Look Around snapshot")
                            
                            // Convert to JPEG data
                            if let imageData = lookAroundImage.jpegData(compressionQuality: 0.8) {
                                // Upload the image
                                self.uploadImage(imageData) { uploadResult in
                                    switch uploadResult {
                                    case .success(let imageUrl):
                                        collectedImageUrls.append(imageUrl)
                                        Logger.debug("Apple Look Around image uploaded successfully: \(imageUrl)")
                                    case .failure(let error):
                                        Logger.error("Failed to upload Look Around image: \(error)")
                                        Logger.warning("Will continue place creation without this image")
                                    }
                                    imageCollectionGroup.leave()
                                }
                            } else {
                                Logger.error("Failed to convert Look Around image to JPEG")
                                imageCollectionGroup.leave()
                            }
                        } catch {
                            Logger.error("Failed to get Look Around snapshot: \(error)")
                            imageCollectionGroup.leave()
                        }
                    } else {
                        Logger.debug("Look Around is NOT available at this location")
                        imageCollectionGroup.leave()
                    }
                }
            } else {
                print("⚠️ PlaceService: iOS version < 16.0, skipping Look Around")
            }
        }
        
        // Try to get Google Places photo if googlePlaceId is available and we don't already have Google photos
        // Skip if we already have pre-uploaded photos (which are likely Google Places photos)
        if let googlePlaceId = googlePlaceId, !googlePlaceId.isEmpty, collectedImageUrls.isEmpty {
            print("🔍 PlaceService: Fetching Google Places photo for placeId: \(googlePlaceId)")
            imageCollectionGroup.enter()
            
            // Fetch place details including photos
            GooglePlacesService.shared.fetchPlaceDetails(placeID: googlePlaceId) { result in
                switch result {
                case .success(let place):
                    // Get the first photo if available
                    if let photoMetadata = place.photos?.first {
                        print("📸 PlaceService: Found Google Places photo metadata, loading photo...")
                        GooglePlacesService.shared.loadPhoto(from: photoMetadata) { photoResult in
                            switch photoResult {
                            case .success(let image):
                                print("✅ PlaceService: Google Places photo loaded successfully")
                                // Convert to JPEG and upload
                                if let imageData = image.jpegData(compressionQuality: 0.8) {
                                    print("📸 PlaceService: Converting Google photo to JPEG (size: \(imageData.count / 1024) KB)")
                                    self.uploadImage(imageData) { uploadResult in
                                        switch uploadResult {
                                        case .success(let imageUrl):
                                            collectedImageUrls.append(imageUrl)
                                            print("✅ PlaceService: Google Places photo uploaded successfully: \(imageUrl)")
                                        case .failure(let error):
                                            print("❌ PlaceService: Failed to upload Google Places photo: \(error)")
                                            print("⚠️ PlaceService: Will continue place creation without this image")
                                            
                                            // Check if it's specifically a server error
                                            if let apiError = error as? APIError, case .serverError = apiError {
                                                print("🔧 PlaceService: Server error - Firebase Storage may not be configured properly")
                                                print("🔧 PlaceService: Run: gcloud run services update circles-backend --update-env-vars FIREBASE_STORAGE_BUCKET=circles-app-83b67.appspot.com --region us-central1")
                                            }
                                        }
                                        imageCollectionGroup.leave()
                                    }
                                } else {
                                    print("❌ PlaceService: Failed to convert Google Places photo to JPEG")
                                    imageCollectionGroup.leave()
                                }
                            case .failure(let error):
                                print("❌ PlaceService: Failed to load Google Places photo: \(error)")
                                imageCollectionGroup.leave()
                            }
                        }
                    } else {
                        print("⚠️ PlaceService: No photos available from Google Places")
                        imageCollectionGroup.leave()
                    }
                case .failure(let error):
                    print("❌ PlaceService: Failed to fetch Google Place details: \(error)")
                    imageCollectionGroup.leave()
                }
            }
        } else {
            if !collectedImageUrls.isEmpty {
                print("⚠️ PlaceService: Skipping Google Places photo - already have pre-uploaded photos")
            } else {
                print("⚠️ PlaceService: No googlePlaceId provided or empty, skipping Google Places photo")
            }
        }
        
        // Wait for all image collection tasks to complete
        imageCollectionGroup.notify(queue: .main) {
            print("🔔 PlaceService: All image collection tasks completed")
            
            // Add collected images to the body
            if !collectedImageUrls.isEmpty {
                body["photos"] = collectedImageUrls
                print("📸 PlaceService: Collected \(collectedImageUrls.count) images for the place")
                for (index, url) in collectedImageUrls.enumerated() {
                    print("  Image \(index + 1): \(url)")
                }
            } else {
                print("⚠️ PlaceService: No images were collected for the place")
                print("⚠️ PlaceService: Creating place without images - image upload may have failed")
                print("🔧 PlaceService: If images aren't uploading, check Firebase Storage configuration")
            }
            
            print("📤 PlaceService: About to create place with \(body.keys.count) fields")
            
            // Create the place with collected images (or without if upload failed)
            self.createPlaceWithBody(body, completion: completion)
        }
    }
    
    private func createPlaceWithBody(_ body: [String: Any], completion: @escaping (Result<Place, Error>) -> Void) {
        print("🚀 PlaceService: Creating place with body containing \(body.keys.count) fields")
        if let photos = body["photos"] as? [String] {
            print("  Photos in request: \(photos.count)")
        }
        
        APIService.shared.request(
            endpoint: "places",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ PlaceService: Place created successfully")
                if let photos = response.place.photos {
                    print("  Photos in response: \(photos.count)")
                    for (index, photo) in photos.enumerated() {
                        print("  Photo \(index + 1): \(photo)")
                    }
                } else {
                    print("  ⚠️ No photos in response")
                }
                completion(.success(response.place))
            case .failure(let error):
                print("❌ PlaceService: Failed to create place: \(error)")
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.creationFailed))
            }
        }
    }
    
    func updatePlace(id: String, name: String? = nil, description: String? = nil, address: String? = nil, category: PlaceCategory? = nil, customCategory: String? = nil, privacy: PlacePrivacy? = nil, website: String? = nil, phone: String? = nil, tags: [String]? = nil, addPhotos: [Data]? = nil, removePhotoUrls: [String]? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        
        var locationCoordinate: CLLocationCoordinate2D?
        var photosUrls: [String]?
        var geocodeError: Error?
        var uploadError: Error?
        
        let taskGroup = DispatchGroup()
        
        // If address is provided, geocode it
        if let address = address {
            taskGroup.enter()
            geocodeAddress(address) { result in
                switch result {
                case .success(let location):
                    locationCoordinate = location
                case .failure(let error):
                    geocodeError = error
                }
                taskGroup.leave()
            }
        }
        
        // If photos are provided, upload them
        if let photos = addPhotos, !photos.isEmpty {
            taskGroup.enter()
            uploadMultipleImages(photos) { result in
                switch result {
                case .success(let urls):
                    photosUrls = urls
                case .failure(let error):
                    uploadError = error
                }
                taskGroup.leave()
            }
        }
        
        // After all async tasks are done, update the place
        taskGroup.notify(queue: .main) {
            // Check for errors
            if let error = geocodeError {
                completion(.failure(error))
                return
            }
            
            if let error = uploadError {
                completion(.failure(error))
                return
            }
            
            // Start building the update body
            var body: [String: Any] = [:]
            
            if let name = name {
                body["name"] = name
            }
            
            if let description = description {
                body["description"] = description
            }
            
            if let newAddress = address {
                body["address"] = newAddress
                
                // Add location if geocoding was successful
                if let location = locationCoordinate {
                    body["location"] = [
                        "type": "Point",
                        "coordinates": [location.longitude, location.latitude]
                    ]
                }
            }
            
            if let category = category {
                body["category"] = category.rawValue
            }
            
            if let customCategory = customCategory {
                body["customCategory"] = customCategory
            }
            
            if let privacy = privacy {
                body["privacy"] = privacy.rawValue
            }
            
            if let website = website {
                body["website"] = website
            }
            
            if let phone = phone {
                body["phone"] = phone
            }
            
            if let tags = tags {
                body["tags"] = tags
            }
            
            // Add new photo URLs if any were uploaded
            if let urls = photosUrls, !urls.isEmpty {
                body["addPhotos"] = urls
            }
            
            // Add URLs of photos to remove
            if let removePhotoUrls = removePhotoUrls, !removePhotoUrls.isEmpty {
                body["removePhotos"] = removePhotoUrls
            }
            
            // Only proceed if there are changes to make
            guard !body.isEmpty else {
                completion(.failure(PlaceError.invalidData))
                return
            }
            
            APIService.shared.request(
                endpoint: "places/\(id)",
                method: .put,
                body: body,
                requiresAuth: true
            ) { [weak self] (result: Result<PlaceResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.place))
                case .failure(let error):
                    let mappedError = self?.mapAPIErrorToPlaceError(error)
                    completion(.failure(mappedError ?? PlaceError.updateFailed))
                }
            }
        }
    }
    
    func deletePlace(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                // Post notification to refresh circles data
                NotificationCenter.default.post(
                    name: Notification.Name("PlaceDeleted"),
                    object: nil,
                    userInfo: ["placeId": id]
                )
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.deleteFailed))
            }
        }
    }
    
    func refreshPlaceFromGoogle(id: String, completion: @escaping (Result<Place, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)/refresh-google",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.updateFailed))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func geocodeAddress(_ address: String, completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let error = error {
                completion(.failure(PlaceError.networkError(error)))
                return
            }
            
            guard let placemark = placemarks?.first,
                  let location = placemark.location?.coordinate else {
                completion(.failure(PlaceError.locationNotFound))
                return
            }
            
            completion(.success(location))
        }
    }
    
    func uploadMultipleImages(_ imagesData: [Data], completion: @escaping (Result<[String], Error>) -> Void) {
        let uploadGroup = DispatchGroup()
        var uploadedUrls: [String] = []
        var uploadError: Error?
        
        for imageData in imagesData {
            uploadGroup.enter()
            
            uploadImage(imageData) { result in
                switch result {
                case .success(let url):
                    uploadedUrls.append(url)
                case .failure(let error):
                    uploadError = error
                }
                
                uploadGroup.leave()
            }
        }
        
        uploadGroup.notify(queue: .main) {
            if let error = uploadError {
                completion(.failure(error))
            } else {
                completion(.success(uploadedUrls))
            }
        }
    }
    
    private func uploadImage(_ imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        uploadImageWithCompression(imageData, compressionQuality: 1.0, attemptNumber: 1, completion: completion)
    }
    
    private func uploadImageWithCompression(_ imageData: Data, compressionQuality: Float, attemptNumber: Int, completion: @escaping (Result<String, Error>) -> Void) {
        // IMPORTANT: Image Compression Strategy
        // Goal: Keep images under 1MB to prevent storage costs and upload failures
        // Strategy: Progressive compression with quality reduction and resizing
        // Note: Backend has a hard limit of 1MB for base64 encoded images
        
        // Log image size
        let imageSizeInKB = Double(imageData.count) / 1024.0
        print("📸 Uploading image - size: \(String(format: "%.0f", imageSizeInKB)) KB (attempt #\(attemptNumber), quality: \(compressionQuality))")
        
        // CRITICAL: Max size is 1MB (1024KB) to match backend limits
        // DO NOT increase this without also updating backend/routes/uploadRoutes.js
        let maxSizeKB: Double = 1024 // 1MB - DO NOT CHANGE
        let maxAttempts = 6
        // Progressive compression levels - will try each until under 1MB
        let compressionLevels: [Float] = [0.8, 0.6, 0.4, 0.2, 0.1, 0.05]
        
        var dataToUpload = imageData
        
        if imageSizeInKB > maxSizeKB && attemptNumber <= maxAttempts {
            print("⚠️ Image size exceeds \(maxSizeKB)KB limit, attempting to compress...")
            
            // Try to compress the image further
            if let image = UIImage(data: imageData),
               attemptNumber <= compressionLevels.count {
                
                // Progressive resizing strategy based on attempt number
                var imageToCompress = image
                
                // Start resizing earlier and more aggressively to achieve 1MB goal
                if attemptNumber >= 2 { // Start resizing on second attempt
                    let resizeDimensions: [CGFloat] = [2048, 1920, 1280, 1024, 800, 640]
                    let dimensionIndex = min(attemptNumber - 2, resizeDimensions.count - 1)
                    let maxDimension = resizeDimensions[dimensionIndex]
                    
                    let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                    if scale < 1.0 {
                        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                        image.draw(in: CGRect(origin: .zero, size: newSize))
                        if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                            imageToCompress = resizedImage
                            print("📐 Resized image to \(Int(newSize.width))x\(Int(newSize.height)) (max dimension: \(Int(maxDimension)))")
                        }
                        UIGraphicsEndImageContext()
                    }
                }
                
                if let compressedData = imageToCompress.jpegData(compressionQuality: CGFloat(compressionLevels[attemptNumber - 1])) {
                    let compressedSizeKB = Double(compressedData.count) / 1024.0
                    print("📸 Compressed image size: \(String(format: "%.0f", compressedSizeKB)) KB with quality \(compressionLevels[attemptNumber - 1])")
                    
                    // If still too large and we have more compression levels to try
                    if compressedSizeKB > maxSizeKB && attemptNumber < compressionLevels.count {
                        uploadImageWithCompression(compressedData, compressionQuality: compressionLevels[attemptNumber], attemptNumber: attemptNumber + 1, completion: completion)
                        return
                    }
                    
                    // Use the compressed data even if slightly over limit on final attempt
                    dataToUpload = compressedData
                }
            } else {
                print("⚠️ Unable to compress image further, uploading as is...")
            }
        }
        
        // Convert image data to base64
        let base64String = dataToUpload.base64EncodedString()
        let filename = "place-\(UUID().uuidString).jpg"
        
        // Log base64 size (about 33% larger than original)
        let base64SizeInKB = Double(base64String.count) / 1024.0
        print("📸 Base64 encoded size: \(String(format: "%.0f", base64SizeInKB)) KB")
        
        let body: [String: Any] = [
            "image": base64String,
            "filename": filename
        ]
        
        print("📤 Sending image upload request...")
        
        APIService.shared.request(
            endpoint: "upload/image",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<ImageUploadResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ Image uploaded successfully: \(response.url)")
                completion(.success(response.url))
            case .failure(let error):
                print("❌ Failed to upload image: \(error)")
                print("   Error details: \(error.localizedDescription)")
                
                // Provide more specific error message
                switch error {
                case .httpError(let statusCode, let messageData):
                    let message = messageData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                    print("   HTTP Error \(statusCode): \(message)")
                case .serverError:
                    print("   Server error - image may be too large or invalid")
                default:
                    print("   Error type: \(error)")
                }
                
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update Place Order
    
    func updatePlaceOrder(circleId: String, placeIds: [String]) async throws {
        let body: [String: Any] = [
            "placeIds": placeIds
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(
                endpoint: "circles/\(circleId)/places/reorder",
                method: .put,
                body: body,
                requiresAuth: true
            ) { [weak self] (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    let mappedError = self?.mapAPIErrorToPlaceError(error) ?? PlaceError.unknown
                    continuation.resume(throwing: mappedError)
                }
            }
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIErrorToPlaceError(_ error: APIError) -> PlaceError {
        switch error {
        case .httpError(let statusCode, _):
            switch statusCode {
            case 403:
                return .permissionDenied
            case 404:
                return .notFound
            case 400:
                return .invalidData
            default:
                return .unknown
            }
            
        case .unauthorized:
            return .permissionDenied
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed, .duplicateRequest:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown
        }
    }
    
    // MARK: - Like/Unlike Place
    
    func likePlace(id: String, completion: @escaping (Result<Place, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)/like",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    // MARK: - Add Existing Place to Circle
    
    func addExistingPlaceToCircle(placeId: String, circleId: String, notes: String? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        var body: [String: Any] = [:]
        
        if let notes = notes {
            body["notes"] = notes
        }
        
        // The API endpoint expects circleId in the URL path, not in the body
        let endpoint = "places/\(placeId)/add-to-circle/\(circleId)"
        Logger.info("Adding existing place to circle - Endpoint: \(endpoint)")
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body.isEmpty ? nil : body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                // Return the actual place from the response
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    // MARK: - Comments
    
    func getPlaceComments(placeId: String, completion: @escaping (Result<[PlaceComment], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(placeId)/comments",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceCommentsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.comments))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func addPlaceComment(placeId: String, text: String, completion: @escaping (Result<PlaceComment, Error>) -> Void) {
        let body = ["text": text]
        
        APIService.shared.request(
            endpoint: "places/\(placeId)/comments",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceCommentResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.comment))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func deletePlaceComment(placeId: String, commentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(placeId)/comments/\(commentId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
}

// MARK: - Response Types

struct PlacesResponse: Decodable {
    let success: Bool
    let places: [Place]
}

struct PlaceResponse: Decodable {
    let success: Bool
    let place: Place
}

struct PlaceCommentsResponse: Decodable {
    let success: Bool
    let comments: [PlaceComment]
}

struct PlaceCommentResponse: Decodable {
    let success: Bool
    let comment: PlaceComment
}

// MARK: - PlaceComment Model

struct PlaceComment: Codable, Identifiable {
    let id: String
    let placeId: String
    let userId: String
    let text: String
    let createdAt: Date
    let user: User? // Populated when fetching comments
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case placeId, userId, text, createdAt, user
    }
}
