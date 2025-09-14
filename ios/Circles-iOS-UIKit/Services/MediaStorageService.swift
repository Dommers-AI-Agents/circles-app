import Foundation
import UIKit

// MARK: - Media Storage Types
enum MediaStorageType {
    case placePhoto
    case placeVideo
    case momentPhoto
    case momentVideo
}

struct StorageResult {
    let mediaType: MediaStorageType
    let place: Place
    let storageUrls: [String: String]
    let metadata: [String: Any]
}

// MARK: - Upload Progress
struct UploadProgress {
    let progress: Double
    let bytesUploaded: Int64
    let totalBytes: Int64
    let phase: UploadPhase
    
    enum UploadPhase {
        case initiating
        case uploading
        case finalizing
        case completed
    }
}

// MARK: - Media Storage Service
class MediaStorageService {
    
    static let shared = MediaStorageService()
    
    private init() {}
    
    // MARK: - Photo Upload
    
    /// Upload processed photo to Firebase Storage (unified for both Places and Moments)
    func uploadPhoto(
        _ photo: ProcessedPhoto,
        for place: Place,
        type: MediaStorageType,
        visibility: String = "public",
        progress: @escaping (UploadProgress) -> Void = { _ in },
        completion: @escaping (Result<StorageResult, Error>) -> Void
    ) {
        progress(UploadProgress(progress: 0.0, bytesUploaded: 0, totalBytes: Int64(photo.sizeInBytes), phase: .initiating))
        
        // Use Global Place system for place photos
        if type == .placePhoto {
            uploadPhotoToGlobalPlace(photo, for: place, visibility: visibility, progress: progress, completion: completion)
            return
        }
        
        // Legacy flow for moments
        // Determine content type and API endpoint based on storage type
        let (contentType, endpoint) = getPhotoUploadConfig(for: type)
        
        // Prepare request body
        var body: [String: Any] = [
            "placeId": place.id,
            "placeName": place.name,
            "title": place.name,
            "description": "",
            "visibility": visibility,
            "tags": [],
            "contentType": contentType,
            "fileSize": photo.sizeInBytes,
            "duration": 0,
            "compressionRatio": photo.compressionRatio,
            "dimensions": [
                "width": photo.dimensions.width,
                "height": photo.dimensions.height
            ]
        ]
        
        // Add place creation data if needed
        addPlaceDataIfNeeded(to: &body, for: place, type: type)
        
        progress(UploadProgress(progress: 0.1, bytesUploaded: 0, totalBytes: Int64(photo.sizeInBytes), phase: .initiating))
        
        // Upload to backend
        uploadPhotoData(
            photo.data,
            body: body,
            endpoint: endpoint,
            progress: { uploadProgress in
                progress(UploadProgress(
                    progress: 0.1 + (uploadProgress * 0.9),
                    bytesUploaded: Int64(Double(photo.sizeInBytes) * uploadProgress),
                    totalBytes: Int64(photo.sizeInBytes),
                    phase: .uploading
                ))
            },
            completion: { result in
                switch result {
                case .success(let response):
                    progress(UploadProgress(progress: 1.0, bytesUploaded: Int64(photo.sizeInBytes), totalBytes: Int64(photo.sizeInBytes), phase: .completed))
                    
                    let storageResult = StorageResult(
                        mediaType: type,
                        place: place,
                        storageUrls: response.storageUrls ?? [:],
                        metadata: [:] // Empty metadata for now
                    )
                    completion(.success(storageResult))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Video Upload
    
    /// Upload processed video to Firebase Storage (unified for both Places and Moments)
    func uploadVideo(
        _ video: ProcessedVideo,
        for place: Place,
        type: MediaStorageType,
        visibility: String = "public",
        progress: @escaping (UploadProgress) -> Void = { _ in },
        completion: @escaping (Result<StorageResult, Error>) -> Void
    ) {
        progress(UploadProgress(progress: 0.0, bytesUploaded: 0, totalBytes: video.sizeInBytes, phase: .initiating))
        
        // Read video data
        guard let videoData = try? Data(contentsOf: video.url) else {
            completion(.failure(MediaStorageError.fileReadError))
            return
        }
        
        // Determine content type and API endpoint based on storage type
        let (contentType, endpoint) = getVideoUploadConfig(for: type)
        
        // Step 1: Initiate upload
        initiateVideoUpload(
            for: place,
            duration: video.duration,
            fileSize: Int(video.sizeInBytes),
            type: type,
            visibility: visibility,
            compressionRatio: video.compressionRatio
        ) { [weak self] initiateResult in
            switch initiateResult {
            case .success(let uploadInfo):
                progress(UploadProgress(progress: 0.1, bytesUploaded: 0, totalBytes: video.sizeInBytes, phase: .uploading))
                
                // Step 2: Upload video and thumbnail files
                self?.uploadVideoFiles(
                    videoData: videoData,
                    thumbnailData: video.thumbnailData,
                    uploadInfo: uploadInfo,
                    progress: { uploadProgress in
                        progress(UploadProgress(
                            progress: 0.1 + (uploadProgress * 0.8),
                            bytesUploaded: Int64(Double(video.sizeInBytes) * uploadProgress),
                            totalBytes: video.sizeInBytes,
                            phase: .uploading
                        ))
                    }
                ) { uploadResult in
                    switch uploadResult {
                    case .success:
                        progress(UploadProgress(progress: 0.9, bytesUploaded: video.sizeInBytes, totalBytes: video.sizeInBytes, phase: .finalizing))
                        
                        // Step 3: Complete upload
                        self?.completeVideoUpload(
                            videoId: uploadInfo.videoId,
                            storagePaths: uploadInfo.storagePaths,
                            originalSize: Int(video.sizeInBytes),
                            compressionRatio: video.compressionRatio
                        ) { completeResult in
                            switch completeResult {
                            case .success(let response):
                                progress(UploadProgress(progress: 1.0, bytesUploaded: video.sizeInBytes, totalBytes: video.sizeInBytes, phase: .completed))
                                
                                let storageResult = StorageResult(
                                    mediaType: type,
                                    place: place,
                                    storageUrls: response.storageUrls ?? [:],
                                    metadata: [:] // Empty metadata for now
                                )
                                completion(.success(storageResult))
                                
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Global Place Photo Upload
    
    /// Upload photo directly to Global Place system
    private func uploadPhotoToGlobalPlace(
        _ photo: ProcessedPhoto,
        for place: Place,
        visibility: String,
        progress: @escaping (UploadProgress) -> Void,
        completion: @escaping (Result<StorageResult, Error>) -> Void
    ) {
        print("📸 [MediaStorageService] Starting Global Place photo upload for place: \(place.name)")
        
        // Step 1: Upload image to Firebase Storage first
        progress(UploadProgress(progress: 0.1, bytesUploaded: 0, totalBytes: Int64(photo.sizeInBytes), phase: .uploading))
        
        // Convert image to JPEG data for upload
        guard let imageData = photo.image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "MediaStorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG data"])))
            return
        }
        
        PlaceService.shared.uploadImage(imageData) { [weak self] (result: Result<String, Error>) in
            switch result {
            case .success(let storageURL):
                print("✅ [MediaStorageService] Image uploaded to Firebase Storage: \(storageURL)")
                progress(UploadProgress(progress: 0.7, bytesUploaded: Int64(photo.sizeInBytes), totalBytes: Int64(photo.sizeInBytes), phase: .finalizing))
                
                // Step 2: Register photo with Global Place system
                self?.registerPhotoWithGlobalPlace(
                    storageURL: storageURL,
                    photo: photo,
                    place: place,
                    visibility: visibility,
                    progress: progress,
                    completion: completion
                )
                
            case .failure(let error):
                print("❌ [MediaStorageService] Firebase Storage upload failed: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Register uploaded photo with Global Place system
    private func registerPhotoWithGlobalPlace(
        storageURL: String,
        photo: ProcessedPhoto,
        place: Place,
        visibility: String,
        progress: @escaping (UploadProgress) -> Void,
        completion: @escaping (Result<StorageResult, Error>) -> Void
    ) {
        print("📝 [MediaStorageService] Registering photo with Global Place system...")
        
        // Use globalPlaceId if available, otherwise fall back to legacy place ID
        let placeIdToUse = place.globalPlaceId ?? place.id
        print("🆔 [MediaStorageService] Using place ID: \(placeIdToUse) (globalPlaceId: \(place.globalPlaceId ?? "none"), legacyId: \(place.id))")
        
        // Use GlobalPlaceService to register the photo
        GlobalPlaceService.shared.uploadPlaceMedia(
            placeId: placeIdToUse,
            mediaType: "photo",
            mediaUrl: storageURL,
            title: place.name,
            description: ""
        ) { result in
            switch result {
            case .success(let attributedPhoto):
                print("✅ [MediaStorageService] Photo registered with Global Place system")
                progress(UploadProgress(progress: 1.0, bytesUploaded: Int64(photo.sizeInBytes), totalBytes: Int64(photo.sizeInBytes), phase: .completed))
                
                // Create successful result
                let storageResult = StorageResult(
                    mediaType: .placePhoto,
                    place: place,
                    storageUrls: ["photoUrl": storageURL],
                    metadata: [
                        "attributedPhotoId": attributedPhoto.id ?? "",
                        "uploadedTo": "globalPlace",
                        "visibility": visibility
                    ]
                )
                
                completion(.success(storageResult))
                
            case .failure(let error):
                print("❌ [MediaStorageService] Failed to register photo with Global Place: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func getPhotoUploadConfig(for type: MediaStorageType) -> (contentType: String, endpoint: String) {
        switch type {
        case .placePhoto:
            return ("photo", "places/global/media/upload") // Use Global Place system for place photos
        case .momentPhoto:
            return ("photo", "videos/upload/initiate")
        case .placeVideo, .momentVideo:
            return ("video", "videos/upload/initiate")
        }
    }
    
    private func getVideoUploadConfig(for type: MediaStorageType) -> (contentType: String, endpoint: String) {
        switch type {
        case .placeVideo:
            return ("video", "videos/upload/initiate")
        case .momentVideo:
            return ("video", "videos/upload/initiate")
        case .placePhoto, .momentPhoto:
            return ("photo", "videos/upload/initiate")
        }
    }
    
    private func addPlaceDataIfNeeded(to body: inout [String: Any], for place: Place, type: MediaStorageType) {
        // Check if this is a new place (not from existing places)
        let isNewPlace = place.circleId?.isEmpty ?? true
        body["isNewPlace"] = isNewPlace
        
        if isNewPlace {
            body["placeAddress"] = place.address
            body["placeCoordinates"] = place.location?.coordinates ?? []
            body["placeCategory"] = place.category.rawValue
            body["placeDescription"] = place.description ?? ""
            body["placePhone"] = place.phone ?? ""
            body["placeWebsite"] = place.website ?? ""
        }
    }
    
    private func uploadPhotoData(
        _ data: Data,
        body: [String: Any],
        endpoint: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<PhotoUploadResponse, Error>) -> Void
    ) {
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        let contentType = "multipart/form-data; boundary=\(boundary)"
        
        var formData = Data()
        
        // Add JSON body as form field
        if let jsonData = try? JSONSerialization.data(withJSONObject: body) {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"data\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            formData.append(jsonData)
            formData.append("\r\n".data(using: .utf8)!)
        }
        
        // Add image file
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        formData.append(data)
        formData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Make request
        guard let url = URL(string: "\(APIEnvironment.current.baseURL)/\(endpoint)") else {
            completion(.failure(MediaStorageError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AuthService.shared.getToken() ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = formData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(MediaStorageError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(PhotoUploadResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    private func initiateVideoUpload(
        for place: Place,
        duration: TimeInterval,
        fileSize: Int,
        type: MediaStorageType,
        visibility: String,
        compressionRatio: Float,
        completion: @escaping (Result<VideoUploadInitiateResponse, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "placeId": place.id,
            "placeName": place.name,
            "duration": duration,
            "fileSize": fileSize,
            "visibility": visibility,
            "compressionRatio": compressionRatio,
            "contentType": "video"
        ]
        
        APIService.shared.request(
            endpoint: "videos/upload/initiate",
            method: .post,
            body: body
        ) { (result: Result<VideoUploadInitiateResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func uploadVideoFiles(
        videoData: Data,
        thumbnailData: Data,
        uploadInfo: VideoUploadInitiateResponse,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // This would implement the Firebase Storage upload logic
        // For now, simulate the upload process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            completion(.success(()))
        }
    }
    
    private func completeVideoUpload(
        videoId: String,
        storagePaths: MediaStorageVideoStoragePaths,
        originalSize: Int,
        compressionRatio: Float,
        completion: @escaping (Result<VideoUploadCompleteResponse, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "storagePaths": [
                "video": storagePaths.video,
                "preview": storagePaths.preview,
                "thumbnail": storagePaths.thumbnail
            ],
            "originalSize": originalSize,
            "compressionRatio": compressionRatio
        ]
        
        APIService.shared.request(
            endpoint: "videos/\(videoId)/upload/complete",
            method: .post,
            body: body
        ) { (result: Result<VideoUploadCompleteResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Response Types
struct PhotoUploadResponse: Codable {
    let success: Bool
    let message: String?
    let storageUrls: [String: String]?
    // Simplified - remove metadata for now to avoid Codable complexity
}

struct VideoUploadInitiateResponse: Codable {
    let success: Bool
    let videoId: String
    let uploadUrls: MediaStorageVideoUploadUrls
    let storagePaths: MediaStorageVideoStoragePaths
}

// MediaStorage-specific response structs (separate from VideoUploadService to avoid conflicts)
struct MediaStorageVideoUploadUrls: Codable {
    let video: String?
    let preview: String?
    let thumbnail: String?
}

struct MediaStorageVideoStoragePaths: Codable {
    let video: String?
    let preview: String?
    let thumbnail: String?
}

struct VideoUploadCompleteResponse: Codable {
    let success: Bool
    let message: String?
    let storageUrls: [String: String]?
    // Simplified - remove metadata for now to avoid Codable complexity
}


// MARK: - Media Storage Errors
enum MediaStorageError: LocalizedError {
    case invalidURL
    case fileReadError
    case noData
    case uploadFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid upload URL"
        case .fileReadError:
            return "Failed to read file data"
        case .noData:
            return "No data received from server"
        case .uploadFailed:
            return "Upload failed"
        case .unknown:
            return "An unknown storage error occurred"
        }
    }
}